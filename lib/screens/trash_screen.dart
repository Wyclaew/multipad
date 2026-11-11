import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

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
      case VaultItemType.note:
      case VaultItemType.folder:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vault = context.watch<VaultProvider>();
    final trashItems = vault.trashItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trash),
        actions: [
          if (trashItems.isNotEmpty)
            TextButton.icon(
              icon: const Icon(
                Icons.delete_forever,
                color: Colors.redAccent,
              ),
              label: Text(
                l10n.tr('Tümünü Temizle', 'Empty Trash'),
                style: const TextStyle(color: Colors.redAccent),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      l10n.tr('Çöp Kutusunu Boşalt', 'Empty Trash'),
                    ),
                    content: Text(
                      l10n.tr(
                        '${trashItems.length} öğe kalıcı olarak silinecek ve geri döndürülemeyecek.',
                        '${trashItems.length} items will be permanently deleted.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(l10n.tr('Kalıcı Sil', 'Delete Forever')),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await vault.emptyTrash();
                }
              },
            ),
        ],
      ),
      body: trashItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.delete_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tr('Çöp kutusu boş', 'Trash is empty'),
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: trashItems.length,
                  itemBuilder: (ctx, i) {
                    final item = trashItems[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(_iconForType(item.type)),
                        title: Text(
                          item.title.isEmpty ? 'Başlıksız' : item.title,
                        ),
                        subtitle: Text(
                          item.type.name.toUpperCase(),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.restore,
                                color: Colors.green,
                              ),
                              tooltip: l10n.tr('Geri Yükle', 'Restore'),
                              onPressed: () => vault.restoreFromTrash(item),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_forever,
                                color: Colors.redAccent,
                              ),
                              tooltip: l10n.tr('Kalıcı Sil', 'Delete Permanently'),
                              onPressed: () => vault.deleteItem(item.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
