import 'vault_item.dart';

enum ConflictResolutionChoice {
  keepLocal,
  keepRemote,
  keepBothAsCopy,
}

class SyncConflict {
  final String itemId;
  final VaultItem localItem;
  final VaultItem remoteItem;
  final DateTime detectedAt;

  SyncConflict({
    required this.itemId,
    required this.localItem,
    required this.remoteItem,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();
}
