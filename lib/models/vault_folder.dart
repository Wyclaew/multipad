import 'vault_item.dart';

class VaultFolder {
  final String id;
  final String name;
  final String? parentId;
  final String colorHex;
  final DateTime updatedAt;
  final bool isDeleted;

  const VaultFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.colorHex = '#6C63FF',
    required this.updatedAt,
    this.isDeleted = false,
  });

  factory VaultFolder.fromVaultItem(VaultItem item) {
    return VaultFolder(
      id: item.id,
      name: item.title,
      parentId: item.folderId,
      colorHex: item.secretType.startsWith('#') ? item.secretType : '#6C63FF',
      updatedAt: item.clientUpdatedAt,
      isDeleted: item.isDeleted,
    );
  }

  VaultItem toVaultItem({String? userId}) {
    return VaultItem(
      id: id,
      userId: userId,
      type: VaultItemType.folder,
      title: name,
      folderId: parentId,
      secretType: colorHex,
      isDeleted: isDeleted,
      clientUpdatedAt: updatedAt,
    );
  }

  VaultFolder copyWith({
    String? id,
    String? name,
    String? parentId,
    bool clearParentId = false,
    String? colorHex,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return VaultFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      colorHex: colorHex ?? this.colorHex,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
