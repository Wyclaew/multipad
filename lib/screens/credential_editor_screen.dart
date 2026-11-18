import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/clipboard_service.dart';
import '../services/hibp_service.dart';
import '../services/totp_migration_service.dart';
import '../services/totp_service.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/revision_history_sheet.dart';

class CredentialEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const CredentialEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<CredentialEditorScreen> createState() => _CredentialEditorScreenState();
}

class _CredentialEditorScreenState extends State<CredentialEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _websiteController;
  late TextEditingController _totpController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;
  late TextEditingController _customDaysController;

  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultItemRevision> _revisions;
  late List<VaultPasskey> _passkeys;
  String? _folderId;
  late bool _isFavorite;
  late bool _isPinned;
  bool _obscurePassword = true;
  bool _isSaving = false;

  int _reminderMode = 0; // 0: Global, 1: Custom Days, 2: Specific Date, 3: Disabled
  DateTime? _selectedReminderDate;
  DateTime? _passwordLastModified;

  bool _isCheckingBreach = false;
  int? _breachCount;
  String? _breachError;

  late String _originalTitle;
  late String _originalUsername;
  late String _initialPassword;
  late String? _originalFolderId;
  Timer? _totpTimer;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _originalTitle = item?.title ?? '';
    _originalUsername = item?.username ?? '';
    _initialPassword = item?.password ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _usernameController = TextEditingController(text: _originalUsername);
    _passwordController = TextEditingController(text: _initialPassword);
    _websiteController = TextEditingController(text: item?.website ?? '');
    _totpController = TextEditingController(text: item?.totpSecret ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();

    _tags = List<String>.from(item?.tags ?? const []);
    _customFields = List<CustomField>.from(item?.customFields ?? const []);
    _revisions = List<VaultItemRevision>.from(item?.revisions ?? const []);
    _passkeys = List<VaultPasskey>.from(item?.passkeys ?? const []);
    _folderId = item?.folderId ?? widget.initialFolderId;
    _originalFolderId = _folderId;

    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
    _passwordLastModified = item?.passwordLastModified;
    _selectedReminderDate = item?.customReminderDate;

    if (item?.customExpiryDays == -1) {
      _reminderMode = 3;
      _customDaysController = TextEditingController();
    } else if (item?.customReminderDate != null) {
      _reminderMode = 2;
      _customDaysController = TextEditingController();
    } else if (item?.customExpiryDays != null && item!.customExpiryDays! > 0) {
      _reminderMode = 1;
      _customDaysController = TextEditingController(
        text: item.customExpiryDays.toString(),
      );
    } else {
      _reminderMode = 0;
      _customDaysController = TextEditingController();
    }

    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _totpController.text.trim().isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _websiteController.dispose();
    _totpController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _usernameController.text != _originalUsername ||
      _passwordController.text != _initialPassword ||
      _folderId != _originalFolderId ||
      _passkeys.length != (widget.initialItem?.passkeys.length ?? 0);

  Future<void> _copyField(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _openPasswordGenerator() async {
    final generated = await showDialog<String>(
      context: context,
      builder: (ctx) => const PasswordGeneratorDialog(),
    );
    if (generated != null && generated.isNotEmpty) {
      setState(() {
        _passwordController.text = generated;
        _breachCount = null;
      });
    }
  }

  Future<void> _scanTotpQr() async {
    final raw = await QrScannerDialog.scan(
      context,
      title: '2FA QR Kod Tara',
      subtitle: 'Authenticator kurulum QR kodunu (otpauth://) tarayın veya ekran görüntüsü seçin.',
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;

    final trimmedRaw = raw.trim();
    if (trimmedRaw.toLowerCase().startsWith('otpauth-migration://')) {
      final mig = TotpMigrationService.parseGoogleMigrationUri(trimmedRaw);
      if (mig.accounts.length == 1) {
        final acc = mig.accounts.first;
        setState(() {
          _totpController.text = acc.storageTotpValue;
          if (_titleController.text.trim().isEmpty && acc.issuer.isNotEmpty) {
            _titleController.text = acc.issuer;
          }
          if (_usernameController.text.trim().isEmpty &&
              acc.accountName.isNotEmpty) {
            _usernameController.text = acc.accountName;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Authenticator 2FA hesabı aktarıldı.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mig.accounts.isEmpty
                  ? (mig.error ?? 'Google Authenticator QR çözümlenemedi.')
                  : 'Bu Google Authenticator QR kodunda ${mig.accounts.length} hesap var. Hepsini aktarmak için 2FA Kodları -> Aktar ekranını kullanın.',
            ),
          ),
        );
      }
      return;
    }

    final parsed = TotpService.parseOtpAuthUri(trimmedRaw);
    if (parsed != null) {
      setState(() {
        _totpController.text = TotpService.formatForVaultStorage(
          secret: parsed.secret,
          issuer: parsed.issuer,
          accountName: parsed.accountName,
          period: parsed.period,
          digits: parsed.digits,
          algorithm: parsed.algorithm,
        );
        if (_titleController.text.trim().isEmpty && parsed.issuer.isNotEmpty) {
          _titleController.text = parsed.issuer;
        }
        if (_usernameController.text.trim().isEmpty &&
            parsed.accountName.isNotEmpty) {
          _usernameController.text = parsed.accountName;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA (TOTP) anahtarı QR koddan aktarıldı.')),
      );
    } else if (TotpService.isValidBase32(trimmedRaw)) {
      setState(() => _totpController.text = TotpService.normalizeBase32(trimmedRaw));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base32 2FA anahtarı aktarıldı.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR kod geçerli bir otpauth:// veya Base32 TOTP anahtarı içermiyor.'),
        ),
      );
    }
  }

  void _showAddPasskeyDialog() {
    String suggestedRpId = '';
    final web = _websiteController.text.trim();
    if (web.isNotEmpty) {
      try {
        final uri = Uri.parse(web.startsWith('http') ? web : 'https://$web');
        suggestedRpId = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      } catch (_) {
        suggestedRpId = web;
      }
    }
    if (suggestedRpId.isEmpty) {
      final user = _usernameController.text.trim();
      if (user.contains('@')) {
        suggestedRpId = user.split('@').last;
      }
    }

    final rpController = TextEditingController(text: suggestedRpId);
    final userController = TextEditingController(text: _usernameController.text.trim());
    final credIdController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.fingerprint, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('Passkey Ekle'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bu hesaba bir WebAuthn / FIDO2 Passkey kimliği bağlayın.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: rpController,
                  decoration: const InputDecoration(
                    labelText: 'Alan Adı / RP ID (örn. google.com)',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı Adı / E-posta',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: credIdController,
                  decoration: const InputDecoration(
                    labelText: 'Kimlik ID (Credential ID - İsteğe bağlı)',
                    hintText: 'Boş bırakılırsa otomatik üretilir',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final rpId = rpController.text.trim();
                if (rpId.isEmpty) return;
                final rawCredId = credIdController.text.trim();
                final credId = rawCredId.isNotEmpty
                    ? rawCredId
                    : base64UrlEncode(
                        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
                      );
                final userName = userController.text.trim();

                final newPasskey = VaultPasskey(
                  id: const Uuid().v4(),
                  credentialId: credId,
                  rpId: rpId,
                  rpName: rpId,
                  userName: userName,
                  createdAt: DateTime.now().toUtc(),
                );

                setState(() {
                  _passkeys.add(newPasskey);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickReminderDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedReminderDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _selectedReminderDate = picked);
    }
  }

  Future<void> _checkPasswordBreach() async {
    final pass = _passwordController.text;
    if (pass.isEmpty) return;

    setState(() {
      _isCheckingBreach = true;
      _breachCount = null;
      _breachError = null;
    });

    try {
      final result = await HibpService.checkPasswordBreach(pass);
      if (mounted) {
        setState(() {
          _isCheckingBreach = false;
          if (result.errorMessage != null) {
            _breachError = result.errorMessage;
          } else {
            _breachCount = result.breachCount;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingBreach = false;
          _breachError = 'Sızıntı veritabanına ulaşılamadı (İnternet gerekli).';
        });
      }
    }
  }

  Future<void> _saveCredential() async {
    final title = _titleController.text.trim();
    if (title.isEmpty &&
        _usernameController.text.isEmpty &&
        _passwordController.text.isEmpty &&
        _totpController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    final newPassword = _passwordController.text;
    final List<String> updatedHistory = List<String>.from(
      widget.initialItem?.passwordHistory ?? const [],
    );

    if (widget.initialItem != null &&
        _initialPassword.isNotEmpty &&
        newPassword != _initialPassword) {
      if (!updatedHistory.contains(_initialPassword)) {
        updatedHistory.insert(0, _initialPassword);
        if (updatedHistory.length > 10) updatedHistory.removeLast();
      }
      _passwordLastModified = DateTime.now().toUtc();
    } else if (widget.initialItem == null && newPassword.isNotEmpty) {
      _passwordLastModified = DateTime.now().toUtc();
    }

    int? customDays;
    DateTime? customDate;
    if (_reminderMode == 1) {
      customDays = int.tryParse(_customDaysController.text.trim());
    } else if (_reminderMode == 2) {
      customDate = _selectedReminderDate;
    } else if (_reminderMode == 3) {
      customDays = -1;
    }

    final updatedItem = (widget.initialItem ?? vault.createNewCredential())
        .copyWith(
          title: title.isEmpty ? 'Adsız Hesap' : title,
          username: _usernameController.text.trim(),
          password: newPassword,
          website: _websiteController.text.trim(),
          totpSecret: _totpController.text.trim(),
          passkeys: _passkeys,
          content: _notesController.text.trim(),
          folderId: _folderId,
          clearFolderId: _folderId == null,
          tags: _tags,
          customFields: _customFields,
          revisions: _revisions,
          passwordHistory: updatedHistory,
          passwordLastModified: _passwordLastModified,
          customExpiryDays: customDays,
          clearCustomExpiryDays: customDays == null,
          customReminderDate: customDate,
          clearCustomReminderDate: customDate == null,
          isFavorite: _isFavorite,
          isPinned: _isPinned,
        );

    await vault.saveItem(updatedItem);

    _originalTitle = _titleController.text;
    _originalUsername = _usernameController.text;
    _initialPassword = _passwordController.text;
    _originalFolderId = _folderId;

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
    }
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceAll('#', '');
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagInputController.clear();
      });
    }
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş Değişiklikler'),
        content: const Text(
          'Hesap bilgilerindeki değişiklikler kaydedilmedi. Çıkmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Düzenlemeye Devam Et'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Kaydetmeden Çık'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final passHistory = widget.initialItem?.passwordHistory ?? const [];
    final liveTotp = TotpService.generateDetailed(_totpController.text.trim());
    final websiteCheck = AuditService.checkWebsiteSecurity(
      _websiteController.text,
    );

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initialItem == null
                ? l10n.tr('Yeni Hesap / Şifre', 'New Login')
                : l10n.tr('Hesabı Düzenle', 'Edit Login'),
          ),
          actions: [
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: l10n.tr('Sürüm Geçmişi', 'Version History'),
                onPressed: () {
                  RevisionHistorySheet.show(
                    context,
                    item: widget.initialItem!.copyWith(
                      title: _titleController.text,
                      password: _passwordController.text,
                      content: _notesController.text,
                      revisions: _revisions,
                    ),
                    onRestore: (rev) {
                      setState(() {
                        _titleController.text = rev.title;
                        if (rev.password.isNotEmpty) {
                          _passwordController.text = rev.password;
                        }
                        _notesController.text = rev.content;
                      });
                    },
                  );
                },
              ),
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              color: _isPinned ? theme.colorScheme.primary : null,
              onPressed: () => setState(() => _isPinned = !_isPinned),
            ),
            IconButton(
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
              color: _isFavorite ? Colors.amber : null,
              onPressed: () => setState(() => _isFavorite = !_isFavorite),
            ),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.save,
                onPressed: _saveCredential,
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: l10n.tr(
                      'Hesap / Platform Adı (örn. Google, Steam)',
                      'Account / Platform Name',
                    ),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Kullanıcı Adı / E-posta', 'Username / Email'),
                    prefixIcon: const Icon(Icons.person_outline),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        if (_usernameController.text.isNotEmpty) {
                          _copyField(_usernameController.text, 'Kullanıcı adı');
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: (_) => setState(() {
                    _breachCount = null;
                    _breachError = null;
                  }),
                  decoration: InputDecoration(
                    labelText: l10n.tr('Şifre', 'Password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_fix_high),
                          tooltip: 'Güçlü Şifre Oluştur',
                          onPressed: _openPasswordGenerator,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            if (_passwordController.text.isNotEmpty) {
                              _copyField(_passwordController.text, 'Parola');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed:
                          _isCheckingBreach ? null : _checkPasswordBreach,
                      icon: _isCheckingBreach
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.security, size: 18),
                      label: const Text('Sızıntı Kontrolü (HIBP)'),
                    ),
                    const Spacer(),
                    if (_passwordLastModified != null)
                      Text(
                        'Son değişim: ${DateFormat('dd.MM.yyyy').format(_passwordLastModified!)}',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                  ],
                ),
                if (_breachCount != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: _breachCount! > 0
                          ? Colors.redAccent.withValues(alpha: 0.15)
                          : Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _breachCount! > 0
                              ? Icons.warning_amber_rounded
                              : Icons.verified_user,
                          color: _breachCount! > 0
                              ? Colors.redAccent
                              : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _breachCount! > 0
                                ? 'UYARI: Bu şifre $_breachCount kez veri sızıntılarında görülmüş! Değiştirmeniz önerilir.'
                                : 'Harika! Bu şifre bilinen sızıntılarda yer almıyor.',
                            style: TextStyle(
                              fontSize: 12,
                              color: _breachCount! > 0
                                  ? Colors.redAccent
                                  : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_breachError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _breachError!,
                      style: const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _websiteController,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Web Sitesi (URL)',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
                if (websiteCheck.issueType != null &&
                    websiteCheck.reason != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.phishing,
                          color: Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            websiteCheck.reason!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _totpController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '2FA (TOTP) Kurulum Anahtarı (İsteğe bağlı)',
                    hintText: 'Base32 secret veya otpauth://...',
                    prefixIcon: const Icon(Icons.qr_code),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'QR Kod Tara (2FA)',
                      onPressed: _scanTotpQr,
                    ),
                  ),
                ),
                if (liveTotp.isValid) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(
                        liveTotp.formattedCode,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 2,
                        ),
                      ),
                      subtitle: Text(
                        'Kalan süre: ${liveTotp.remainingSeconds} / ${liveTotp.period} sn (${liveTotp.algorithm.uriName})',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => _copyField(liveTotp.code, '2FA kodu'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.purpleAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.fingerprint,
                            color: Colors.purpleAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Passkey (FIDO2 / WebAuthn)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Passkey Ekle'),
                            onPressed: _showAddPasskeyDialog,
                          ),
                        ],
                      ),
                      if (_passkeys.isEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Bu hesaba bağlı bir passkey yok. "Passkey Ekle" ile ekleyebilir veya Bitwarden dışa aktarımı ile otomatik içe aktarabilirsiniz.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        ..._passkeys.asMap().entries.map((entry) {
                          final index = entry.key;
                          final p = entry.value;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: theme.colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: Colors.purpleAccent.withValues(alpha: 0.2),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: const CircleAvatar(
                                radius: 15,
                                backgroundColor: Color(0x22AB47BC),
                                child: Icon(
                                  Icons.fingerprint,
                                  color: Colors.purpleAccent,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                p.rpId,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Kullanıcı: ${p.userName.isNotEmpty ? p.userName : (_usernameController.text.isNotEmpty ? _usernameController.text : "Belirtilmemiş")}\nID: ${p.credentialId.length > 24 ? "${p.credentialId.substring(0, 24)}..." : p.credentialId}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                tooltip: 'Passkey\'i Kaldır',
                                onPressed: () {
                                  setState(() {
                                    _passkeys.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                            color: Colors.amber,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Şifre Yenileme Hatırlatıcısı',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _reminderMode,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(
                              'Varsayılan Ayar (${auth.globalPasswordExpiryDays == 0 ? "Kapalı" : "${auth.globalPasswordExpiryDays} Gün"})',
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 1,
                            child: Text('Özel Periyot (Gün Olarak)'),
                          ),
                          const DropdownMenuItem(
                            value: 2,
                            child: Text('Belirli Bir Tarih Seç'),
                          ),
                          const DropdownMenuItem(
                            value: 3,
                            child: Text('Bu Hesap İçin Hatırlatma Yok'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _reminderMode = val);
                        },
                      ),
                      if (_reminderMode == 1) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customDaysController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kaç günde bir hatırlatılsın? (örn. 30)',
                            isDense: true,
                          ),
                        ),
                      ],
                      if (_reminderMode == 2) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickReminderDate,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            _selectedReminderDate == null
                                ? 'Tarih Seçin'
                                : 'Hatırlatma: ${DateFormat('dd.MM.yyyy').format(_selectedReminderDate!)}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._tags.map(
                      (tag) => Chip(
                        label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _removeTag(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _tagInputController,
                        decoration: const InputDecoration(
                          hintText: '+ Etiket ekle',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ek Notlar / Kurtarma Kodları',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                CustomFieldsEditor(
                  fields: _customFields,
                  onChanged: (next) => setState(() => _customFields = next),
                ),
                if (passHistory.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Eski Şifre Geçmişi (${passHistory.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...passHistory.map(
                    (oldPass) => Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          '•' * oldPass.length,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: const Text('Önceki parola'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, size: 18),
                              tooltip: 'Bu Parolayı Geri Yükle',
                              onPressed: () {
                                setState(() {
                                  _passwordController.text = oldPass;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () => _copyField(oldPass, 'Eski parola'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
