import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';
import '../services/totp_ticker_service.dart';

class CredentialDetailPane extends StatefulWidget {
  final VaultItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorite;

  const CredentialDetailPane({
    super.key,
    required this.item,
    this.onEdit,
    this.onClose,
    this.onDelete,
    this.onToggleFavorite,
  });

  @override
  State<CredentialDetailPane> createState() => _CredentialDetailPaneState();
}

class _CredentialDetailPaneState extends State<CredentialDetailPane> {
  bool _isPasswordMasked = true;
  bool _isCardCvvMasked = true;
  bool _isSeedPhraseMasked = true;
  bool _isWifiPasswordMasked = true;
  bool _isServerPasswordMasked = true;
  bool _isDbPasswordMasked = true;
  final Map<String, bool> _maskedCustomFields = {};

  StreamSubscription<int>? _totpSubscription;
  String? _currentTotp;
  int _remainingSeconds = 30;
  int _periodSeconds = 30;

  @override
  void initState() {
    super.initState();
    _initTotp();
  }

  @override
  void didUpdateWidget(covariant CredentialDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.totpSecret != widget.item.totpSecret) {
      _totpSubscription?.cancel();
      _totpSubscription = null;
      _currentTotp = null;
      _initTotp();
    }
  }

  @override
  void dispose() {
    _totpSubscription?.cancel();
    _totpSubscription = null;
    super.dispose();
  }

  void _initTotp() {
    if (widget.item.totpSecret.trim().isNotEmpty) {
      _updateTotp();
      _totpSubscription?.cancel();
      _totpSubscription = TotpTickerService.instance.tickStream.listen((_) {
        _updateTotp();
      });
    }
  }

  void _updateTotp() {
    if (!mounted) return;
    final detailed = TotpService.generateDetailed(widget.item.totpSecret);
    setState(() {
      _currentTotp = detailed.isValid ? detailed.code : null;
      _remainingSeconds = detailed.remainingSeconds;
      _periodSeconds = detailed.period;
    });
  }

  Future<void> _copySecure(String value, String label) async {
    if (value.isEmpty) return;
    int timeout = ClipboardService.defaultTimeoutSeconds;
    try {
      timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    } catch (_) {}
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (mounted) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.copiedWithTimeout(label, timeout),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    final uri = Uri.tryParse(clean.contains('://') ? clean : 'https://$clean');
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  IconData _getTypeIcon(VaultItemType type) {
    switch (type) {
      case VaultItemType.credential:
        return Icons.lock_outline;
      case VaultItemType.note:
        return Icons.note_outlined;
      case VaultItemType.card:
        return Icons.credit_card_outlined;
      case VaultItemType.bankAccount:
        return Icons.account_balance_outlined;
      case VaultItemType.server:
        return Icons.dns_outlined;
      case VaultItemType.database:
        return Icons.storage_outlined;
      case VaultItemType.cryptoWallet:
        return Icons.account_balance_wallet_outlined;
      case VaultItemType.wifi:
        return Icons.wifi_rounded;
      case VaultItemType.identity:
        return Icons.badge_outlined;
      case VaultItemType.license:
        return Icons.vpn_key_outlined;
      case VaultItemType.secret:
        return Icons.key_outlined;
      case VaultItemType.folder:
        return Icons.folder_outlined;
    }
  }

  String _getTypeLabel(BuildContext context, VaultItemType type) {
    final l10n = context.l10n;
    switch (type) {
      case VaultItemType.credential:
        return l10n.catCredentials;
      case VaultItemType.note:
        return l10n.catNotes;
      case VaultItemType.card:
        return l10n.catCards;
      case VaultItemType.bankAccount:
        return l10n.tr('Banka Hesabı', 'Bank Account');
      case VaultItemType.server:
        return l10n.tr('Sunucu (SSH)', 'Server (SSH)');
      case VaultItemType.database:
        return l10n.tr('Veritabanı', 'Database');
      case VaultItemType.cryptoWallet:
        return l10n.tr('Kripto Cüzdan', 'Crypto Wallet');
      case VaultItemType.wifi:
        return l10n.catWifi;
      case VaultItemType.identity:
        return l10n.catIdentity;
      case VaultItemType.license:
        return l10n.catLicense;
      case VaultItemType.secret:
        return l10n.catSecrets;
      case VaultItemType.folder:
        return l10n.tr('Klasör', 'Folder');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final item = widget.item;

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header
          _buildHeader(theme, l10n, item),
          const Divider(height: 1),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Quick Action Chips
                _buildActionChips(theme, l10n, item),
                const SizedBox(height: 16),

                // Credentials (Username, Password, TOTP, Website)
                if (item.type == VaultItemType.credential ||
                    item.username.isNotEmpty ||
                    item.password.isNotEmpty ||
                    item.totpSecret.isNotEmpty ||
                    item.website.isNotEmpty)
                  _buildCredentialSection(theme, l10n, item),

                // Passkey Section
                if (item.hasPasskeys)
                  _buildPasskeySection(theme, l10n, item),

                // Bank Account Section
                if (item.type == VaultItemType.bankAccount ||
                    item.bankIban.isNotEmpty ||
                    item.bankName.isNotEmpty)
                  _buildBankAccountSection(theme, l10n, item),

                // Server (SSH) Section
                if (item.type == VaultItemType.server ||
                    item.serverHost.isNotEmpty ||
                    item.serverKey.isNotEmpty)
                  _buildServerSection(theme, l10n, item),

                // Database Section
                if (item.type == VaultItemType.database ||
                    item.databaseHost.isNotEmpty ||
                    item.databaseName.isNotEmpty)
                  _buildDatabaseSection(theme, l10n, item),

                // Crypto Wallet Section
                if (item.type == VaultItemType.cryptoWallet ||
                    item.cryptoWalletAddress.isNotEmpty ||
                    item.cryptoSeedPhrase.isNotEmpty)
                  _buildCryptoSection(theme, l10n, item),

                // Payment Card Section
                if (item.type == VaultItemType.card ||
                    item.cardNumber.isNotEmpty)
                  _buildCardSection(theme, l10n, item),

                // Wi-Fi Section
                if (item.type == VaultItemType.wifi || item.wifiSsid.isNotEmpty)
                  _buildWifiSection(theme, l10n, item),

                // Identity Section
                if (item.type == VaultItemType.identity ||
                    item.idNumber.isNotEmpty ||
                    item.fullName.isNotEmpty)
                  _buildIdentitySection(theme, l10n, item),

                // License Section
                if (item.type == VaultItemType.license ||
                    item.licenseKey.isNotEmpty)
                  _buildLicenseSection(theme, l10n, item),

                // Content / Notes Section
                if (item.content.trim().isNotEmpty)
                  _buildNotesSection(theme, l10n, item),

                // Custom Fields Section
                if (item.customFields.isNotEmpty)
                  _buildCustomFieldsSection(theme, l10n, item),

                // Tags & Metadata
                if (item.tags.isNotEmpty)
                  _buildTagsSection(theme, l10n, item),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getTypeIcon(item.type),
              color: theme.colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  item.title.isEmpty
                      ? (item.username.isNotEmpty ? item.username : 'Adsız Öğe')
                      : item.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getTypeLabel(context, item.type),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onToggleFavorite != null)
            IconButton(
              tooltip: item.isFavorite
                  ? l10n.tr('Favorilerden Çıkar', 'Remove Favorite')
                  : l10n.tr('Favorilere Ekle', 'Add Favorite'),
              icon: Icon(
                item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: item.isFavorite ? Colors.amber : null,
              ),
              onPressed: widget.onToggleFavorite,
            ),
          if (widget.onEdit != null)
            FilledButton.tonalIcon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(l10n.edit),
            ),
          if (widget.onDelete != null)
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.onDelete,
            ),
          if (widget.onClose != null)
            IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildActionChips(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    final chips = <Widget>[];

    if (item.username.isNotEmpty) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.person_outline, size: 16),
          label: Text(l10n.tr('Kullanıcı Adı', 'Username')),
          onPressed: () => _copySecure(item.username, l10n.tr('Kullanıcı Adı', 'Username')),
        ),
      );
    }

    if (item.password.isNotEmpty) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.key_outlined, size: 16),
          label: Text(l10n.tr('Şifre', 'Password')),
          onPressed: () => _copySecure(item.password, l10n.tr('Şifre', 'Password')),
        ),
      );
    }

    if (_currentTotp != null) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.timer_outlined, size: 16),
          label: Text('TOTP (${_currentTotp!})'),
          onPressed: () => _copySecure(_currentTotp!, 'TOTP 2FA Kodu'),
        ),
      );
    }

    if (item.bankIban.isNotEmpty) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.account_balance_outlined, size: 16),
          label: Text(l10n.tr('IBAN Kopyala', 'Copy IBAN')),
          onPressed: () => _copySecure(item.bankIban, 'IBAN'),
        ),
      );
    }

    if (item.cryptoWalletAddress.isNotEmpty) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.account_balance_wallet_outlined, size: 16),
          label: Text(l10n.tr('Adres Kopyala', 'Copy Address')),
          onPressed: () => _copySecure(item.cryptoWalletAddress, l10n.tr('Cüzdan Adresi', 'Wallet Address')),
        ),
      );
    }

    if (item.website.isNotEmpty) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.open_in_new, size: 16),
          label: Text(l10n.tr('Web Sitesi', 'Website')),
          onPressed: () => _openUrl(item.website),
        ),
      );
    }

    if (item.hasPasskeys) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.fingerprint, size: 16),
          label: Text('Passkey (${item.passkeys.length})'),
          onPressed: () {
            if (item.passkeys.isNotEmpty && item.passkeys.first.credentialId.isNotEmpty) {
              _copySecure(item.passkeys.first.credentialId, 'Passkey ID');
            }
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips.map((c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: c,
        )).toList(),
      ),
    );
  }

  Widget _buildFieldRow({
    required BuildContext context,
    required String label,
    required String value,
    bool isSensitive = false,
    bool isMasked = false,
    VoidCallback? onToggleMask,
    VoidCallback? onCopy,
    VoidCallback? onOpen,
    Widget? trailingWidget,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final displayValue = isSensitive && isMasked ? '••••••••••••' : value;

    final actionButtons = <Widget>[
      if (trailingWidget != null) trailingWidget,
      if (onOpen != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.open_in_new, size: 18),
          tooltip: l10n.tr('Aç', 'Open'),
          onPressed: onOpen,
        ),
      if (onToggleMask != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
          icon: Icon(
            isMasked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 18,
          ),
          tooltip: isMasked ? l10n.tr('Göster', 'Show') : l10n.tr('Gizle', 'Hide'),
          onPressed: onToggleMask,
        ),
      if (onCopy != null)
        IconButton(
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
          icon: const Icon(Icons.copy_rounded, size: 18),
          tooltip: l10n.tr('Kopyala', 'Copy'),
          onPressed: onCopy,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  displayValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: isSensitive && !isMasked ? 'monospace' : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );

            if (actionButtons.isEmpty) {
              return textColumn;
            }

            // In narrow viewports (< 300px inner container width), wrap actions below text to avoid RenderFlex overflow.
            if (constraints.maxWidth < 300) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  textColumn,
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionButtons,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: textColumn),
                const SizedBox(width: 8),
                Flexible(
                  fit: FlexFit.loose,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actionButtons,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCredentialSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.username.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Kullanıcı Adı', 'Username'),
            value: item.username,
            onCopy: () => _copySecure(item.username, l10n.tr('Kullanıcı Adı', 'Username')),
          ),
        if (item.password.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Şifre', 'Password'),
            value: item.password,
            isSensitive: true,
            isMasked: _isPasswordMasked,
            onToggleMask: () => setState(() => _isPasswordMasked = !_isPasswordMasked),
            onCopy: () => _copySecure(item.password, l10n.tr('Şifre', 'Password')),
          ),
        if (item.totpSecret.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _periodSeconds > 0 ? _remainingSeconds / _periodSeconds : 0,
                          strokeWidth: 3,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: _remainingSeconds <= 5 ? Colors.redAccent : theme.colorScheme.primary,
                        ),
                        Text(
                          '$_remainingSeconds',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _remainingSeconds <= 5 ? Colors.redAccent : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('Doğrulama Kodu (TOTP)', 'Verification Code (TOTP)'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          _currentTotp != null
                              ? '${_currentTotp!.substring(0, 3)} ${_currentTotp!.substring(3)}'
                              : '------',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_currentTotp != null)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      tooltip: 'TOTP Kopyala',
                      onPressed: () => _copySecure(_currentTotp!, 'TOTP Kodu'),
                    ),
                ],
              ),
            ),
          ),
        if (item.website.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Web Sitesi', 'Website'),
            value: item.website,
            onOpen: () => _openUrl(item.website),
            onCopy: () => _copySecure(item.website, l10n.tr('Web Sitesi', 'Website')),
          ),
      ],
    );
  }

  Widget _buildPasskeySection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        for (final pk in item.passkeys)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.fingerprint, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Passkey (FIDO2 / WebAuthn)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FIDO2',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (pk.rpId.isNotEmpty)
                  Text(
                    'RP ID: ${pk.rpId}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (pk.userName.isNotEmpty)
                  Text(
                    'Hesap: ${pk.userName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                if (pk.credentialId.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ID: ${pk.credentialId.length > 24 ? "${pk.credentialId.substring(0, 20)}..." : pk.credentialId}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Passkey ID Kopyala',
                        onPressed: () => _copySecure(pk.credentialId, 'Passkey ID'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBankAccountSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    final isValidIban = item.bankIban.isNotEmpty && IbanValidator.isValid(item.bankIban);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.bankName.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Banka Adı', 'Bank Name'),
            value: item.bankName,
            onCopy: () => _copySecure(item.bankName, 'Banka Adı'),
          ),
        if (item.bankAccountHolder.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Hesap Sahibi', 'Account Holder'),
            value: item.bankAccountHolder,
            onCopy: () => _copySecure(item.bankAccountHolder, 'Hesap Sahibi'),
          ),
        if (item.bankIban.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: 'IBAN',
            value: IbanValidator.format(item.bankIban),
            trailingWidget: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isValidIban ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isValidIban
                    ? l10n.tr('ISO 7064 Geçerli', 'ISO 7064 Valid')
                    : l10n.tr('Geçersiz IBAN', 'Invalid IBAN'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isValidIban ? Colors.green : Colors.red,
                ),
              ),
            ),
            onCopy: () => _copySecure(item.bankIban, 'IBAN'),
          ),
        if (item.bankBicSwift.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: 'BIC / SWIFT',
            value: item.bankBicSwift,
            onCopy: () => _copySecure(item.bankBicSwift, 'BIC / SWIFT'),
          ),
        if (item.bankAccountNumber.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Hesap Numarası', 'Account Number'),
            value: item.bankAccountNumber,
            onCopy: () => _copySecure(item.bankAccountNumber, 'Hesap Numarası'),
          ),
        if (item.bankRoutingNumber.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Şube / Yönlendirme Kodu', 'Routing / Branch Code'),
            value: item.bankRoutingNumber,
            onCopy: () => _copySecure(item.bankRoutingNumber, 'Şube Kodu'),
          ),
      ],
    );
  }

  Widget _buildServerSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.serverHost.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Sunucu Adresi / Host', 'Server Host'),
            value: item.serverPort.isNotEmpty ? '${item.serverHost}:${item.serverPort}' : item.serverHost,
            onCopy: () => _copySecure(item.serverHost, 'Sunucu Host'),
          ),
        if (item.serverUsername.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('SSH Kullanıcı', 'SSH User'),
            value: item.serverUsername,
            onCopy: () => _copySecure(item.serverUsername, 'SSH Kullanıcı'),
          ),
        if (item.serverPassword.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('SSH Parola', 'SSH Password'),
            value: item.serverPassword,
            isSensitive: true,
            isMasked: _isServerPasswordMasked,
            onToggleMask: () => setState(() => _isServerPasswordMasked = !_isServerPasswordMasked),
            onCopy: () => _copySecure(item.serverPassword, 'SSH Parola'),
          ),
        if (item.serverKey.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('SSH Özel Anahtar', 'SSH Private Key'),
            value: item.serverKey,
            isSensitive: true,
            isMasked: true,
            onCopy: () => _copySecure(item.serverKey, 'SSH Anahtarı'),
          ),
      ],
    );
  }

  Widget _buildDatabaseSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    final connectionUri = '${item.databaseType.isNotEmpty ? item.databaseType.toLowerCase() : 'db'}://${item.databaseUser.isNotEmpty ? item.databaseUser : 'user'}:${item.databasePassword.isNotEmpty ? item.databasePassword : 'password'}@${item.databaseHost.isNotEmpty ? item.databaseHost : 'localhost'}${item.databasePort.isNotEmpty ? ':${item.databasePort}' : ''}/${item.databaseName}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.databaseType.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Veritabanı Türü', 'Database Engine'),
            value: item.databaseType,
            onCopy: () => _copySecure(item.databaseType, 'Veritabanı Türü'),
          ),
        if (item.databaseHost.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Host & Port', 'Host & Port'),
            value: item.databasePort.isNotEmpty ? '${item.databaseHost}:${item.databasePort}' : item.databaseHost,
            onCopy: () => _copySecure(item.databaseHost, 'Host'),
          ),
        if (item.databaseName.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Veritabanı Adı', 'Database Name'),
            value: item.databaseName,
            onCopy: () => _copySecure(item.databaseName, 'Veritabanı Adı'),
          ),
        if (item.databaseUser.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Veritabanı Kullanıcısı', 'Database User'),
            value: item.databaseUser,
            onCopy: () => _copySecure(item.databaseUser, 'Veritabanı Kullanıcısı'),
          ),
        if (item.databasePassword.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Veritabanı Şifresi', 'Database Password'),
            value: item.databasePassword,
            isSensitive: true,
            isMasked: _isDbPasswordMasked,
            onToggleMask: () => setState(() => _isDbPasswordMasked = !_isDbPasswordMasked),
            onCopy: () => _copySecure(item.databasePassword, 'Veritabanı Şifresi'),
          ),
        if (item.databaseHost.isNotEmpty && item.databaseName.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Bağlantı Dizesi (URI)', 'Connection String (URI)'),
            value: connectionUri,
            isSensitive: true,
            isMasked: true,
            onCopy: () => _copySecure(connectionUri, 'Bağlantı URI'),
          ),
      ],
    );
  }

  Widget _buildCryptoSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.cryptoNetwork.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Ağ / Blockchain', 'Network / Blockchain'),
            value: item.cryptoNetwork,
            onCopy: () => _copySecure(item.cryptoNetwork, 'Ağ'),
          ),
        if (item.cryptoWalletAddress.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Cüzdan Adresi', 'Wallet Address'),
            value: item.cryptoWalletAddress,
            onCopy: () => _copySecure(item.cryptoWalletAddress, 'Cüzdan Adresi'),
          ),
        if (item.cryptoSeedPhrase.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Kurtarma İfadesi (Seed Phrase)', 'Recovery Seed Phrase'),
            value: item.cryptoSeedPhrase,
            isSensitive: true,
            isMasked: _isSeedPhraseMasked,
            onToggleMask: () => setState(() => _isSeedPhraseMasked = !_isSeedPhraseMasked),
            onCopy: () => _copySecure(item.cryptoSeedPhrase, 'Seed Phrase'),
          ),
      ],
    );
  }

  Widget _buildCardSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.cardNumber.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Kart Numarası', 'Card Number'),
            value: item.cardNumber,
            onCopy: () => _copySecure(item.cardNumber, l10n.tr('Kart Numarası', 'Card Number')),
          ),
        if (item.cardHolder.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Kart Sahibi', 'Cardholder'),
            value: item.cardHolder,
            onCopy: () => _copySecure(item.cardHolder, l10n.tr('Kart Sahibi', 'Cardholder')),
          ),
        Row(
          children: [
            if (item.cardExpiry.isNotEmpty)
              Expanded(
                child: _buildFieldRow(
                  context: context,
                  label: l10n.tr('Son Kullanma', 'Expiry Date'),
                  value: item.cardExpiry,
                  onCopy: () => _copySecure(item.cardExpiry, l10n.tr('Son Kullanma', 'Expiry Date')),
                ),
              ),
            if (item.cardExpiry.isNotEmpty && item.cardCvv.isNotEmpty)
              const SizedBox(width: 8),
            if (item.cardCvv.isNotEmpty)
              Expanded(
                child: _buildFieldRow(
                  context: context,
                  label: 'CVV',
                  value: item.cardCvv,
                  isSensitive: true,
                  isMasked: _isCardCvvMasked,
                  onToggleMask: () => setState(() => _isCardCvvMasked = !_isCardCvvMasked),
                  onCopy: () => _copySecure(item.cardCvv, 'CVV'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildWifiSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.wifiSsid.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Ağ Adı (SSID)', 'Network Name (SSID)'),
            value: item.wifiSsid,
            onCopy: () => _copySecure(item.wifiSsid, l10n.tr('Ağ Adı (SSID)', 'Network Name (SSID)')),
          ),
        if (item.wifiPassword.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Wi-Fi Şifresi', 'Wi-Fi Password'),
            value: item.wifiPassword,
            isSensitive: true,
            isMasked: _isWifiPasswordMasked,
            onToggleMask: () => setState(() => _isWifiPasswordMasked = !_isWifiPasswordMasked),
            onCopy: () => _copySecure(item.wifiPassword, l10n.tr('Wi-Fi Şifresi', 'Wi-Fi Password')),
          ),
      ],
    );
  }

  Widget _buildIdentitySection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.fullName.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Ad Soyad', 'Full Name'),
            value: item.fullName,
            onCopy: () => _copySecure(item.fullName, l10n.tr('Ad Soyad', 'Full Name')),
          ),
        if (item.idNumber.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Kimlik / Pasaport No', 'ID / Passport Number'),
            value: item.idNumber,
            onCopy: () => _copySecure(item.idNumber, l10n.tr('Kimlik No', 'ID Number')),
          ),
      ],
    );
  }

  Widget _buildLicenseSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.productName.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Ürün Adı', 'Product Name'),
            value: item.productName,
            onCopy: () => _copySecure(item.productName, l10n.tr('Ürün Adı', 'Product Name')),
          ),
        if (item.licenseKey.isNotEmpty)
          _buildFieldRow(
            context: context,
            label: l10n.tr('Lisans Anahtarı', 'License Key'),
            value: item.licenseKey,
            onCopy: () => _copySecure(item.licenseKey, l10n.tr('Lisans Anahtarı', 'License Key')),
          ),
      ],
    );
  }

  Widget _buildNotesSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('Notlar', 'Notes'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              item.content,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.tr('Özel Alanlar', 'Custom Fields'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ...item.customFields.map((field) {
          final isMasked = _maskedCustomFields[field.id] ?? (field.type == CustomFieldType.hidden || field.isHidden);

          return _buildFieldRow(
            context: context,
            label: field.label,
            value: field.value,
            isSensitive: field.type == CustomFieldType.hidden || field.isHidden,
            isMasked: isMasked,
            onToggleMask: (field.type == CustomFieldType.hidden || field.isHidden)
                ? () {
                    setState(() {
                      _maskedCustomFields[field.id] = !isMasked;
                    });
                  }
                : null,
            onOpen: field.type == CustomFieldType.url ? () => _openUrl(field.value) : null,
            onCopy: () => _copySecure(field.value, field.label),
          );
        }),
      ],
    );
  }

  Widget _buildTagsSection(ThemeData theme, AppLocalizations l10n, VaultItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: item.tags.map((t) => Chip(
          label: Text('#$t', style: const TextStyle(fontSize: 11)),
          visualDensity: VisualDensity.compact,
        )).toList(),
      ),
    );
  }
}
