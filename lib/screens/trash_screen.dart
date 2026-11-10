import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final trashItems = vault.allItems.where((i) => i.isTrash && !i.isDeleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Çöp Kutusu'),
        actions: [
          if (trashItems.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 18),
              label: const Text('Tümünü Temizle', style: TextStyle(color: Colors.redAccent)),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Çöp Kutusunu Boşalt'),
                    content: const Text('Çöp kutusundaki tüm öğeler kalıcı olarak silinecektir. Devam edilsin mi?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Kalıcı Olarak Sil'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  for (final item in trashItems) {
                    await vault.deleteItem(item.id);
                  }
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: trashItems.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline_rounded, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Çöp kutusu boş', style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: trashItems.length,
              itemBuilder: (ctx, i) {
                final item = trashItems[i];
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: Icon(
                      item.type == VaultItemType.credential
                          ? Icons.vpn_key_outlined
                          : item.type == VaultItemType.card
                              ? Icons.credit_card_outlined
                              : item.type == VaultItemType.secret
                                  ? Icons.security_outlined
                                  : Icons.description_outlined,
                      color: Colors.grey,
                    ),
                    title: Text(item.title.isEmpty ? 'İsimsiz Öğe' : item.title),
                    subtitle: Text('Silinmiş ${item.type.name}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore_from_trash_outlined, color: Colors.blueAccent),
                          tooltip: 'Geri Yükle',
                          onPressed: () => vault.restoreFromTrash(item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                          tooltip: 'Kalıcı Olarak Sil',
                          onPressed: () => vault.deleteItem(item.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
