import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';

class _QuickSearchAction {
  final String label;
  final String value;
  final IconData icon;
  final String tooltip;
  final bool isTotp;

  const _QuickSearchAction({
    required this.label,
    required this.value,
    required this.icon,
    required this.tooltip,
    this.isTotp = false,
  });
}

class QuickSearchDialog extends StatefulWidget {
  const QuickSearchDialog({super.key});

  @override
  State<QuickSearchDialog> createState() => _QuickSearchDialogState();
}

class _QuickSearchDialogState extends State<QuickSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _focusNode;
  Timer? _totpTimer;

  int _selectedIndex = 0;
  int _selectedActionIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    _queryController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final vault = context.read<VaultProvider>();
    final q = _queryController.text.trim().toLowerCase();
    final matches = _filterMatches(vault.items, q);

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    if (matches.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, matches.length - 1);
        _selectedActionIndex = 0;
      });
      _scrollToIndex(_selectedIndex);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, matches.length - 1);
        _selectedActionIndex = 0;
      });
      _scrollToIndex(_selectedIndex);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_selectedIndex >= 0 && _selectedIndex < matches.length) {
        final item = matches[_selectedIndex];
        final totp = item.totpSecret.trim().isNotEmpty
            ? (TotpService.generateCode(item.totpSecret) ?? '')
            : '';
        final actions = _getActionsForItem(item, totp, context.l10n);
        if (actions.isNotEmpty) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          setState(() {
            if (isShift) {
              _selectedActionIndex =
                  (_selectedActionIndex - 1 + actions.length) % actions.length;
            } else {
              _selectedActionIndex =
                  (_selectedActionIndex + 1) % actions.length;
            }
          });
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_selectedIndex >= 0 && _selectedIndex < matches.length) {
        final item = matches[_selectedIndex];
        final totp = item.totpSecret.trim().isNotEmpty
            ? (TotpService.generateCode(item.totpSecret) ?? '')
            : '';
        final actions = _getActionsForItem(item, totp, context.l10n);
        if (actions.isNotEmpty) {
          final action =
              actions[_selectedActionIndex.clamp(0, actions.length - 1)];
          _copy(action.value, action.label);
          Navigator.of(context).pop();
        }
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 72.0;
    final target = (index * itemHeight) - 80.0;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  List<VaultItem> _filterMatches(List<VaultItem> items, String q) {
    return items.where((i) {
      if (q.isEmpty) return true;
      return i.title.toLowerCase().contains(q) ||
          i.username.toLowerCase().contains(q) ||
          i.website.toLowerCase().contains(q) ||
          i.wifiSsid.toLowerCase().contains(q) ||
          i.productName.toLowerCase().contains(q) ||
          i.fullName.toLowerCase().contains(q);
    }).take(12).toList();
  }

  List<_QuickSearchAction> _getActionsForItem(
    VaultItem item,
    String totp,
    AppLocalizations l10n,
  ) {
    final actions = <_QuickSearchAction>[];
    if (item.password.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('Parola', 'Password'),
          value: item.password,
          icon: Icons.password,
          tooltip: l10n.tr('Şifreyi Kopyala', 'Copy Password'),
        ),
      );
    }
    if (item.username.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('Kullanıcı adı', 'Username'),
          value: item.username,
          icon: Icons.person_outline,
          tooltip: l10n.tr('Kullanıcı Adını Kopyala', 'Copy Username'),
        ),
      );
    }
    if (totp.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('2FA Kodu', '2FA Code'),
          value: totp,
          icon: Icons.timer_outlined,
          tooltip: l10n.tr('2FA Kodunu Kopyala', 'Copy 2FA Code'),
          isTotp: true,
        ),
      );
    }
    if (item.type == VaultItemType.wifi && item.wifiPassword.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('Wi-Fi Parolası', 'Wi-Fi Password'),
          value: item.wifiPassword,
          icon: Icons.wifi_password,
          tooltip: l10n.tr('Wi-Fi Parolasını Kopyala', 'Copy Wi-Fi Password'),
        ),
      );
    }
    if (item.type == VaultItemType.card && item.cardNumber.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('Kart Numarası', 'Card Number'),
          value: item.cardNumber,
          icon: Icons.credit_card,
          tooltip: l10n.tr('Kart Numarasını Kopyala', 'Copy Card Number'),
        ),
      );
    }
    if (item.type == VaultItemType.license && item.licenseKey.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.tr('Lisans Anahtarı', 'License Key'),
          value: item.licenseKey,
          icon: Icons.vpn_key_outlined,
          tooltip: l10n.tr('Lisans Anahtarını Kopyala', 'Copy License Key'),
        ),
      );
    }
    if (actions.isEmpty && item.content.isNotEmpty) {
      actions.add(
        _QuickSearchAction(
          label: l10n.catNotes,
          value: item.content,
          icon: Icons.description_outlined,
          tooltip: l10n.tr('Notu Kopyala', 'Copy Note'),
        ),
      );
    }
    return actions;
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

  Widget _buildKeyBadge(
    String symbol, {
    String? label,
    bool isPrimary = false,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isPrimary
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPrimary
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            symbol,
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: isPrimary
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isPrimary
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
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
    final matches = _filterMatches(vault.items, q);

    if (_selectedIndex >= matches.length) {
      _selectedIndex = matches.isEmpty ? 0 : matches.length - 1;
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 540),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _queryController,
                focusNode: _focusNode,
                autofocus: true,
                onChanged: (_) => setState(() {
                  _selectedIndex = 0;
                  _selectedActionIndex = 0;
                }),
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
                        controller: _scrollController,
                        itemCount: matches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (ctx, idx) {
                          final item = matches[idx];
                          final totp = item.totpSecret.trim().isNotEmpty
                              ? (TotpService.generateCode(item.totpSecret) ?? '')
                              : '';
                          final isCardSelected = idx == _selectedIndex;
                          final actions = _getActionsForItem(item, totp, l10n);

                          return Container(
                            decoration: BoxDecoration(
                              color: isCardSelected
                                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCardSelected
                                    ? theme.colorScheme.primary.withValues(alpha: 0.6)
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: Icon(
                                    _iconFor(item.type),
                                    color: isCardSelected ? theme.colorScheme.primary : null,
                                  ),
                                  title: Text(
                                    item.title.isEmpty ? '(Başlıksız)' : item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: isCardSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
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
                                  onTap: () {
                                    setState(() {
                                      _selectedIndex = idx;
                                      _selectedActionIndex = 0;
                                    });
                                  },
                                  trailing: Wrap(
                                    spacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      ...actions.asMap().entries.map((entry) {
                                        final aIdx = entry.key;
                                        final act = entry.value;
                                        final isActionFocused =
                                            isCardSelected && aIdx == _selectedActionIndex;
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: isActionFocused
                                                ? theme.colorScheme.primaryContainer
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            border: isActionFocused
                                                ? Border.all(color: theme.colorScheme.primary)
                                                : null,
                                          ),
                                          child: IconButton(
                                            icon: act.isTotp
                                                ? Text(
                                                    TotpService.formatCode(act.value),
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  )
                                                : Icon(act.icon, size: 18),
                                            tooltip: act.tooltip,
                                            onPressed: () {
                                              _copy(act.value, act.label);
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                if (isCardSelected && actions.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                    child: Row(
                                      children: [
                                        _buildKeyBadge(
                                          '↵',
                                          label: actions[_selectedActionIndex.clamp(0, actions.length - 1)].label,
                                          isPrimary: true,
                                          theme: theme,
                                        ),
                                        if (actions.length > 1) ...[
                                          const SizedBox(width: 8),
                                          _buildKeyBadge(
                                            '⇥',
                                            label: l10n.tr('Değiştir', 'Cycle'),
                                            theme: theme,
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        _buildKeyBadge(
                                          '⎋',
                                          label: l10n.tr('Kapat', 'Dismiss'),
                                          theme: theme,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '↑↓ ${l10n.tr("Gezin", "Navigate")}   •   ↵ ${l10n.tr("Kopyala", "Copy")}   •   ⇥ ${l10n.tr("İşlem Değiştir", "Cycle Action")}   •   ⎋ ${l10n.tr("Kapat", "Dismiss")}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
