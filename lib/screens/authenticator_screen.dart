import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../services/totp_migration_service.dart';
import '../services/totp_service.dart';
import '../services/totp_ticker_service.dart';
import '../widgets/qr_scanner_dialog.dart';
import 'credential_editor_screen.dart';

/// Dedicated live TOTP Authenticator view supporting 30s/custom-period codes
/// and multi-app migration (Google Authenticator, Aegis, 2FAS, Ente, Bitwarden,
/// plus guided transfer for Microsoft Authenticator & Duo Mobile).
class AuthenticatorScreen extends StatefulWidget {
  final bool openImportOnStart;

  const AuthenticatorScreen({
    super.key,
    this.openImportOnStart = false,
  });

  @override
  State<AuthenticatorScreen> createState() => _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends State<AuthenticatorScreen> {
  final _searchCtrl = TextEditingController();
  StreamSubscription<int>? _tickerSub;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _tickerSub = TotpTickerService.instance.tickStream.listen((nowMs) {
      if (mounted) {
        setState(() {
          _nowMs = nowMs;
        });
      }
    });

    if (widget.openImportOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openMigrationWizard();
        }
      });
    }
  }

  @override
  void dispose() {
    _tickerSub?.cancel();
    _tickerSub = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VaultItem> _totpItems(VaultProvider vault) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final items = vault.allItems
        .where(
          (i) =>
              !i.isTrash &&
              !i.isDeleted &&
              i.type == VaultItemType.credential &&
              i.totpSecret.trim().isNotEmpty,
        )
        .toList();

    if (q.isEmpty) return items;
    return items.where((i) {
      return i.title.toLowerCase().contains(q) ||
          i.username.toLowerCase().contains(q) ||
          i.website.toLowerCase().contains(q) ||
          i.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _copyCode(TotpDetailedCode detailed) async {
    if (!detailed.isValid) return;
    await ClipboardService.copySecurely(detailed.code);
    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.copiedWithTimeout(
            l10n.tr('2FA doğrulama kodu', '2FA verification code'),
            ClipboardService.defaultTimeoutSeconds,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openMigrationWizard({String? initialRawPayload}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TotpMigrationSheet(
        initialRawPayload: initialRawPayload,
      ),
    );
  }

  Future<void> _openAddSingleDialog() async {
    final result = await showModalBottomSheet<_SingleAddResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddSingleTotpSheet(),
    );

    if (result == null || !mounted) return;
    if (result.redirectMigrationPayload != null) {
      await _openMigrationWizard(
        initialRawPayload: result.redirectMigrationPayload,
      );
      return;
    }

    final vault = context.read<VaultProvider>();
    final l10n = context.l10n;

    if (result.mergeTarget != null) {
      final updated = result.mergeTarget!.copyWith(
        totpSecret: result.storageSecret,
      );
      await vault.saveItem(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.tr(
                '2FA kodu "${updated.title}" hesabına bağlandı.',
                '2FA code attached to "${updated.title}".',
              ),
            ),
          ),
        );
      }
      return;
    }

    final created = vault.createNewCredential().copyWith(
          title: result.title,
          username: result.account,
          totpSecret: result.storageSecret,
          tags: const ['2FA'],
        );
    await vault.saveItem(created);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              '"${created.title}" için 2FA doğrulayıcı eklendi.',
              'Added 2FA authenticator for "${created.title}".',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showMigrationGuide() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _MigrationGuideSheet(),
    );
  }

  void _showBackupQrDialog(VaultItem item, TotpDetailedCode detailed) {
    final l10n = context.l10n;
    final uri = TotpService.buildOtpAuthUri(
      secret: detailed.normalizedSecret,
      issuer: item.title.isNotEmpty ? item.title : detailed.issuer,
      accountName: item.username.isNotEmpty ? item.username : detailed.accountName,
      period: detailed.period,
      digits: detailed.digits,
      algorithm: detailed.algorithm,
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.tr('2FA Yedek QR Kodu', '2FA Backup QR Code'),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title.isEmpty ? '2FA' : item.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (item.username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.username,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).hintColor,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: uri,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.tr(
                  'Dikkat: Bu QR kodu gören herkes aynı 2FA kodlarını üretebilir. Güvenli tutun.',
                  'Warning: Anyone seeing this QR can generate your 2FA codes. Keep it private.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ClipboardService.copySecurely(detailed.normalizedSecret);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.tr(
                      'Base32 gizli anahtar kopyalandı.',
                      'Base32 secret copied.',
                    ),
                  ),
                ),
              );
            },
            child: Text(l10n.tr('Anahtarı Kopyala', 'Copy Key')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.tr('Kapat', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveTotp(VaultItem item) async {
    final l10n = context.l10n;
    final vault = context.read<VaultProvider>();
    final hasPasswordData =
        item.password.isNotEmpty || item.website.isNotEmpty;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.tr('2FA Kaydını Kaldır', 'Remove 2FA Entry'),
        ),
        content: Text(
          hasPasswordData
              ? l10n.tr(
                  '"${item.title}" kaydında kayıtlı parola/web sitesi bilgisi var. Yalnızca 2FA anahtarını mı kaldırmak istersiniz?',
                  '"${item.title}" also stores a password/URL. Remove only the 2FA key or trash the whole entry?',
                )
              : l10n.tr(
                  '"${item.title}" 2FA kaydı Çöp Kutusuna taşınsın mı?',
                  'Move "${item.title}" 2FA entry to Trash?',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          if (hasPasswordData)
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, 'strip_totp'),
              child: Text(l10n.tr('Sadece 2FA Kaldır', 'Remove 2FA Only')),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, 'trash'),
            child: Text(
              hasPasswordData
                  ? l10n.tr('Tüm Kaydı Çöpe At', 'Move All to Trash')
                  : l10n.tr('Çöpe Taşı', 'Move to Trash'),
            ),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;
    if (action == 'strip_totp') {
      await vault.saveItem(item.copyWith(totpSecret: ''));
    } else if (action == 'trash') {
      await vault.moveToTrash(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vault = context.watch<VaultProvider>();
    final items = _totpItems(vault);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authenticator),
        actions: [
          IconButton(
            tooltip: l10n.tr(
              'Aktarım Rehberi (Google / MS / Duo)',
              'Migration Guide (Google / MS / Duo)',
            ),
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: _showMigrationGuide,
          ),
          IconButton(
            tooltip: l10n.tr(
              'Uygulamalardan Aktar',
              'Import from Other Authenticators',
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => _openMigrationWizard(),
          ),
          IconButton(
            tooltip: l10n.tr('Manuel / Tekli Ekle', 'Add Single 2FA'),
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: _openAddSingleDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.tr(
                      'Servis, e-posta veya etiket ara...',
                      'Search issuer, account, or tag...',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: Text(
                          l10n.tr(
                            'Google / Aegis / 2FAS / Ente Aktar',
                            'Import Google / Aegis / 2FAS / Ente',
                          ),
                        ),
                        onPressed: () => _openMigrationWizard(),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: Text(l10n.tr('Tekli 2FA Ekle', 'Add 2FA')),
                        onPressed: _openAddSingleDialog,
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.menu_book_outlined, size: 18),
                        label: Text(
                          l10n.tr(
                            'MS Auth & Duo Rehberi',
                            'MS Auth & Duo Guide',
                          ),
                        ),
                        onPressed: _showMigrationGuide,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) {
                      final item = items[idx];
                      final detailed = TotpService.generateDetailed(
                        item.totpSecret,
                        timeMs: _nowMs,
                      );
                      return _TotpAccountCard(
                        item: item,
                        detailed: detailed,
                        onCopy: () => _copyCode(detailed),
                        onEdit: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CredentialEditorScreen(initialItem: item),
                          ),
                        ),
                        onShowBackupQr: () =>
                            _showBackupQrDialog(item, detailed),
                        onRemove: () => _confirmRemoveTotp(item),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMigrationWizard(),
        icon: const Icon(Icons.move_to_inbox_rounded),
        label: Text(l10n.tr('2FA Aktar', 'Import 2FA')),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isFiltering = _searchCtrl.text.trim().isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 88),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 16),
              Text(
                isFiltering
                    ? l10n.tr(
                        'Aramayla eşleşen 2FA kaydı yok',
                        'No 2FA entries match your search',
                      )
                    : l10n.tr(
                        'Henüz 2FA Doğrulayıcı Kodu Eklenmemiş',
                        'No 2FA Authenticator Codes Yet',
                      ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tr(
                  'Google Authenticator dışa aktarma QR kodunuzu tarayın, Aegis / 2FAS / Ente yedeğini içe aktarın veya gizli anahtarınızı manuel ekleyin. Kodlar tüm cihazlarınıza şifreli olarak senkronlanır.',
                  'Scan your Google Authenticator export QR, import Aegis / 2FAS / Ente backups, or add secrets manually. All codes sync E2EE across your devices.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openMigrationWizard(),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(
                  l10n.tr(
                    'Diğer Uygulamalardan Aktar',
                    'Import from Other Apps',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openAddSingleDialog,
                icon: const Icon(Icons.add),
                label: Text(l10n.tr('Tekli 2FA Kodu Ekle', 'Add Single 2FA')),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _showMigrationGuide,
                icon: const Icon(Icons.info_outline, size: 18),
                label: Text(
                  l10n.tr(
                    'Microsoft Auth & Duo Nasıl Taşınır?',
                    'How to migrate Microsoft Auth & Duo?',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotpAccountCard extends StatelessWidget {
  final VaultItem item;
  final TotpDetailedCode detailed;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onShowBackupQr;
  final VoidCallback onRemove;

  const _TotpAccountCard({
    required this.item,
    required this.detailed,
    required this.onCopy,
    required this.onEdit,
    required this.onShowBackupQr,
    required this.onRemove,
  });

  String _initials() {
    final src = (item.title.trim().isNotEmpty
            ? item.title.trim()
            : (detailed.issuer.isNotEmpty ? detailed.issuer : '2FA'))
        .toUpperCase();
    final parts = src.split(RegExp(r'[\s._-]+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return src.length >= 2 ? src.substring(0, 2) : src;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isUrgent = detailed.remainingSeconds <= 5;
    final ringColor = isUrgent ? Colors.redAccent : theme.colorScheme.primary;
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : (detailed.issuer.isNotEmpty ? detailed.issuer : '2FA Hesabı');
    final accountLabel = item.username.trim().isNotEmpty
        ? item.username.trim()
        : detailed.accountName;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: detailed.isValid ? onCopy : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                child: Text(
                  _initials(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!item.isTotpOnly) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: l10n.tr(
                              'Kayıtlı şifreyle eşli',
                              'Linked to stored password',
                            ),
                            child: Icon(
                              Icons.link_rounded,
                              size: 16,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (accountLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        accountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (detailed.isValid)
                      Row(
                        children: [
                          Text(
                            detailed.formattedCode,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.2,
                              color: isUrgent
                                  ? Colors.redAccent
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (detailed.algorithm != TotpAlgorithm.sha1 ||
                              detailed.digits != 6 ||
                              detailed.period != 30)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${detailed.algorithm.uriName}•${detailed.period}s',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.hintColor,
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      Text(
                        l10n.tr('Geçersiz TOTP anahtarı', 'Invalid TOTP key'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    if (detailed.isValid && isUrgent && detailed.nextCode.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${l10n.tr("Sonraki", "Next")}: ${detailed.formattedNextCode}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (detailed.isValid) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: detailed.progress,
                            strokeWidth: 3.2,
                            color: ringColor,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                          Text(
                            '${detailed.remainingSeconds}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isUrgent ? Colors.redAccent : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: l10n.tr('Kodu Kopyala', 'Copy Code'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onCopy,
                    ),
                  ],
                ),
              ],
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'qr') onShowBackupQr();
                  if (value == 'remove') onRemove();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(
                        l10n.tr('Düzenle / Şifre Ekle', 'Edit / Add Password'),
                      ),
                    ),
                  ),
                  if (detailed.isValid)
                    PopupMenuItem(
                      value: 'qr',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.qr_code_2),
                        title: Text(
                          l10n.tr('Yedek QR Göster', 'Show Backup QR'),
                        ),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        l10n.tr('Kaldır', 'Remove'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SingleAddResult {
  final String title;
  final String account;
  final String storageSecret;
  final VaultItem? mergeTarget;
  final String? redirectMigrationPayload;

  const _SingleAddResult({
    this.title = '',
    this.account = '',
    this.storageSecret = '',
    this.mergeTarget,
    this.redirectMigrationPayload,
  });
}

class _AddSingleTotpSheet extends StatefulWidget {
  const _AddSingleTotpSheet();

  @override
  State<_AddSingleTotpSheet> createState() => _AddSingleTotpSheetState();
}

class _AddSingleTotpSheetState extends State<_AddSingleTotpSheet> {
  final _titleCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  TotpAlgorithm _algorithm = TotpAlgorithm.sha1;
  int _digits = 6;
  int _period = 30;
  String? _mergeItemId;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _accountCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final raw = await QrScannerDialog.scan(
      context,
      title: '2FA QR Kod Tara',
      subtitle:
          'Herhangi bir sitenin 2FA QR kodunu (otpauth://) tarayın veya ekran görüntüsü seçin.',
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;

    final trimmed = raw.trim();
    if (trimmed.toLowerCase().startsWith('otpauth-migration://')) {
      Navigator.pop(
        context,
        _SingleAddResult(redirectMigrationPayload: trimmed),
      );
      return;
    }

    _applyRawSecretOrUri(trimmed);
  }

  void _applyRawSecretOrUri(String raw) {
    final parsed = TotpService.parseOtpAuthUri(raw);
    if (parsed != null) {
      setState(() {
        _error = null;
        _secretCtrl.text = parsed.secret;
        if (_titleCtrl.text.trim().isEmpty && parsed.issuer.isNotEmpty) {
          _titleCtrl.text = parsed.issuer;
        }
        if (_accountCtrl.text.trim().isEmpty && parsed.accountName.isNotEmpty) {
          _accountCtrl.text = parsed.accountName;
        }
        _algorithm = parsed.algorithm;
        _digits = parsed.digits;
        _period = parsed.period;
      });
    } else if (TotpService.isValidBase32(raw)) {
      setState(() {
        _error = null;
        _secretCtrl.text = TotpService.normalizeBase32(raw);
      });
    } else {
      setState(() {
        _error = 'Geçerli bir Base32 anahtarı veya otpauth:// QR algılanamadı.';
      });
    }
  }

  void _submit(List<VaultItem> mergeTargets) {
    final rawSecret = _secretCtrl.text.trim();
    final parsedUri = TotpService.parseOtpAuthUri(rawSecret);

    String normalizedSecret;
    TotpAlgorithm algo = _algorithm;
    int digits = _digits;
    int period = _period;
    String title = _titleCtrl.text.trim();
    String account = _accountCtrl.text.trim();

    if (parsedUri != null) {
      normalizedSecret = parsedUri.secret;
      algo = parsedUri.algorithm;
      digits = parsedUri.digits;
      period = parsedUri.period;
      if (title.isEmpty) title = parsedUri.issuer;
      if (account.isEmpty) account = parsedUri.accountName;
    } else {
      normalizedSecret = TotpService.normalizeBase32(rawSecret);
    }

    if (normalizedSecret.isEmpty || !TotpService.isValidBase32(normalizedSecret)) {
      setState(() {
        _error = 'Lütfen geçerli bir Base32 gizli anahtarı (A-Z, 2-7) girin.';
      });
      return;
    }

    final storageSecret = TotpService.formatForVaultStorage(
      secret: normalizedSecret,
      issuer: title,
      accountName: account,
      period: period,
      digits: digits,
      algorithm: algo,
    );

    VaultItem? selectedMerge;
    if (_mergeItemId != null) {
      for (final m in mergeTargets) {
        if (m.id == _mergeItemId) {
          selectedMerge = m;
          break;
        }
      }
    }

    Navigator.pop(
      context,
      _SingleAddResult(
        title: title.isEmpty ? '2FA Hesabı' : title,
        account: account,
        storageSecret: storageSecret,
        mergeTarget: selectedMerge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final vault = context.watch<VaultProvider>();
    final mergeCandidates = vault.allItems
        .where(
          (i) =>
              !i.isTrash &&
              !i.isDeleted &&
              i.type == VaultItemType.credential &&
              i.totpSecret.trim().isEmpty,
        )
        .toList();

    final previewUri = TotpService.isValidBase32(
      TotpService.extractNormalizedSecret(_secretCtrl.text),
    )
        ? TotpService.formatForVaultStorage(
            secret: TotpService.extractNormalizedSecret(_secretCtrl.text),
            period: _period,
            digits: _digits,
            algorithm: _algorithm,
          )
        : '';
    final previewCode = previewUri.isNotEmpty
        ? TotpService.generateDetailed(previewUri)
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr('Tekli 2FA Hesabı Ekle', 'Add Single 2FA Account'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(l10n.tr('QR Tara / Seç', 'Scan / Pick QR')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('Servis / Site (örn. GitHub)', 'Service / Issuer'),
                prefixIcon: const Icon(Icons.apps_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('Hesap / E-posta', 'Account / Email'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secretCtrl,
              onChanged: (v) {
                if (v.trim().toLowerCase().startsWith('otpauth://')) {
                  _applyRawSecretOrUri(v.trim());
                } else {
                  setState(() => _error = null);
                }
              },
              decoration: InputDecoration(
                labelText: l10n.tr(
                  'Gizli Anahtar (Base32 veya otpauth://)',
                  'Secret Key (Base32 or otpauth://)',
                ),
                prefixIcon: const Icon(Icons.vpn_key_outlined),
              ),
            ),
            if (previewCode != null && previewCode.isValid) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.tr('Canlı Önizleme:', 'Live Preview:'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      previewCode.formattedCode,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (mergeCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey(_mergeItemId),
                initialValue: _mergeItemId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.tr(
                    'Mevcut Şifre Kaydına Bağla (İsteğe bağlı)',
                    'Attach to Existing Login (Optional)',
                  ),
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      l10n.tr(
                        'Yeni bağımsız 2FA kaydı oluştur',
                        'Create standalone 2FA entry',
                      ),
                    ),
                  ),
                  ...mergeCandidates.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(
                        c.username.isNotEmpty
                            ? '${c.title} (${c.username})'
                            : c.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _mergeItemId = v),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                l10n.tr('Gelişmiş TOTP Parametreleri', 'Advanced TOTP Settings'),
                style: const TextStyle(fontSize: 13),
              ),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TotpAlgorithm>(
                        key: ValueKey(_algorithm),
                        initialValue: _algorithm,
                        decoration: const InputDecoration(
                          labelText: 'Algoritma',
                          isDense: true,
                        ),
                        items: TotpAlgorithm.values
                            .map(
                              (a) => DropdownMenuItem(
                                value: a,
                                child: Text(a.uriName),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _algorithm = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(_digits),
                        initialValue: _digits,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Hane', 'Digits'),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 6, child: Text('6')),
                          DropdownMenuItem(value: 8, child: Text('8')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _digits = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(_period),
                        initialValue: _period,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Süre', 'Period'),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30 sn')),
                          DropdownMenuItem(value: 60, child: Text('60 sn')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _period = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _submit(mergeCandidates),
              icon: const Icon(Icons.check),
              label: Text(l10n.tr('2FA Kaydını Ekle', 'Save 2FA Entry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotpMigrationSheet extends StatefulWidget {
  final String? initialRawPayload;

  const _TotpMigrationSheet({this.initialRawPayload});

  @override
  State<_TotpMigrationSheet> createState() => _TotpMigrationSheetState();
}

class _TotpMigrationSheetState extends State<_TotpMigrationSheet> {
  final List<MigratedTotpAccount> _accumulatedAccounts = [];
  final List<String> _warnings = [];
  final Set<int> _scannedBatchIndices = {};
  int _expectedBatchSize = 1;
  List<TotpImportCandidate> _candidates = [];
  String? _error;
  bool _isSaving = false;
  Timer? _previewTicker;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _previewTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
      }
    });
    if (widget.initialRawPayload != null &&
        widget.initialRawPayload!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ingestRawPayload(widget.initialRawPayload!);
        }
      });
    }
  }

  @override
  void dispose() {
    _previewTicker?.cancel();
    super.dispose();
  }

  void _ingestRawPayload(String raw) {
    final res = TotpMigrationService.parseInput(raw);
    if (res.hasError) {
      setState(() => _error = res.error);
      return;
    }

    setState(() {
      _error = null;
      for (final w in res.warnings) {
        if (!_warnings.contains(w)) _warnings.add(w);
      }

      if (res.googleBatch != null) {
        _expectedBatchSize = res.googleBatch!.batchSize;
        _scannedBatchIndices.add(res.googleBatch!.batchIndex);
      }

      final existingSecrets = _accumulatedAccounts.map((a) => a.secret).toSet();
      for (final acc in res.accounts) {
        if (existingSecrets.add(acc.secret)) {
          _accumulatedAccounts.add(acc);
        }
      }

      final vault = context.read<VaultProvider>();
      final previousSelection = {
        for (final c in _candidates) c.account.secret: c.selected,
      };
      final previousDisposition = {
        for (final c in _candidates) c.account.secret: c.disposition,
      };

      _candidates = TotpMigrationService.planImport(
        _accumulatedAccounts,
        vault.allItems,
      );

      for (final c in _candidates) {
        if (previousSelection.containsKey(c.account.secret)) {
          c.selected = previousSelection[c.account.secret]!;
        }
        if (previousDisposition.containsKey(c.account.secret)) {
          c.disposition = previousDisposition[c.account.secret]!;
        }
      }
    });
  }

  Future<void> _scanQr() async {
    final raw = await QrScannerDialog.scan(
      context,
      title: 'Google Auth / 2FA QR Tara',
      subtitle:
          'Google Authenticator dışa aktarma QR kodunu (veya ekran görüntüsünü) tarayın.',
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    _ingestRawPayload(raw);
  }

  Future<void> _pickBackupFile() async {
    final auth = context.read<AuthProvider>();
    final result = await auth.runWithoutAutoLock(
      () => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', '2fas', 'txt'],
        withData: true,
      ),
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final picked = result.files.first;
    var bytes = picked.bytes;
    if (bytes == null && !kIsWeb && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null) return;
    final content = utf8.decode(bytes, allowMalformed: true);
    _ingestRawPayload(content);
  }

  Future<void> _openPasteDialog() async {
    final pasted = await showDialog<String>(
      context: context,
      builder: (_) => const _PastePayloadDialog(),
    );
    if (pasted != null && pasted.trim().isNotEmpty && mounted) {
      _ingestRawPayload(pasted);
    }
  }

  Future<void> _commitImport() async {
    final selected = _candidates.where((c) => c.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    int mergedCount = 0;
    int createdCount = 0;

    try {
      for (final c in selected) {
        final acc = c.account;
        if (c.disposition == TotpImportDisposition.mergeIntoExisting &&
            c.suggestedMergeTarget != null) {
          final target = c.suggestedMergeTarget!;
          final tags = List<String>.from(target.tags);
          if (!tags.contains('2FA')) tags.add('2FA');
          await vault.saveItem(
            target.copyWith(
              totpSecret: acc.storageTotpValue,
              tags: tags,
            ),
          );
          mergedCount++;
        } else {
          final item = vault.createNewCredential().copyWith(
                title: acc.displayTitle,
                username: acc.accountName,
                totpSecret: acc.storageTotpValue,
                content: acc.note,
                tags: const ['2FA'],
              );
          await vault.saveItem(item);
          createdCount++;
        }
      }

      if (!mounted) return;
      final l10n = context.l10n;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              '$createdCount yeni 2FA kaydı eklendi, $mergedCount mevcut hesaba bağlandı.',
              'Added $createdCount standalone 2FA entries, attached $mergedCount to existing logins.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final selectedCount = _candidates.where((c) => c.selected).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        18,
        MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr(
                      'Çoklu 2FA Kod Aktarımı',
                      'Multi-App 2FA Migration',
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              l10n.tr(
                'Google Authenticator QR (çoklu QR destekli), Aegis JSON, .2fas, Ente (.txt) veya otpauth:// URI yapıştırın.',
                'Supports Google Authenticator multi-QR, Aegis JSON, .2fas, Ente (.txt), and otpauth:// URIs.',
              ),
              style: TextStyle(fontSize: 12.5, color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isSaving ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(
                    l10n.tr('QR Tara / Resim Seç', 'Scan / Pick QR'),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _isSaving ? null : _pickBackupFile,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(l10n.tr('Dosya (.json/.2fas/.txt)', 'Backup File')),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _openPasteDialog,
                  icon: const Icon(Icons.paste_rounded, size: 18),
                  label: Text(l10n.tr('Metin Yapıştır', 'Paste')),
                ),
              ],
            ),
            if (_expectedBatchSize > 1) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.layers_outlined,
                        color: Colors.blueAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.tr(
                          'Google Authenticator Çoklu QR: ${_scannedBatchIndices.length} / $_expectedBatchSize parça tarandı. Kalan QR kodlarını da sırayla tarayabilirsiniz.',
                          'Google Authenticator Batch: ${_scannedBatchIndices.length} / $_expectedBatchSize QR parts scanned. Scan remaining QRs to add all accounts.',
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                ),
              ),
            ],
            if (_warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _warnings.join('\n'),
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _candidates.isEmpty
                  ? Center(
                      child: Text(
                        l10n.tr(
                          'Başlamak için yukarıdan QR tarayın veya yedek dosyası seçin.',
                          'Scan a QR code or choose a backup file above to preview accounts.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _candidates.length,
                      itemBuilder: (ctx, idx) {
                        final c = _candidates[idx];
                        final acc = c.account;
                        final live = TotpService.generateDetailed(
                          acc.storageTotpValue,
                          timeMs: _nowMs,
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: CheckboxListTile(
                            value: c.selected,
                            onChanged: (v) {
                              setState(() => c.selected = v ?? false);
                            },
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    acc.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  live.formattedCode,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (acc.accountName.isNotEmpty)
                                  Text(
                                    acc.accountName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 4),
                                if (c.existingDuplicate != null)
                                  Text(
                                    l10n.tr(
                                      'Zaten kasada var: "${c.existingDuplicate!.title}"',
                                      'Already in vault: "${c.existingDuplicate!.title}"',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.amber,
                                    ),
                                  )
                                else if (c.suggestedMergeTarget != null)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        c.disposition = c.disposition ==
                                                TotpImportDisposition
                                                    .mergeIntoExisting
                                            ? TotpImportDisposition
                                                .createStandalone
                                            : TotpImportDisposition
                                                .mergeIntoExisting;
                                      });
                                    },
                                    child: Text(
                                      c.disposition ==
                                              TotpImportDisposition
                                                  .mergeIntoExisting
                                          ? l10n.tr(
                                              'Eşleşme: "${c.suggestedMergeTarget!.title}" şifresine eklenecek (dokun: ayrı ekle)',
                                              'Will attach to "${c.suggestedMergeTarget!.title}" login (tap to separate)',
                                            )
                                          : l10n.tr(
                                              'Ayrı 2FA kaydı olarak eklenecek (dokun: "${c.suggestedMergeTarget!.title}" ile birleştir)',
                                              'Will add separately (tap to attach to "${c.suggestedMergeTarget!.title}")',
                                            ),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.teal,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    l10n.tr(
                                      'Yeni bağımsız 2FA kaydı olarak eklenecek',
                                      'Will be added as standalone 2FA entry',
                                    ),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.hintColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed:
                    _isSaving || selectedCount == 0 ? null : _commitImport,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_done_rounded),
                label: Text(
                  l10n.tr(
                    '$selectedCount 2FA Hesabını Kasaya Aktar',
                    'Import $selectedCount 2FA Accounts',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MigrationGuideSheet extends StatelessWidget {
  const _MigrationGuideSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr(
                      'Authenticator Uygulamalarından Geçiş Rehberi',
                      'Authenticator Migration Guide',
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GuideCard(
              icon: Icons.qr_code_2_rounded,
              color: Colors.blueAccent,
              title: 'Google Authenticator (Tek Tıkla Toplu QR)',
              steps: l10n.tr(
                '1. Google Authenticator uygulamasını açın.\n'
                '2. Sol üst menü -> "Hesapları aktar" -> "Hesapları dışa aktar"a basın.\n'
                '3. Aktaracağınız hesapları seçin; ekranda QR kod(lar)ı oluşacaktır.\n'
                '4. MultiPad -> 2FA Aktar -> "QR Tara / Resim Seç" ile QR kodlarını sırayla tarayın (birden fazla QR varsa hepsini otomatik birleştirir).',
                '1. Open Google Authenticator.\n'
                '2. Menu -> Transfer accounts -> Export accounts.\n'
                '3. Select accounts to generate QR code(s).\n'
                '4. In MultiPad -> Import 2FA -> Scan / Pick QR sequentially (multi-QR batches merge automatically).',
              ),
            ),
            _GuideCard(
              icon: Icons.security_rounded,
              color: Colors.teal,
              title: 'Microsoft Authenticator',
              steps: l10n.tr(
                'Şeffaf Bilgi: Microsoft Authenticator kişisel hesaplar için şifresiz toplu gizli anahtar (seed/QR) dışa aktarımına izin vermez.\n'
                'Nasıl Taşınır?\n'
                '• İlgili web sitelerinin (Google, GitHub, Discord, Amazon vb.) Hesap Güvenliği ayarından "Authenticator uygulamasını değiştir / Yeni QR kurulumu" seçeneğini açın ve çıkan QR kodunu MultiPad ile tarayın.\n'
                '• Kurumsal iş/okul Microsoft 365 hesapları yönetici ilkesi nedeniyle yalnızca Microsoft Authenticator Push isteyebilir.',
                'Important: Microsoft Authenticator does not export unencrypted TOTP seeds.\n'
                'How to migrate:\n'
                '• Re-enroll via each website\'s 2FA settings ("Change Authenticator App") and scan the new otpauth:// QR with MultiPad before removing the old token.',
              ),
            ),
            _GuideCard(
              icon: Icons.verified_user_rounded,
              color: Colors.green,
              title: 'Duo Mobile',
              steps: l10n.tr(
                'Şeffaf Bilgi: Duo Mobile kurumsal Duo Push/SSO hesapları Duo\'nun cihaz sertifikasına bağlıdır ve başka uygulamaya aktarılamaz.\n'
                'Ancak Duo içinde eklediğiniz standart 6 haneli (3. parti) hesapları, ilgili web sitesinin 2FA ayarlarından yeni QR / Base32 anahtarı üreterek MultiPad\'e taşıyabilirsiniz.',
                'Important: Enterprise Duo Push/SSO accounts are device-bound.\n'
                'Standard 6-digit third-party TOTP accounts stored in Duo can be moved cleanly by regenerating the 2FA QR/secret on each website and scanning it into MultiPad.',
              ),
            ),
            _GuideCard(
              icon: Icons.folder_zip_outlined,
              color: Colors.deepPurpleAccent,
              title: 'Aegis / 2FAS / Ente Auth / Bitwarden',
              steps: l10n.tr(
                '• Aegis: Ayarlar -> İçe/Dışa Aktar -> "Dışa Aktar" -> Düz JSON (Şifrelemeyi geçici olarak kapatın).\n'
                '• 2FAS: Ayarlar -> Yedek -> Dışa Aktar (.2fas dosyasını parolasız kaydedin).\n'
                '• Ente Auth: Ayarlar -> Veri -> Dışa Aktar (Şifresiz metin/otpauth URI listesi).\n'
                '• Aktarım bittikten sonra şifresiz yedek dosyasını cihazınızdan kalıcı olarak silin!',
                '• Aegis / 2FAS / Ente Auth: Export an unencrypted JSON / .2fas / .txt file, import it via "Backup File" here, then permanently delete the plain backup file.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PastePayloadDialog extends StatefulWidget {
  const _PastePayloadDialog();

  @override
  State<_PastePayloadDialog> createState() => _PastePayloadDialogState();
}

class _PastePayloadDialogState extends State<_PastePayloadDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        l10n.tr(
          'URI veya JSON Yedeği Yapıştır',
          'Paste URI or JSON Backup',
        ),
      ),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: _ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText:
                'otpauth-migration://offline?data=...\nveya\notpauth://totp/...\nveya Aegis / 2FAS JSON',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(l10n.tr('Çözümle', 'Parse')),
        ),
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String steps;

  const _GuideCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(steps, style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ],
        ),
      ),
    );
  }
}
