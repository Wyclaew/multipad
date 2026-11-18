import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';

class QuickSearchDialog extends StatefulWidget {
  const QuickSearchDialog({super.key});

  @override
  State<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<QuickSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  Timer? _totpTimer;

  @override
  void initState() {
    super.initState();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _copy(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.copiedWithTimeout(label, timeout)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  IconData _iconFor(VaultItemType type) {
    switch (type) {
      case VaultItemType.credential:
        return Icons.key;
      case VaultItemType.card:
        return Icons.credit_card;
      case VaultItemType.secret:
        return Icons.enhanced_encryption;
      case VaultItemType.wifi:
        return Icons.wifi;
      case VaultItemType.identity:
        return Icons.badge;
      case VaultItemType.license:
        return Icons.verified_user;
      case VaultItemType.bankAccount:
        return Icons.account_balance;
      case VaultItemType.server:
        return Icons.dns;
      case VaultItemType.database:
        return Icons.storage;
      case VaultItemType.cryptoWallet:
        return Icons.account_balance_wallet;
      case VaultItemType.note:
      case VaultItemType.folder:
        return Icons.description;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final vault = context.watch<VaultProvider>();

    if (!auth.isUnlocked) {
      return AlertDialog(
        title: Text(l10n.tr('MultiPad Hızlı Arama', 'MultiPad Quick Search')),
        content: Text(
          l10n.tr(
            'Kasa şu anda kilitli. Hızlı erişim için lütfen MultiPad penceresinden kilidi açın.',
            'Vault is currently locked. Unlock MultiPad to use quick search.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      );
    }

    final q = _queryController.text.trim().toLowerCase();
    final matches = vault.items.where((i) {
      if (q.isEmpty) return true;
      return i.title.toLowerCase().contains(q) ||
          i.username.toLowerCase().contains(q) ||
          i.website.toLowerCase().contains(q) ||
          i.wifiSsid.toLowerCase().contains(q) ||
          i.productName.toLowerCase().contains(q) ||
          i.fullName.toLowerCase().contains(q);
    }).take(12).toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _queryController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.tr(
                    'Hızlı arama & tek tıkla kopyala (Cmd/Ctrl+Shift+Space)...',
                    'Quick search & 1-click copy...',
                  ),
                  prefixIcon: const Icon(Icons.bolt),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: matches.isEmpty
                    ? Center(
                        child: Text(
                          l10n.tr('Eşleşen kayıt bulunamadı.', 'No matching entries.'),
                          style: TextStyle(color: theme.hintColor),
                        ),
                      )
                    : ListView.separated(
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final item = matches[idx];
                          final totp = item.totpSecret.trim().isNotEmpty
                              ? (TotpService.generateCode(item.totpSecret) ?? '')
                              : '';

                          return ListTile(
                            leading: Icon(_iconFor(item.type)),
                            title: Text(
                              item.title.isEmpty ? '(Başlıksız)' : item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.username.isNotEmpty
                                  ? item.username
                                  : (item.website.isNotEmpty
                                        ? item.website
                                        : item.wifiSsid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (item.username.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.person_outline, size: 18),
                                    tooltip: l10n.tr('Kullanıcı Adını Kopyala', 'Copy Username'),
                                    onPressed: () => _copy(item.username, 'Kullanıcı adı'),
                                  ),
                                if (item.password.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.password, size: 18),
                                    tooltip: l10n.tr('Şifreyi Kopyala', 'Copy Password'),
                                    onPressed: () => _copy(item.password, 'Parola'),
                                  ),
                                if (totp.isNotEmpty)
                                  ActionChip(
                                    label: Text(
                                      TotpService.formatCode(totp),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () => _copy(totp, '2FA Kodu'),
                                  ),
                                if (item.type == VaultItemType.wifi &&
                                    item.wifiPassword.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.wifi_password, size: 18),
                                    tooltip: 'Wi-Fi Parolasını Kopyala',
                                    onPressed: () =>
                                        _copy(item.wifiPassword, 'Wi-Fi Parolası'),
                                  ),
                                if (item.type == VaultItemType.card &&
                                    item.cardNumber.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.credit_card, size: 18),
                                    tooltip: 'Kart Numarasını Kopyala',
                                    onPressed: () =>
                                        _copy(item.cardNumber, 'Kart Numarası'),
                                  ),
                                if (item.type == VaultItemType.license &&
                                    item.licenseKey.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                                    tooltip: 'Lisans Anahtarını Kopyala',
                                    onPressed: () =>
                                        _copy(item.licenseKey, 'Lisans Anahtarı'),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
