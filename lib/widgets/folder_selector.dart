import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_folder.dart';
import '../providers/vault_provider.dart';

class FolderSelector extends StatelessWidget {
  final String? selectedFolderId;
  final ValueChanged<String?> onChanged;

  const FolderSelector({
    super.key,
    required this.selectedFolderId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final folders = context.watch<VaultProvider>().folders;
    final validId = folders.any((f) => f.id == selectedFolderId)
        ? selectedFolderId
        : null;

    String buildPath(VaultFolder folder) {
      final parts = <String>[folder.name];
      String? curParent = folder.parentId;
      final visited = <String>{folder.id};
      while (curParent != null && !visited.contains(curParent)) {
        visited.add(curParent);
        final parent = folders.cast<VaultFolder?>().firstWhere(
              (f) => f?.id == curParent,
              orElse: () => null,
            );
        if (parent == null) break;
        parts.insert(0, parent.name);
        curParent = parent.parentId;
      }
      return parts.join(' / ');
    }

    return DropdownButtonFormField<String?>(
      initialValue: validId,
      decoration: InputDecoration(
        labelText: l10n.tr('Klasör', 'Folder'),
        prefixIcon: const Icon(Icons.folder_outlined),
      ),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(l10n.tr('Klasör Yok (Kök)', 'No Folder (Root)')),
        ),
        ...folders.map(
          (f) => DropdownMenuItem<String?>(
            value: f.id,
            child: Text(buildPath(f), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
