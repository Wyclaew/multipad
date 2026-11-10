import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/vault_item.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';

class VaultItemCard extends StatefulWidget {
  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;
  final VoidCallback onMoveToTrash;

  const VaultItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onTogglePin,
    required this.onMoveToTrash,
  });

  @override
  State<VaultItemCard> createState() => _VaultItemCardState();
}

class _VaultItemCardState extends State<VaultItemCard> {
  Timer? _totpTimer;
  String? _currentTotp;
  int _remainingSeconds = 30;

  @override
  void initState() {
    super.initState();
    _initTotp();
  }

  @override
  void didUpdateWidget(covariant VaultItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.totpSecret != widget.item.totpSecret) {
      _initTotp();
    }
  }

  void _initTotp() {
    _totpTimer?.cancel();
    if (widget.item.totpSecret.trim().isNotEmpty) {
      _updateTotp();
      _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTotp());
    } else {
      _currentTotp = null;
    }
  }

  void _updateTotp() {
    if (widget.item.totpSecret.trim().isEmpty) return;
    final code = TotpService.generateCode(widget.item.totpSecret);
    final remaining = TotpService.getRemainingSeconds();
    if (mounted) {
      setState(() {
        _currentTotp = code;
        _remainingSeconds = remaining;
      });
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd MMM, HH:mm');

    Color typeColor = Colors.blueAccent;
    IconData typeIcon = Icons.description_outlined;

    switch (item.type) {
      case VaultItemType.credential:
        typeColor = Colors.purpleAccent;
        typeIcon = Icons.vpn_key_outlined;
        break;
      case VaultItemType.card:
        typeColor = Colors.orangeAccent;
        typeIcon = Icons.credit_card_outlined;
        break;
      case VaultItemType.secret:
        typeColor = Colors.tealAccent;
        typeIcon = Icons.security_outlined;
        break;
      case VaultItemType.note:
      default:
        typeColor = Colors.blueAccent;
        typeIcon = Icons.description_outlined;
        break;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.isPinned
              ? Colors.blueAccent.withOpacity(0.5)
              : theme.colorScheme.outlineVariant.withOpacity(0.6),
          width: item.isPinned ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon + Title + Actions
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(typeIcon, size: 20, color: typeColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isPinned) ...[
                              const Icon(Icons.push_pin, size: 14, color: Colors.blueAccent),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                item.title.trim().isEmpty ? 'İsimsiz Öğe' : item.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (item.type == VaultItemType.credential && item.website.trim().isNotEmpty)
                          Text(
                            item.website,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (item.type == VaultItemType.secret)
                          Text(
                            item.secretType,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20,
                      color: item.isPinned ? Colors.blueAccent : theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: item.isPinned ? 'Sabitlemeyi Kaldır' : 'Başa Sabitle',
                    onPressed: widget.onTogglePin,
                  ),
                  IconButton(
                    icon: Icon(
                      item.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: item.isFavorite ? Colors.amber : theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: item.isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
                    onPressed: widget.onToggleFavorite,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Item Type Specific Content
              if (item.type == VaultItemType.credential) ...[
                if (item.username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.username,
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    const Text('••••••••••••', style: TextStyle(letterSpacing: 2, fontSize: 13)),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Şifreyi Kopyala', style: TextStyle(fontSize: 12)),
                      onPressed: () async {
                        await ClipboardService.copySecurely(item.password);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Şifre kopyalandı! (30 sn sonra temizlenir)')),
                          );
                        }
                      },
                    ),
                  ],
                ),
                // Live 2FA / TOTP Box
                if (_currentTotp != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phonelink_lock_rounded, size: 18, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Text(
                          '2FA Kodu: $_currentTotp',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_remainingSeconds}s',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: '2FA Kodunu Kopyala',
                          onPressed: () async {
                            await ClipboardService.copySecurely(_currentTotp!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('2FA kodu kopyalandı!')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ] else if (item.type == VaultItemType.card) ...[
                Row(
                  children: [
                    Icon(Icons.payment_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      item.cardNumber.length >= 4
                          ? '•••• •••• •••• ${item.cardNumber.substring(item.cardNumber.length - 4)}'
                          : '•••• •••• •••• ••••',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, letterSpacing: 1.2),
                    ),
                    const Spacer(),
                    if (item.cardExpiry.isNotEmpty)
                      Text('SKT: ${item.cardExpiry}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Kart Numarasını Kopyala',
                      onPressed: () async {
                        await ClipboardService.copySecurely(item.cardNumber);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kart numarası kopyalandı!')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ] else if (item.type == VaultItemType.secret) ...[
                Row(
                  children: [
                    Icon(Icons.vpn_key_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    const Text('••••••••••••••••••••', style: TextStyle(letterSpacing: 2, fontSize: 12)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: 'Gizli Anahtarı Kopyala',
                      onPressed: () async {
                        await ClipboardService.copySecurely(item.password);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gizli anahtar kopyalandı!')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ] else ...[
                if (item.content.trim().isNotEmpty)
                  Text(
                    item.content,
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, height: 1.3),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],

              const SizedBox(height: 10),

              // Footer: Tags + Updated Date
              Row(
                children: [
                  if (item.tags.isNotEmpty)
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.tags.take(3).map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  else
                    const Spacer(),
                  Text(
                    dateFormat.format(item.clientUpdatedAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8)),
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
