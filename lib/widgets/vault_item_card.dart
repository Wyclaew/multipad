import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../constants.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';
import '../services/totp_ticker_service.dart';

class VaultItemCard extends StatefulWidget {
  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const VaultItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  State<VaultItemCard> createState() => _VaultItemCardState();
}

class _VaultItemCardState extends State<VaultItemCard> {
  StreamSubscription<int>? _totpSubscription;
  String? _currentTotp;
  int _remainingSeconds = 30;
  int _periodSeconds = 30;
  bool _isHovered = false;
  String? _recentlyCopiedField;
  Timer? _copyResetTimer;

  @override
  void initState() {
    super.initState();
    _initTotp();
  }

  @override
  void didUpdateWidget(covariant VaultItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.totpSecret != widget.item.totpSecret) {
      _totpSubscription?.cancel();
      _totpSubscription = null;
      _currentTotp = null;
      _initTotp();
    }
  }

  void _initTotp() {
    if (widget.item.type == VaultItemType.credential &&
        widget.item.totpSecret.trim().isNotEmpty) {
      _updateTotp();
      _totpSubscription?.cancel();
      _totpSubscription = TotpTickerService.instance.subscribe((_) {
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

  @override
  void dispose() {
    _totpSubscription?.cancel();
    _totpSubscription = null;
    _copyResetTimer?.cancel();
    _copyResetTimer = null;
    super.dispose();
  }

  Future<void> _copySecure(String value, String fieldKey) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    if (!mounted) return;
    _copyResetTimer?.cancel();
    setState(() {
      _recentlyCopiedField = fieldKey;
    });
    _copyResetTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _recentlyCopiedField = null;
        });
      }
    });
  }

  Widget _buildCopyButton({
    required String fieldKey,
    required String value,
    required String tooltip,
    IconData icon = Icons.copy_rounded,
  }) {
    final isCopied = _recentlyCopiedField == fieldKey;
    final theme = Theme.of(context);
    return Tooltip(
      message: isCopied ? 'Kopyalandı!' : tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _copySecure(value, fieldKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isCopied
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isCopied ? Icons.check_circle_rounded : icon,
              key: ValueKey<bool>(isCopied),
              size: 18,
              color: isCopied
                  ? Colors.green
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _showWifiQrDialog(VaultItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.wifiSsid.isNotEmpty ? item.wifiSsid : item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: item.toWifiQrPayload(),
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Güvenlik: ${item.wifiSecurity}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  bool _isPasswordExpiringSoon(VaultItem item, int globalDays) {
    if (item.type != VaultItemType.credential) return false;
    if (item.customExpiryDays == -1) return false;
    if (item.customReminderDate != null) {
      return DateTime.now().isAfter(item.customReminderDate!);
    }
    final activeDays = item.customExpiryDays ?? globalDays;
    if (activeDays <= 0) return false;
    final baseDate = item.passwordLastModified ?? item.clientUpdatedAt;
    return DateTime.now().toUtc().difference(baseDate).inDays >= activeDays;
  }

  IconData _iconForType(VaultItemType type) {
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
        return Icons.badge_outlined;
      case VaultItemType.license:
        return Icons.verified_user_outlined;
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
        return Icons.description_outlined;
    }
  }

  Color _colorForType(VaultItemType type) {
    switch (type) {
      case VaultItemType.credential:
        return Colors.indigoAccent;
      case VaultItemType.card:
        return Colors.tealAccent.shade700;
      case VaultItemType.secret:
        return Colors.purpleAccent;
      case VaultItemType.wifi:
        return Colors.lightBlueAccent;
      case VaultItemType.identity:
        return Colors.orangeAccent;
      case VaultItemType.license:
        return Colors.greenAccent.shade700;
      case VaultItemType.bankAccount:
        return Colors.tealAccent.shade400;
      case VaultItemType.server:
        return Colors.blueGrey;
      case VaultItemType.database:
        return Colors.cyanAccent.shade700;
      case VaultItemType.cryptoWallet:
        return Colors.amberAccent.shade400;
      case VaultItemType.note:
      case VaultItemType.folder:
        return Colors.amberAccent.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    VaultProvider? vault;
    try {
      vault = context.read<VaultProvider>();
    } catch (_) {}
    AuthProvider? auth;
    try {
      auth = context.watch<AuthProvider>();
    } catch (_) {}
    final item = widget.item;

    final isExpiring = _isPasswordExpiringSoon(
      item,
      auth?.globalPasswordExpiryDays ?? 90,
    );
    final icon = _iconForType(item.type);
    final typeColor = _colorForType(item.type);

    String subtitle = '';
    if (item.type == VaultItemType.credential) {
      if (item.isTotpOnly) {
        subtitle = item.username.isNotEmpty
            ? '${item.username} • 2FA Doğrulayıcı'
            : '2FA Doğrulayıcı';
      } else {
        subtitle = item.username.isNotEmpty
            ? item.username
            : (item.website.isNotEmpty ? item.website : 'Şifre Kaydı');
      }
    } else if (item.type == VaultItemType.card) {
      final cleanNum = item.cardNumber.replaceAll(' ', '');
      final last4 = cleanNum.length >= 4
          ? '•••• ${cleanNum.substring(cleanNum.length - 4)}'
          : '••••';
      final brand = cleanNum.isNotEmpty
          ? AuditService.detectCardBrand(cleanNum)
          : 'Kart';
      subtitle = '${item.cardHolder.isNotEmpty ? "${item.cardHolder} • " : ""}$brand $last4';
    } else if (item.type == VaultItemType.secret) {
      subtitle = item.secretType;
    } else if (item.type == VaultItemType.wifi) {
      subtitle = 'SSID: ${item.wifiSsid} (${item.wifiSecurity})';
    } else if (item.type == VaultItemType.identity) {
      subtitle = item.fullName.isNotEmpty ? item.fullName : item.idNumber;
    } else if (item.type == VaultItemType.license) {
      subtitle = item.productName.isNotEmpty ? item.productName : item.licensedTo;
    } else {
      subtitle = item.content.replaceAll('\n', ' ').trim();
      if (subtitle.length > 70) {
        subtitle = '${subtitle.substring(0, 70)}...';
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: _isHovered ? 2.0 : 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: widget.isSelected
              ? BorderSide(color: theme.colorScheme.primary, width: 2)
              : BorderSide(
                  color: _isHovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.45)
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
                  width: _isHovered ? 1.0 : 0.5,
                ),
        ),
        color: widget.isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
            : (_isHovered
                ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.45)
                : null),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 10, top: 6),
                        child: Checkbox(
                          value: widget.isSelected,
                          onChanged: (_) => widget.onTap(),
                        ),
                      )
                    else
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: typeColor, size: 22),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (item.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: Colors.indigoAccent,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  item.title.isEmpty
                                      ? 'Başlıksız Öğe'
                                      : item.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isExpiring)
                                Tooltip(
                                  message: 'Şifrenizi yenileme zamanı geldi!',
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_active,
                                      color: Colors.orangeAccent,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (!widget.isSelectionMode) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.type == VaultItemType.credential &&
                              item.password.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'password',
                              value: item.password,
                              tooltip: 'Şifreyi Kopyala',
                              icon: Icons.copy_all_rounded,
                            ),
                          if (item.type == VaultItemType.wifi)
                            Tooltip(
                              message: 'Wi-Fi QR Göster',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _showWifiQrDialog(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 19,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          if (item.type == VaultItemType.wifi &&
                              item.wifiPassword.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'wifi_password',
                              value: item.wifiPassword,
                              tooltip: 'Wi-Fi Şifresini Kopyala',
                            ),
                          if (item.type == VaultItemType.card &&
                              item.cardNumber.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'card_number',
                              value: item.cardNumber,
                              tooltip: 'Kart Numarasını Kopyala',
                            ),
                          if (item.type == VaultItemType.secret &&
                              item.password.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'secret_key',
                              value: item.password,
                              tooltip: 'Gizli Anahtarı Kopyala',
                            ),
                          if (item.type == VaultItemType.identity &&
                              item.idNumber.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'id_number',
                              value: item.idNumber,
                              tooltip: 'Belge Numarasını Kopyala',
                            ),
                          if (item.type == VaultItemType.license &&
                              item.licenseKey.isNotEmpty)
                            _buildCopyButton(
                              fieldKey: 'license_key',
                              value: item.licenseKey,
                              tooltip: 'Lisans Anahtarını Kopyala',
                            ),
                          const SizedBox(width: 2),
                          Tooltip(
                            message: item.isFavorite
                                ? 'Favorilerden Çıkar'
                                : 'Favorilere Ekle',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => vault?.toggleFavorite(item),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  item.isFavorite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  color: item.isFavorite
                                      ? Colors.amber
                                      : theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (_currentTotp != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.security_rounded,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          TotpService.formatCode(_currentTotp!),
                          style: AppThemeConstants.secretTextStyle.copyWith(
                            fontSize: 15,
                            letterSpacing: 1.6,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 15,
                          height: 15,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              end: _periodSeconds > 0
                                  ? (_remainingSeconds / _periodSeconds)
                                      .clamp(0.0, 1.0)
                                  : 0.0,
                            ),
                            duration: const Duration(milliseconds: 850),
                            curve: Curves.linear,
                            builder: (context, val, _) {
                              return CircularProgressIndicator(
                                value: val.clamp(0.0, 1.0),
                                strokeWidth: 2.2,
                                backgroundColor: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.4),
                                color: _remainingSeconds <= 5
                                    ? Colors.redAccent
                                    : theme.colorScheme.primary,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_remainingSeconds}s',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _remainingSeconds <= 5
                                ? Colors.redAccent
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildCopyButton(
                          fieldKey: 'totp',
                          value: _currentTotp!,
                          tooltip: '2FA Kodunu Kopyala',
                          icon: Icons.copy_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
                if (item.tags.isNotEmpty ||
                    item.attachments.isNotEmpty ||
                    item.customFields.isNotEmpty ||
                    item.hasPasskeys) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (item.hasPasskeys)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purpleAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.purpleAccent.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.fingerprint_rounded,
                                size: 13,
                                color: Colors.purpleAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.passkeys.length == 1
                                    ? 'Passkey'
                                    : 'Passkey (${item.passkeys.length})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purpleAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...item.tags.map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      if (item.attachments.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.teal.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '📎 ${item.attachments.length} ek',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (item.customFields.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.indigo.withValues(alpha: 0.25),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '+${item.customFields.length} alan',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(
                        item.clientUpdatedAt.toLocal(),
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
