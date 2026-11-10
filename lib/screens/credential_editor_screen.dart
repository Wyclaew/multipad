import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../widgets/password_generator_dialog.dart';

class CredentialEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const CredentialEditorScreen({super.key, this.initialItem});

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
  late bool _isFavorite;
  late bool _isPinned;

  // Reminder state
  int _reminderMode = 0; // 0: Global, 1: Custom Days, 2: Specific Date, 3: Disabled
  DateTime? _selectedReminderDate;
  DateTime? _passwordLastModified;
  late String _initialPassword;
  late String _originalTitle;
  late String _originalUsername;

  bool _obscurePassword = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _initialPassword = item?.password ?? '';
    _originalTitle = item?.title ?? '';
    _originalUsername = item?.username ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _usernameController = TextEditingController(text: _originalUsername);
    _passwordController = TextEditingController(text: _initialPassword);
    _websiteController = TextEditingController(text: item?.website ?? '');
    _totpController = TextEditingController(text: item?.totpSecret ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();

    _tags = List<String>.from(item?.tags ?? []);
    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;

    _passwordLastModified = item?.passwordLastModified;
    _selectedReminderDate = item?.customReminderDate;

    if (item?.customExpiryDays == -1) {
      _reminderMode = 3; // Disabled
      _customDaysController = TextEditingController();
    } else if (item?.customReminderDate != null) {
      _reminderMode = 2; // Specific Date
      _customDaysController = TextEditingController();
    } else if (item?.customExpiryDays != null && item!.customExpiryDays! > 0) {
      _reminderMode = 1; // Custom Days
      _customDaysController = TextEditingController(text: item.customExpiryDays.toString());
    } else {
      _reminderMode = 0; // Global default
      _customDaysController = TextEditingController();
    }
  }

  @override
  void dispose() {
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

  bool get _hasUnsavedChanges {
    return _titleController.text != _originalTitle ||
        _usernameController.text != _originalUsername ||
        _passwordController.text != _initialPassword;
  }

  Future<void> _openPasswordGenerator() async {
    final generated = await showDialog<String>(
      context: context,
      builder: (ctx) => const PasswordGeneratorDialog(),
    );

    if (generated != null && generated.isNotEmpty) {
      setState(() {
        _passwordController.text = generated;
        _obscurePassword = false;
      });
    }
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
      setState(() {
        _selectedReminderDate = picked;
        _reminderMode = 2;
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _usernameController.text.isEmpty && _passwordController.text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    // Check if password changed to update passwordLastModified and history
    final newPass = _passwordController.text;
    final List<String> history = List.from(widget.initialItem?.passwordHistory ?? []);
    DateTime? lastMod = _passwordLastModified;

    if (newPass != _initialPassword) {
      lastMod = DateTime.now().toUtc();
      if (_initialPassword.isNotEmpty && !history.contains(_initialPassword)) {
        history.insert(0, _initialPassword);
      }
    }

    // Determine expiry settings
    int? customDays;
    DateTime? reminderDate;

    if (_reminderMode == 1) {
      customDays = int.tryParse(_customDaysController.text.trim());
    } else if (_reminderMode == 2) {
      reminderDate = _selectedReminderDate;
    } else if (_reminderMode == 3) {
      customDays = -1; // Disabled
    }

    final updatedItem = (widget.initialItem ?? vault.createNewCredential()).copyWith(
      title: title.isEmpty ? 'İsimsiz Hesap' : title,
      username: _usernameController.text.trim(),
      password: newPass,
      website: _websiteController.text.trim(),
      totpSecret: _totpController.text.trim().replaceAll(' ', ''),
      content: _notesController.text.trim(),
      tags: _tags,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
      passwordLastModified: lastMod,
      customExpiryDays: customDays,
      customReminderDate: reminderDate,
      passwordHistory: history,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    await vault.saveItem(updatedItem);
    _originalTitle = _titleController.text;
    _originalUsername = _usernameController.text;
    _initialPassword = newPass;
    setState(() => _isSaving = false);

    if (mounted) Navigator.of(context).pop();
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabı Çöpe Taşı'),
        content: const Text('Bu hesabı çöp kutusuna taşımak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Çöpe Taşı'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (widget.initialItem != null) {
        await context.read<VaultProvider>().moveToTrash(widget.initialItem!);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<bool> _handlePop() async {
    if (!_hasUnsavedChanges) return true;

    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş Değişiklikler'),
        content: const Text('Hesap bilgilerinde kaydedilmemiş değişiklikler var. Çıkmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Düzenlemeye Devam Et'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Değişiklikleri Sil'),
          ),
        ],
      ),
    );

    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dateFormat = DateFormat('dd MMMM yyyy');

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handlePop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initialItem == null ? 'Yeni Şifre / Hesap' : 'Hesap Düzenle'),
          actions: [
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              color: _isPinned ? Colors.blueAccent : null,
              tooltip: _isPinned ? 'Sabitlemeyi Kaldır' : 'Başa Sabitle',
              onPressed: () => setState(() => _isPinned = !_isPinned),
            ),
            IconButton(
              icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
              color: _isFavorite ? Colors.amber : null,
              tooltip: _isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
              onPressed: () => setState(() => _isFavorite = !_isFavorite),
            ),
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Çöpe Taşı',
                onPressed: _delete,
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: _isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Kaydet'),
              onPressed: _isSaving ? null : _save,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'Hesap / Servis Adı',
                      hintText: 'Örn: Google, GitHub, Banka',
                      prefixIcon: Icon(Icons.label_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Website / URL
                  TextField(
                    controller: _websiteController,
                    decoration: const InputDecoration(
                      labelText: 'Web Sitesi / URL (İsteğe bağlı)',
                      hintText: 'https://example.com',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Username / Email
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Kullanıcı Adı / E-posta',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Kullanıcı Adını Kopyala',
                        onPressed: () async {
                          if (_usernameController.text.isNotEmpty) {
                            await ClipboardService.copySecurely(_usernameController.text);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Kullanıcı adı kopyalandı!')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password with generator and copy actions
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(
                      fontFamily: _obscurePassword ? null : 'monospace',
                      letterSpacing: _obscurePassword ? 2 : 1,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            tooltip: _obscurePassword ? 'Şifreyi Göster' : 'Şifreyi Gizle',
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          IconButton(
                            icon: const Icon(Icons.auto_fix_high_outlined, color: Colors.blueAccent),
                            tooltip: 'Gelişmiş Şifre Motoru',
                            onPressed: _openPasswordGenerator,
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Şifreyi Kopyala (30 sn)',
                            onPressed: () async {
                              if (_passwordController.text.isNotEmpty) {
                                await ClipboardService.copySecurely(_passwordController.text);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Şifre kopyalandı! (30 sn sonra temizlenir)')),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2FA TOTP Secret Key field
                  TextField(
                    controller: _totpController,
                    decoration: const InputDecoration(
                      labelText: '2FA / TOTP Gizli Anahtarı veya otpauth:// URI',
                      hintText: 'JBSWY3DPEHPK3PXP... veya otpauth://...',
                      prefixIcon: Icon(Icons.phonelink_lock_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --------------------------------------------------------
                  // ŞİFRE YENİLEME VE GÜNCELLEME HATIRLATICISI (Item 30)
                  // --------------------------------------------------------
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.alarm_on_rounded, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Şifre Yenileme Hatırlatıcısı (Item 30)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Spacer(),
                              if (widget.initialItem != null)
                                Text(
                                  '${widget.initialItem!.passwordAgeDays} gündür güncel',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _reminderMode,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              labelText: 'Bu Şifre İçin Hatırlatma Kuralı',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(
                                  auth.globalPasswordExpiryDays > 0
                                      ? 'Genel Kasa Kuralını Kullan (${auth.globalPasswordExpiryDays} gün)'
                                      : 'Genel Kasa Kuralını Kullan (Kapalı)',
                                ),
                              ),
                              const DropdownMenuItem(value: 1, child: Text('Özel Gün Aralığı Belirle')),
                              const DropdownMenuItem(value: 2, child: Text('Spesifik Bir Hatırlatma Tarihi Seç')),
                              const DropdownMenuItem(value: 3, child: Text('Bu Şifre İçin Hatırlatmayı Kapat')),
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
                                labelText: 'Kaç günde bir yenileme hatırlatılsın?',
                                hintText: 'Örn: 45',
                                prefixIcon: Icon(Icons.timer_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ] else if (_reminderMode == 2) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedReminderDate != null
                                        ? 'Hatırlatma Tarihi: ${dateFormat.format(_selectedReminderDate!)}'
                                        : 'Henüz bir tarih seçilmedi.',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                                  label: const Text('Tarih Seç'),
                                  onPressed: _pickReminderDate,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tags
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
                        width: 130,
                        child: TextField(
                          controller: _tagInputController,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: '+ etiket ekle',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: _addTag,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Güvenli Ek Notlar (2FA Kurtarma Kodları, PIN vb.)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),

                  // Password History (if available)
                  if (widget.initialItem != null && widget.initialItem!.passwordHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    ExpansionTile(
                      title: Text(
                        'Eski Şifre Geçmişi (${widget.initialItem!.passwordHistory.length})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      children: widget.initialItem!.passwordHistory.map((oldPass) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(oldPass, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () => ClipboardService.copySecurely(oldPass),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
