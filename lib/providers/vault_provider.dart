import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../constants.dart';
import '../models/sync_conflict.dart';
import '../models/vault_folder.dart';
import '../models/vault_item.dart';
import '../services/audit_service.dart';
import '../services/browser_bridge_service.dart';
import '../services/crypto_service.dart';
import '../services/native_bridge_service.dart';
import '../services/offline_storage_service.dart';
import '../services/supabase_service.dart';

enum VaultCategoryFilter {
  all,
  notes,
  credentials,
  cards,
  secrets,
  wifi,
  identity,
  license,
  favorites,
  trash,
  bankAccounts,
  servers,
  databases,
  cryptoWallets,
}

enum VaultSortOrder {
  az,
  za,
  recentlyUpdated,
}

enum SyncMergeDecision {
  useRemote,
  pushLocal,
  markCleanMatching,
  conflict,
}

class VaultProvider with ChangeNotifier {
  final CryptoService _cryptoService = CryptoService();
  final SupabaseService _supabaseService = SupabaseService();
  final Uuid _uuid = const Uuid();

  List<int>? _masterKey;
  bool _isActive = false;
  bool _isDuressMode = false;

  List<VaultItem> _items = [];
  List<SyncConflict> _conflicts = [];
  bool _isLoading = false;
  bool _isSyncingVault = false;
  bool _reloadRequested = false;
  String _searchQuery = '';
  VaultCategoryFilter _currentCategory = VaultCategoryFilter.all;
  VaultSortOrder _sortOrder = VaultSortOrder.az;
  String? _selectedFolderId;
  bool _autofillEnabled = true;

  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = <String>{};

  RealtimeChannel? _subscription;
  bool _isOnlineSyncActive = false;

  VaultProvider({
    bool isUnlocked = false,
    List<int>? masterKey,
    bool isDuressMode = false,
  }) {
    if (isUnlocked && masterKey != null) {
      syncAuthState(
        isUnlocked: true,
        masterKey: masterKey,
        isDuressMode: isDuressMode,
      );
    }
  }

  bool get isLoading => _isLoading;
  bool get isDuressMode => _isDuressMode;
  String get searchQuery => _searchQuery;
  VaultCategoryFilter get currentCategory => _currentCategory;
  VaultSortOrder get sortOrder => _sortOrder;
  String? get selectedFolderId => _selectedFolderId;
  bool get isOnlineSyncActive => _isOnlineSyncActive;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedItemIds => Set.unmodifiable(_selectedItemIds);
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);
  bool get hasConflicts => _conflicts.isNotEmpty;

  /// Raw decrypted items (excluding permanent tombstones). Includes folders & trash.
  List<VaultItem> get allItems => List.unmodifiable(_items);

  /// Active non-deleted, non-trash content items (excludes folder items).
  List<VaultItem> get items => _items
      .where(
        (i) => !i.isDeleted && !i.isTrash && i.type != VaultItemType.folder,
      )
      .toList();

  /// Items currently in Trash.
  List<VaultItem> get trashItems => _items
      .where((i) => !i.isDeleted && i.isTrash && i.type != VaultItemType.folder)
      .toList();

  /// Active folders hierarchy.
  List<VaultFolder> get folders {
    final list = _items
        .where(
          (i) => !i.isDeleted && !i.isTrash && i.type == VaultItemType.folder,
        )
        .map(VaultFolder.fromVaultItem)
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void setAutofillEnabledSetting(bool enabled) {
    if (_autofillEnabled == enabled) return;
    _autofillEnabled = enabled;
    syncAutofillIndex(enabled);
  }

  /// Pure 3-way sync reconciliation decision helper (used by SQLite/cloud sync & unit tests).
  static SyncMergeDecision reconcileThreeWay({
    required bool localDirty,
    required String? baseHash,
    required String? localHash,
    required String? remoteHash,
    required bool localDeleted,
    required bool remoteDeleted,
  }) {
    if (!localDirty) {
      return SyncMergeDecision.useRemote;
    }
    if (localDeleted && remoteDeleted) {
      return SyncMergeDecision.markCleanMatching;
    }
    if (!localDeleted &&
        !remoteDeleted &&
        localHash != null &&
        remoteHash != null &&
        localHash == remoteHash) {
      return SyncMergeDecision.markCleanMatching;
    }
    if (remoteDeleted && !localDeleted) {
      return SyncMergeDecision.conflict;
    }
    if (baseHash == null || (remoteHash != null && baseHash == remoteHash)) {
      return SyncMergeDecision.pushLocal;
    }
    return SyncMergeDecision.conflict;
  }

  /// Appends a snapshot of [previous] into [updated.revisions] when content materially changed.
  static VaultItem withRevisionSnapshot(
    VaultItem? previous,
    VaultItem updated, {
    String summary = '',
  }) {
    if (previous == null) return updated;
    if (previous.computeContentHash() == updated.computeContentHash()) {
      return updated;
    }
    final rev = VaultItemRevision(
      id: const Uuid().v4(),
      savedAt: DateTime.now().toUtc(),
      title: previous.title,
      content: previous.content,
      password: previous.password,
      summary: summary.isNotEmpty
          ? summary
          : (previous.type == VaultItemType.credential
                ? 'Hesap / parola güncellendi'
                : 'Önceki sürüm'),
    );
    final nextRevs = [rev, ...previous.revisions];
    if (nextRevs.length > VaultItem.maxRevisions) {
      nextRevs.removeRange(VaultItem.maxRevisions, nextRevs.length);
    }
    return updated.copyWith(revisions: nextRevs);
  }

  /// Called cleanly by ChangeNotifierProxyProvider when AuthProvider state changes.
  void syncAuthState({
    required bool isUnlocked,
    required List<int>? masterKey,
    bool isDuressMode = false,
  }) {
    if (isUnlocked && masterKey != null) {
      if (_isActive &&
          _isDuressMode == isDuressMode &&
          _masterKey != null &&
          _listEquals(_masterKey!, masterKey)) {
        return;
      }
      CryptoService.wipe(_masterKey);
      _masterKey = List<int>.from(masterKey);
      _isActive = true;
      _isDuressMode = isDuressMode;
      if (_isDuressMode) {
        _subscription?.unsubscribe();
        _subscription = null;
        _isOnlineSyncActive = false;
        NativeBridgeService.clearAutofillIndex();
      } else {
        _subscribeToRealtime();
      }
      loadVault();
    } else {
      if (!_isActive && _masterKey == null && _items.isEmpty) return;
      _isActive = false;
      _isDuressMode = false;
      wipe();
    }
  }

  AuditReport? _cachedAuditReport;
  bool _auditDirty = true;
  int _lastAuditExpiryDays = 90;

  /// Returns memoized vault audit report, recomputed only when items mutate.
  AuditReport get auditReport => getAuditReport();

  /// Returns memoized audit report for the current items, caching Levenshtein computations.
  AuditReport getAuditReport({int expiryDays = 90}) {
    if (_cachedAuditReport == null || _auditDirty || _lastAuditExpiryDays != expiryDays) {
      _cachedAuditReport = AuditService.analyzeVault(
        items,
        globalExpiryDays: expiryDays,
      );
      _lastAuditExpiryDays = expiryDays;
      _auditDirty = false;
    }
    return _cachedAuditReport!;
  }

  /// Invalidates the cached audit report (called whenever items mutate).
  void invalidateAuditReport() {
    _auditDirty = true;
    _cachedAuditReport = null;
  }

  /// Securely locks the vault and purges all sensitive cryptographic and credential data from RAM.
  void lockVault() {
    wipe();
  }

  /// Wipes all in-memory decrypted items, clears caches, and invokes OS memory pressure.
  void wipe() {
    for (final item in _items) {
      item.wipeSecrets();
    }
    CryptoService.wipe(_masterKey);
    _masterKey = null;
    _items = [];
    _conflicts = [];
    _selectedFolderId = null;
    _selectedItemIds.clear();
    _isSelectionMode = false;
    _isOnlineSyncActive = false;
    _subscription?.unsubscribe();
    _subscription = null;
    invalidateAuditReport();

    // Clear decoded image memory buffers
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    // Advise runtime to clean old-generation garbage immediately
    try {
      WidgetsBinding.instance.handleMemoryPressure();
    } catch (_) {}

    notifyListeners();
  }

  @visibleForTesting
  void setItemsForTesting(List<VaultItem> items) {
    _items = List.from(items);
    _isLoading = false;
    _isSyncingVault = false;
    invalidateAuditReport();
    notifyListeners();
  }


  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Set<String> getDescendantFolderIds(String rootFolderId) {
    final allFolders = folders;
    final Set<String> result = {rootFolderId};
    final List<String> queue = [rootFolderId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final f in allFolders) {
        if (f.parentId == current && !result.contains(f.id)) {
          result.add(f.id);
          queue.add(f.id);
        }
      }
    }
    return result;
  }

  List<VaultItem> get filteredItems {
    Iterable<VaultItem> result = _items.where(
      (i) => !i.isDeleted && i.type != VaultItemType.folder,
    );

    if (_currentCategory == VaultCategoryFilter.trash) {
      result = result.where((i) => i.isTrash);
    } else {
      result = result.where((i) => !i.isTrash);

      if (_selectedFolderId != null) {
        final allowedFolders = getDescendantFolderIds(_selectedFolderId!);
        result = result.where(
          (i) => i.folderId != null && allowedFolders.contains(i.folderId),
        );
      }

      switch (_currentCategory) {
        case VaultCategoryFilter.notes:
          result = result.where((i) => i.type == VaultItemType.note);
          break;
        case VaultCategoryFilter.credentials:
          result = result.where((i) => i.type == VaultItemType.credential);
          break;
        case VaultCategoryFilter.cards:
          result = result.where((i) => i.type == VaultItemType.card);
          break;
        case VaultCategoryFilter.secrets:
          result = result.where((i) => i.type == VaultItemType.secret);
          break;
        case VaultCategoryFilter.wifi:
          result = result.where((i) => i.type == VaultItemType.wifi);
          break;
        case VaultCategoryFilter.identity:
          result = result.where((i) => i.type == VaultItemType.identity);
          break;
        case VaultCategoryFilter.license:
          result = result.where((i) => i.type == VaultItemType.license);
          break;
        case VaultCategoryFilter.favorites:
          result = result.where((i) => i.isFavorite);
          break;
        case VaultCategoryFilter.bankAccounts:
          result = result.where((i) => i.type == VaultItemType.bankAccount);
          break;
        case VaultCategoryFilter.servers:
          result = result.where((i) => i.type == VaultItemType.server);
          break;
        case VaultCategoryFilter.databases:
          result = result.where((i) => i.type == VaultItemType.database);
          break;
        case VaultCategoryFilter.cryptoWallets:
          result = result.where((i) => i.type == VaultItemType.cryptoWallet);
          break;
        case VaultCategoryFilter.all:
        case VaultCategoryFilter.trash:
          break;
      }
    }

    if (_searchQuery.trim().isNotEmpty) {
      final tokens = _searchQuery.trim().split(RegExp(r'\s+'));
      final textTokens = <String>[];
      VaultItemType? tokenTypeFilter;
      bool? tokenFavoriteFilter;
      bool? tokenTrashFilter;
      bool? tokenTotpFilter;
      String? tokenTagFilter;

      for (final rawToken in tokens) {
        final lower = rawToken.toLowerCase();
        if (lower.startsWith('type:')) {
          tokenTypeFilter = VaultItem.typeFromString(lower.substring(5));
        } else if (lower == 'is:favorite' || lower == 'is:fav') {
          tokenFavoriteFilter = true;
        } else if (lower == 'is:trash') {
          tokenTrashFilter = true;
        } else if (lower == 'has:totp' || lower == 'has:2fa') {
          tokenTotpFilter = true;
        } else if (lower.startsWith('tag:')) {
          tokenTagFilter = lower.substring(4);
        } else {
          textTokens.add(rawToken.toLowerCase());
        }
      }

      if (tokenTrashFilter == true) {
        result = _items.where((i) => !i.isDeleted && i.isTrash && i.type != VaultItemType.folder);
      }
      if (tokenTypeFilter != null) {
        result = result.where((i) => i.type == tokenTypeFilter);
      }
      if (tokenFavoriteFilter == true) {
        result = result.where((i) => i.isFavorite);
      }
      if (tokenTotpFilter == true) {
        result = result.where((i) => i.totpSecret.trim().isNotEmpty || i.customFields.any((f) => f.type == CustomFieldType.otp));
      }
      if (tokenTagFilter != null && tokenTagFilter.isNotEmpty) {
        result = result.where((i) => i.tags.any((t) => t.toLowerCase() == tokenTagFilter));
      }

      if (textTokens.isNotEmpty) {
        final q = textTokens.join(' ');
        result = result.where((i) {
          final inFields = i.customFields.any(
            (f) =>
                f.label.toLowerCase().contains(q) ||
                (!f.isHidden && f.value.toLowerCase().contains(q)),
          );
          return i.title.toLowerCase().contains(q) ||
              i.content.toLowerCase().contains(q) ||
              i.username.toLowerCase().contains(q) ||
              i.website.toLowerCase().contains(q) ||
              i.cardHolder.toLowerCase().contains(q) ||
              i.wifiSsid.toLowerCase().contains(q) ||
              i.fullName.toLowerCase().contains(q) ||
              i.idNumber.toLowerCase().contains(q) ||
              i.productName.toLowerCase().contains(q) ||
              i.bankName.toLowerCase().contains(q) ||
              i.bankAccountHolder.toLowerCase().contains(q) ||
              i.bankIban.toLowerCase().contains(q) ||
              i.serverHost.toLowerCase().contains(q) ||
              i.databaseName.toLowerCase().contains(q) ||
              i.cryptoWalletAddress.toLowerCase().contains(q) ||
              i.tags.any((t) => t.toLowerCase().contains(q)) ||
              inFields;
        });
      }
    }

    final list = result.toList();
    _sortItems(list);
    return list;
  }

  void setSortOrder(VaultSortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(VaultCategoryFilter category) {
    _currentCategory = category;
    notifyListeners();
  }

  void setSelectedFolder(String? folderId) {
    _selectedFolderId = folderId;
    if (folderId != null && _currentCategory == VaultCategoryFilter.trash) {
      _currentCategory = VaultCategoryFilter.all;
    }
    notifyListeners();
  }

  // --- Multi-Selection Mode ---

  void enterSelectionMode(String initialId) {
    _isSelectionMode = true;
    _selectedItemIds.add(initialId);
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedItemIds.contains(id)) {
      _selectedItemIds.remove(id);
      if (_selectedItemIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _isSelectionMode = true;
      _selectedItemIds.add(id);
    }
    notifyListeners();
  }

  void selectAllFiltered() {
    _isSelectionMode = true;
    for (final item in filteredItems) {
      _selectedItemIds.add(item.id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedItemIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  Future<void> moveItemsToFolder(
    Iterable<String> ids,
    String? targetFolderId,
  ) async {
    final targetIds = ids.toSet();
    for (final item in _items.where((i) => targetIds.contains(i.id)).toList()) {
      await saveItem(
        item.copyWith(
          folderId: targetFolderId,
          clearFolderId: targetFolderId == null,
        ),
      );
    }
    clearSelection();
  }

  Future<void> moveItemsToTrash(Iterable<String> ids) async {
    final targetIds = ids.toSet();
    for (final item in _items.where((i) => targetIds.contains(i.id)).toList()) {
      await moveToTrash(item);
    }
    clearSelection();
  }

  Future<void> deleteItemsPermanently(Iterable<String> ids) async {
    final targetIds = ids.toSet();
    for (final id in targetIds) {
      await deleteItem(id);
    }
    clearSelection();
  }

  // --- Load & 3-Way Sync ---

  Future<void> loadVault() async {
    if (_masterKey == null) return;
    if (_isSyncingVault) {
      _reloadRequested = true;
      return;
    }

    _isSyncingVault = true;
    _isLoading = true;
    notifyListeners();

    try {
      if (_isDuressMode) {
        await _loadDuressVault();
        return;
      }

      // ==========================================
      // PHASE 1: Immediate Local SQLite Render (<50ms)
      // ==========================================
      final localRows = await OfflineStorageService.loadLocalItems();
      final localItems = await decryptRowsParallel(
        rows: localRows,
        masterKey: _masterKey!,
      );

      final Map<String, Map<String, dynamic>> localById = {};
      final Map<String, VaultItem?> localDecryptedById = {};
      for (final r in localRows) {
        final id = r['id'] as String?;
        if (id != null && id.isNotEmpty) {
          localById[id] = r;
        }
      }
      for (final item in localItems) {
        localDecryptedById[item.id] = item;
      }

      final Map<String, VaultItem> finalVisibleItems = {};
      for (final item in localItems) {
        if (!item.isDeleted) {
          finalVisibleItems[item.id] = item;
        }
      }

      // Instantly render local items to UI in Phase 1
      final initialLoaded = finalVisibleItems.values.toList();
      _sortItems(initialLoaded);
      _items = initialLoaded;
      _isLoading = false;
      notifyListeners();
      await syncAutofillIndex(_autofillEnabled);

      // ==========================================
      // PHASE 2: Asynchronous Cloud Delta-Sync
      // ==========================================
      final List<SyncConflict> detectedConflicts = [];

      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          final remoteRows = await _supabaseService.fetchVaultItems();
          _isOnlineSyncActive = true;

          final Map<String, Map<String, dynamic>> remoteById = {};
          final Map<String, VaultItem?> remoteDecryptedById = {};
          final List<Map<String, dynamic>> remoteToDecrypt = [];

          for (final r in remoteRows) {
            final id = r['id'] as String?;
            if (id == null || id.isEmpty) continue;
            remoteById[id] = r;

            final localRow = localById[id];
            // Reuse already decrypted local item if ciphertext matches
            if (localRow != null &&
                localRow['encrypted_payload'] == r['encrypted_payload'] &&
                localDecryptedById.containsKey(id) &&
                localDecryptedById[id] != null) {
              remoteDecryptedById[id] = localDecryptedById[id];
            } else {
              remoteToDecrypt.add(r);
            }
          }

          if (remoteToDecrypt.isNotEmpty) {
            final decryptedRemotes = await decryptRowsParallel(
              rows: remoteToDecrypt,
              masterKey: _masterKey!,
            );
            for (final item in decryptedRemotes) {
              remoteDecryptedById[item.id] = item;
            }
          }

          final allIds = {...localById.keys, ...remoteById.keys};

          for (final id in allIds) {
            final local = localById[id];
            final remote = remoteById[id];
            final localItem = localDecryptedById[id];
            final remoteItem = remoteDecryptedById[id];

            if (local != null && remote == null) {
              final localDirty = local['dirty'] == true;
              final baseHash = local['base_hash'] as String?;
              if (localDirty || baseHash == null) {
                if (local['is_deleted'] == true) {
                  await _supabaseService.deleteVaultItem(id);
                  await OfflineStorageService.removeLocalItem(id);
                  finalVisibleItems.remove(id);
                } else {
                  await _supabaseService.upsertVaultItem(local);
                  final hash = localItem?.computeContentHash() ?? '';
                  await OfflineStorageService.markItemSynced(id, hash);
                  if (localItem != null && !localItem.isDeleted) {
                    finalVisibleItems[id] = localItem;
                  }
                }
              } else {
                // Previously synced cleanly and hard-removed remotely
                await OfflineStorageService.removeLocalItem(id);
                finalVisibleItems.remove(id);
              }
            } else if (local == null && remote != null) {
              final rHash = remoteItem?.computeContentHash() ?? '';
              await OfflineStorageService.upsertLocalItem(
                remote,
                dirty: false,
                baseHash: rHash,
              );
              if (remoteItem != null && !remoteItem.isDeleted) {
                finalVisibleItems[id] = remoteItem;
              }
            } else if (local != null && remote != null) {
              final localDirty = local['dirty'] == true;
              final baseHash = local['base_hash'] as String?;
              final localDeleted = local['is_deleted'] == true;
              final remoteDeleted = remote['is_deleted'] == true;
              final localHash = localItem?.computeContentHash();
              final remoteHash = remoteItem?.computeContentHash();

              final decision = reconcileThreeWay(
                localDirty: localDirty,
                baseHash: baseHash,
                localHash: localHash,
                remoteHash: remoteHash,
                localDeleted: localDeleted,
                remoteDeleted: remoteDeleted,
              );

              switch (decision) {
                case SyncMergeDecision.useRemote:
                case SyncMergeDecision.markCleanMatching:
                  await OfflineStorageService.upsertLocalItem(
                    remote,
                    dirty: false,
                    baseHash: remoteHash ?? '',
                  );
                  if (remoteItem != null) {
                    if (remoteItem.isDeleted) {
                      finalVisibleItems.remove(id);
                    } else {
                      finalVisibleItems[id] = remoteItem;
                    }
                  }
                  break;
                case SyncMergeDecision.pushLocal:
                  if (localDeleted) {
                    await _supabaseService.deleteVaultItem(id);
                    await OfflineStorageService.markItemSynced(
                      id,
                      localHash ?? '',
                    );
                    finalVisibleItems.remove(id);
                  } else {
                    await _supabaseService.upsertVaultItem(local);
                    await OfflineStorageService.markItemSynced(
                      id,
                      localHash ?? '',
                    );
                    if (localItem != null && !localItem.isDeleted) {
                      finalVisibleItems[id] = localItem;
                    }
                  }
                  break;
                case SyncMergeDecision.conflict:
                  if (localItem != null && remoteItem != null) {
                    detectedConflicts.add(
                      SyncConflict(
                        itemId: id,
                        localItem: localItem,
                        remoteItem: remoteItem,
                      ),
                    );
                    // Preserve local draft visibly while awaiting resolution
                    if (!localItem.isDeleted) {
                      finalVisibleItems[id] = localItem;
                    }
                  } else if (remoteItem != null && !remoteItem.isDeleted) {
                    finalVisibleItems[id] = remoteItem;
                  }
                  break;
              }
            }
          }

          final updatedLoaded = finalVisibleItems.values.toList();
          _sortItems(updatedLoaded);
          _items = updatedLoaded;
          _conflicts = detectedConflicts;
          await syncAutofillIndex(_autofillEnabled);
          notifyListeners();
        } catch (syncErr) {
          debugPrint(
            'Cloud sync skipped (offline or timeout), loading local SQLite cache: $syncErr',
          );
          _isOnlineSyncActive = false;
        }
      } else {
        _isOnlineSyncActive = false;
      }
    } finally {
      _isLoading = false;
      _isSyncingVault = false;
      notifyListeners();
      if (_reloadRequested) {
        _reloadRequested = false;
        Future.microtask(loadVault);
      }
    }
  }

  Future<void> resolveConflict(
    SyncConflict conflict,
    ConflictResolutionChoice choice,
  ) async {
    if (_masterKey == null || _isDuressMode) return;

    if (choice == ConflictResolutionChoice.keepLocal) {
      final refreshed = conflict.localItem.copyWith(
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      await _persistItemEncrypted(refreshed, isDirtyBeforeSync: true);
    } else if (choice == ConflictResolutionChoice.keepRemote) {
      final remote = conflict.remoteItem;
      final plainJson = remote.toPlainJson();
      final encrypted = await _cryptoService.encryptData(plainJson, _masterKey!);
      final storageMap = remote.toStorageMap(
        encryptedPayload: encrypted.ciphertext,
        iv: encrypted.iv,
        mac: encrypted.mac,
      );
      final remoteHash = remote.computeContentHash();
      await OfflineStorageService.upsertLocalItem(
        storageMap,
        dirty: false,
        baseHash: remoteHash,
      );
      _replaceOrRemoveInMemory(remote);
    } else if (choice == ConflictResolutionChoice.keepBothAsCopy) {
      // Keep remote on original ID cleanly
      final remote = conflict.remoteItem;
      final remoteEnc = await _cryptoService.encryptData(
        remote.toPlainJson(),
        _masterKey!,
      );
      final remoteStorage = remote.toStorageMap(
        encryptedPayload: remoteEnc.ciphertext,
        iv: remoteEnc.iv,
        mac: remoteEnc.mac,
      );
      await OfflineStorageService.upsertLocalItem(
        remoteStorage,
        dirty: false,
        baseHash: remote.computeContentHash(),
      );
      _replaceOrRemoveInMemory(remote);

      // Save local copy under a brand-new ID
      final copyItem = conflict.localItem.copyWith(
        id: _uuid.v4(),
        title: '${conflict.localItem.title} (Çakışma Kopyası)',
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      await saveItem(copyItem);
    }

    _conflicts.removeWhere((c) => c.itemId == conflict.itemId);
    await syncAutofillIndex(_autofillEnabled);
    notifyListeners();
  }

  void _replaceOrRemoveInMemory(VaultItem item) {
    _items.removeWhere((i) => i.id == item.id);
    if (!item.isDeleted) {
      _items.add(item);
      _sortItems(_items);
    }
  }

  // --- Duress / Decoy Storage ---

  Future<void> _loadDuressVault() async {
    if (_masterKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keyDuressEncryptedItems);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final plainStr = await _cryptoService.decryptData(
          ciphertextBase64: decoded['ciphertext'] as String,
          ivBase64: decoded['iv'] as String,
          macBase64: decoded['mac'] as String,
          masterKey: _masterKey!,
        );
        final list = jsonDecode(plainStr) as List<dynamic>;
        _items = list
            .map(
              (entry) {
                final map = entry as Map<String, dynamic>;
                final rawType = map['item_type'] as String? ?? 'note';
                return VaultItem.fromDecryptedJson(
                  id: map['id'] as String? ?? _uuid.v4(),
                  type: VaultItem.typeFromString(rawType),
                  decryptedPayload: map,
                  isDeleted: false,
                  clientUpdatedAt:
                      DateTime.tryParse(map['clientUpdatedAt'] as String? ?? '') ??
                      DateTime.now().toUtc(),
                );
              },
            )
            .toList();
        _sortItems(_items);
        return;
      } catch (e) {
        debugPrint('Duress vault decode warning: $e');
      }
    }

    // Seed innocent default decoy items on first duress unlock
    _items = [
      VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.note,
        title: 'Haftalık Alışveriş Listesi',
        content: '- [ ] Süt, yumurta, tam buğday ekmek\n- [ ] Kahve çekirdeği\n- [ ] Meyve ve sebze\n- [ ] Bulaşık tableti',
        tags: const ['günlük'],
        isPinned: true,
      ),
      VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.note,
        title: 'Okunacak Kitaplar',
        content: '- Atomik Alışkanlıklar\n- Derin Çalışma\n- Temiz Kod',
        tags: const ['kişisel'],
      ),
      VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.wifi,
        title: 'Misafir Wi-Fi',
        wifiSsid: 'GuestNetwork_2.4G',
        wifiPassword: 'WelcomeGuest2026',
        wifiSecurity: 'WPA',
      ),
    ];
    await _saveDuressVault();
  }

  Future<void> _saveDuressVault() async {
    if (_masterKey == null) return;
    final List<Map<String, dynamic>> serialized = [];
    for (final item in _items.where((i) => !i.isDeleted)) {
      final map = jsonDecode(item.toPlainJson()) as Map<String, dynamic>;
      map['id'] = item.id;
      map['item_type'] = item.type.storageKey;
      map['clientUpdatedAt'] = item.clientUpdatedAt.toIso8601String();
      serialized.add(map);
    }
    final encrypted = await _cryptoService.encryptData(
      jsonEncode(serialized),
      _masterKey!,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.keyDuressEncryptedItems,
      jsonEncode(encrypted),
    );
  }

  void _sortItems(List<VaultItem> list) {
    invalidateAuditReport();
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;

      switch (_sortOrder) {
        case VaultSortOrder.az:
          final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          if (cmp != 0) return cmp;
          return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
        case VaultSortOrder.za:
          final cmp = b.title.toLowerCase().compareTo(a.title.toLowerCase());
          if (cmp != 0) return cmp;
          return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
        case VaultSortOrder.recentlyUpdated:
          return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
      }
    });
  }

  void _subscribeToRealtime() {
    _subscription?.unsubscribe();
    if (!SupabaseService.isInitialized ||
        SupabaseService.currentUser == null ||
        _isDuressMode) {
      return;
    }

    _subscription = _supabaseService.subscribeToVaultChanges((payload) async {
      if (!_isActive || _masterKey == null || _isDuressMode) return;
      final record = payload.newRecord;
      if (record.isEmpty || record['id'] == null) return;

      final id = record['id'] as String;
      final isDeleted = record['is_deleted'] == true;

      final localRows = await OfflineStorageService.loadLocalItems();
      final localRow = localRows.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == id,
            orElse: () => null,
          );
      final localDirty = localRow != null && localRow['dirty'] == true;

      if (isDeleted) {
        if (!localDirty) {
          await OfflineStorageService.removeLocalItem(id);
          _items.removeWhere((i) => i.id == id);
          _conflicts.removeWhere((c) => c.itemId == id);
          await syncAutofillIndex(_autofillEnabled);
          notifyListeners();
        }
      } else {
        final decryptedItem = await _decryptRow(record);
        if (decryptedItem != null) {
          final remoteHash = decryptedItem.computeContentHash();
          if (localDirty) {
            final localItem = await _decryptRow(localRow);
            final baseHash = localRow['base_hash'] as String?;
            final localHash = localItem?.computeContentHash();
            if (localItem != null &&
                localHash != remoteHash &&
                baseHash != null &&
                baseHash != remoteHash) {
              _conflicts.removeWhere((c) => c.itemId == id);
              _conflicts.add(
                SyncConflict(
                  itemId: id,
                  localItem: localItem,
                  remoteItem: decryptedItem,
                ),
              );
              notifyListeners();
            }
          } else {
            await OfflineStorageService.upsertLocalItem(
              record,
              dirty: false,
              baseHash: remoteHash,
            );
            _replaceOrRemoveInMemory(decryptedItem);
            await syncAutofillIndex(_autofillEnabled);
            notifyListeners();
          }
        }
      }
    });
  }

  /// Static isolate-safe chunk decryptor
  static Future<List<VaultItem>> _decryptRowsInIsolate(
    List<Map<String, dynamic>> chunk,
    Uint8List masterKeyCopy,
  ) async {
    final crypto = CryptoService();
    final results = <VaultItem>[];
    for (final row in chunk) {
      final ciphertext = row['encrypted_payload'] as String?;
      final iv = row['iv'] as String?;
      final mac = row['mac'] as String?;
      final id = row['id'] as String?;
      final userId = row['user_id'] as String?;
      final isDeleted = row['is_deleted'] == true || row['is_deleted'] == 1;
      final clientUpdatedAtStr = row['client_updated_at'] as String?;

      if (ciphertext == null || iv == null || mac == null || id == null) {
        continue;
      }
      try {
        final plainJsonStr = await crypto.decryptData(
          ciphertextBase64: ciphertext,
          ivBase64: iv,
          macBase64: mac,
          masterKey: masterKeyCopy,
        );
        final Map<String, dynamic> payload = jsonDecode(plainJsonStr);
        final rawType =
            row['item_type'] as String? ??
            (payload['item_type'] as String? ?? 'note');
        results.add(
          VaultItem.fromDecryptedJson(
            id: id,
            userId: userId,
            type: VaultItem.typeFromString(rawType),
            decryptedPayload: payload,
            isDeleted: isDeleted,
            clientUpdatedAt:
                DateTime.tryParse(clientUpdatedAtStr ?? '') ??
                DateTime.now().toUtc(),
          ),
        );
      } catch (e) {
        debugPrint('Parallel decrypt warning for row $id: $e');
      }
    }
    return results;
  }

  /// Parallel chunk decryption splitting rows across isolates
  static Future<List<VaultItem>> decryptRowsParallel({
    required List<Map<String, dynamic>> rows,
    required List<int> masterKey,
    int maxChunks = 4,
  }) async {
    if (rows.isEmpty) return [];
    final keyCopy = Uint8List.fromList(masterKey);
    if (rows.length <= 4) {
      return _decryptRowsInIsolate(rows, keyCopy);
    }

    final chunkSize = (rows.length / maxChunks).ceil();
    final chunks = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < rows.length; i += chunkSize) {
      chunks.add(rows.sublist(i, min(i + chunkSize, rows.length)));
    }

    final chunkFutures = chunks.map(
      (chunk) => Isolate.run(() => _decryptRowsInIsolate(chunk, keyCopy)),
    );
    final results = await Future.wait(chunkFutures);
    return results.expand((list) => list).toList();
  }

  Future<VaultItem?> _decryptRow(Map<String, dynamic> row) async {
    if (_masterKey == null) return null;
    final items = await _decryptRowsInIsolate(
      [row],
      Uint8List.fromList(_masterKey!),
    );
    return items.isNotEmpty ? items.first : null;
  }

  Future<void> _persistItemEncrypted(
    VaultItem itemToSave, {
    bool isDirtyBeforeSync = true,
  }) async {
    if (_masterKey == null) return;
    final plainJson = itemToSave.toPlainJson();
    final encrypted = await _cryptoService.encryptData(plainJson, _masterKey!);
    final contentHash = itemToSave.computeContentHash();

    final itemWithCipher = itemToSave.copyWith(
      userId: SupabaseService.currentUser?.id,
    );

    final index = _items.indexWhere((i) => i.id == itemWithCipher.id);
    if (index >= 0) {
      _items[index] = itemWithCipher;
    } else {
      _items.insert(0, itemWithCipher);
    }
    _sortItems(_items);
    notifyListeners();

    final storageMap = itemWithCipher.toStorageMap(
      encryptedPayload: encrypted.ciphertext,
      iv: encrypted.iv,
      mac: encrypted.mac,
    );

    await OfflineStorageService.upsertLocalItem(
      storageMap,
      dirty: isDirtyBeforeSync,
      preserveExistingBaseHash: true,
    );

    if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
      try {
        await _supabaseService.upsertVaultItem(storageMap);
        await OfflineStorageService.markItemSynced(itemWithCipher.id, contentHash);
      } catch (e) {
        debugPrint('Cloud save deferred (kept dirty in SQLite): $e');
      }
    }
  }

  Future<void> saveItem(VaultItem item) async {
    if (_masterKey == null) return;

    final existingIdx = _items.indexWhere((i) => i.id == item.id);
    final existing = existingIdx >= 0 ? _items[existingIdx] : null;

    var itemToSave = item.copyWith(
      clientUpdatedAt: DateTime.now().toUtc(),
      userId: SupabaseService.currentUser?.id,
    );
    itemToSave = withRevisionSnapshot(existing, itemToSave);

    if (_isDuressMode) {
      final index = _items.indexWhere((i) => i.id == itemToSave.id);
      if (index >= 0) {
        _items[index] = itemToSave;
      } else {
        _items.insert(0, itemToSave);
      }
      _sortItems(_items);
      await _saveDuressVault();
      notifyListeners();
      return;
    }

    await _persistItemEncrypted(itemToSave);
    await syncAutofillIndex(_autofillEnabled);
  }

  /// Feature 13: Finds an existing credential matching captured domain / package and username.
  VaultItem? findMatchingCredential({
    required String website,
    required String username,
    String? packageName,
  }) {
    final cleanUsername = username.trim().toLowerCase();
    final cleanWebsite = website.trim().toLowerCase();
    final cleanPackage = packageName?.trim().toLowerCase();

    for (final item in items) {
      if (item.type != VaultItemType.credential) continue;
      if (item.username.trim().toLowerCase() != cleanUsername) continue;

      // 1. Direct website / domain matching (exact, subdomain, eTLD+1)
      if (cleanWebsite.isNotEmpty && item.website.isNotEmpty) {
        if (BrowserBridgeService.isDomainMatch(cleanWebsite, item.website)) {
          return item;
        }
      }

      // 2. Package name matching in custom fields or website field
      if (cleanPackage != null && cleanPackage.isNotEmpty) {
        if (item.website.toLowerCase() == cleanPackage) {
          return item;
        }
        final hasMatchingCustomField = item.customFields.any(
          (field) => field.value.trim().toLowerCase() == cleanPackage,
        );
        if (hasMatchingCustomField) {
          return item;
        }
      }

      // 3. Fallback: If both website and item.website are identical strings
      if (cleanWebsite.isNotEmpty && item.website.trim().toLowerCase() == cleanWebsite) {
        return item;
      }
    }
    return null;
  }

  /// Feature 13: Processes captured autofill credentials from native layer.
  /// If [updateExisting] is true and [existingItem] is provided, updates its password and records history.
  /// Otherwise, creates and saves a new credential VaultItem.
  Future<VaultItem> processPendingAutofillCapture({
    required Map<String, dynamic> captured,
    bool updateExisting = false,
    VaultItem? existingItem,
    String? customTitle,
  }) async {
    final capturedUsername = (captured['username'] as String? ?? '').trim();
    final capturedPassword = (captured['password'] as String? ?? '').trim();
    final capturedWebsite = (captured['website'] as String? ?? '').trim();
    final capturedPackage = (captured['packageName'] as String? ?? '').trim();
    final capturedTitle = (captured['title'] as String? ?? '').trim();

    if (updateExisting && existingItem != null) {
      final updatedHistory = List<String>.from(existingItem.passwordHistory);
      if (existingItem.password.isNotEmpty && existingItem.password != capturedPassword) {
        updatedHistory.insert(0, existingItem.password);
        if (updatedHistory.length > 10) {
          updatedHistory.removeLast();
        }
      }

      final updatedItem = existingItem.copyWith(
        title: (customTitle != null && customTitle.trim().isNotEmpty)
            ? customTitle.trim()
            : existingItem.title,
        password: capturedPassword.isNotEmpty ? capturedPassword : existingItem.password,
        passwordHistory: updatedHistory,
        passwordLastModified: DateTime.now().toUtc(),
      );

      await saveItem(updatedItem);
      return updatedItem;
    } else {
      final title = (customTitle != null && customTitle.trim().isNotEmpty)
          ? customTitle.trim()
          : (capturedTitle.isNotEmpty
              ? capturedTitle
              : (capturedWebsite.isNotEmpty ? capturedWebsite : 'New Login'));

      final customFields = <CustomField>[];
      if (capturedPackage.isNotEmpty) {
        customFields.add(CustomField(
          id: _uuid.v4(),
          label: 'Package',
          value: capturedPackage,
          type: CustomFieldType.text,
        ));
      }

      final newItem = VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.credential,
        title: title,
        username: capturedUsername,
        password: capturedPassword,
        website: capturedWebsite,
        customFields: customFields,
        passwordLastModified: DateTime.now().toUtc(),
      );

      await saveItem(newItem);
      return newItem;
    }
  }


  /// Folders CRUD (stored as VaultItemType.folder)
  Future<VaultFolder> createFolder({
    required String name,
    String? parentId,
    String colorHex = '#6366F1',
  }) async {
    final folder = VaultFolder(
      id: _uuid.v4(),
      name: name.trim(),
      parentId: parentId,
      colorHex: colorHex,
      updatedAt: DateTime.now().toUtc(),
    );
    await saveItem(folder.toVaultItem(userId: SupabaseService.currentUser?.id));
    return folder;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final existing = folders.cast<VaultFolder?>().firstWhere(
          (f) => f?.id == folderId,
          orElse: () => null,
        );
    if (existing == null) return;
    final updated = existing.copyWith(
      name: newName.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    await saveItem(updated.toVaultItem(userId: SupabaseService.currentUser?.id));
  }

  Future<void> deleteFolder(String folderId) async {
    final targetFolder = folders.cast<VaultFolder?>().firstWhere(
          (f) => f?.id == folderId,
          orElse: () => null,
        );
    final parentId = targetFolder?.parentId;

    // Reparent child folders so hierarchy stays intact
    for (final child in folders.where((f) => f.parentId == folderId).toList()) {
      final reparented = child.copyWith(
        parentId: parentId,
        clearParentId: parentId == null,
        updatedAt: DateTime.now().toUtc(),
      );
      await saveItem(
        reparented.toVaultItem(userId: SupabaseService.currentUser?.id),
      );
    }

    // Move items in the deleted folder up to parentId (or root)
    for (final item
        in _items
            .where((i) => i.folderId == folderId && i.type != VaultItemType.folder)
            .toList()) {
      await saveItem(
        item.copyWith(
          folderId: parentId,
          clearFolderId: parentId == null,
        ),
      );
    }

    if (_selectedFolderId == folderId) {
      _selectedFolderId = parentId;
    }

    await deleteItem(folderId);
  }

  /// Encrypted Attachments CRUD
  Future<VaultAttachmentMeta> encryptAndStoreAttachment({
    required String itemId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (_masterKey == null) {
      throw Exception('Kasa kilidi açık değil.');
    }
    final attachmentId = _uuid.v4();
    final encrypted = await _cryptoService.encryptBytes(bytes, _masterKey!);
    final digest = CryptoService.sha256HexBytes(bytes);
    final now = DateTime.now().toUtc();

    await OfflineStorageService.upsertAttachment({
      'id': attachmentId,
      'item_id': itemId,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': bytes.length,
      'sha256': digest,
      'ciphertext': encrypted.ciphertext,
      'iv': encrypted.iv,
      'mac': encrypted.mac,
      'created_at': now.toIso8601String(),
    });

    return VaultAttachmentMeta(
      id: attachmentId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      sha256: digest,
      createdAt: now,
    );
  }

  Future<Uint8List?> loadDecryptedAttachment(String attachmentId) async {
    if (_masterKey == null) return null;
    final row = await OfflineStorageService.loadAttachmentById(attachmentId);
    if (row == null) return null;
    try {
      return await _cryptoService.decryptBytes(
        ciphertextBase64: row['ciphertext'] as String,
        ivBase64: row['iv'] as String,
        macBase64: row['mac'] as String,
        masterKey: _masterKey!,
      );
    } catch (e) {
      debugPrint('Failed to decrypt attachment $attachmentId: $e');
      return null;
    }
  }

  Future<void> deleteEncryptedAttachment(String attachmentId) async {
    await OfflineStorageService.deleteAttachment(attachmentId);
  }

  /// Re-encrypts ALL vault items + encrypted attachments when master password / KDF changes.
  Future<void> reEncryptAllWithNewKey(List<int> newMasterKey) async {
    if (_isDuressMode) {
      throw Exception('Mevcut modda şifre değiştirilemez.');
    }
    final oldKey = _masterKey;
    final List<Map<String, dynamic>> updatedStorageRows = [];

    for (final item in _items) {
      final plainJson = item.toPlainJson();
      final encrypted = await _cryptoService.encryptData(plainJson, newMasterKey);
      final updatedItem = item.copyWith(
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      final storageMap = updatedItem.toStorageMap(
        encryptedPayload: encrypted.ciphertext,
        iv: encrypted.iv,
        mac: encrypted.mac,
      );
      storageMap['dirty'] = true;
      storageMap['base_hash'] = updatedItem.computeContentHash();
      updatedStorageRows.add(storageMap);

      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          await _supabaseService.upsertVaultItem(storageMap);
          storageMap['dirty'] = false;
        } catch (e) {
          debugPrint('Re-encrypt cloud push warning for ${item.id}: $e');
        }
      }
    }

    // Also re-encrypt local AES-GCM file attachments so they remain decryptable!
    if (oldKey != null) {
      for (final item in _items) {
        final attRows = await OfflineStorageService.loadAttachmentsForItem(item.id);
        for (final row in attRows) {
          try {
            final plainBytes = await _cryptoService.decryptBytes(
              ciphertextBase64: row['ciphertext'] as String,
              ivBase64: row['iv'] as String,
              macBase64: row['mac'] as String,
              masterKey: oldKey,
            );
            final reEnc = await _cryptoService.encryptBytes(
              plainBytes,
              newMasterKey,
            );
            await OfflineStorageService.upsertAttachment({
              ...row,
              'ciphertext': reEnc.ciphertext,
              'iv': reEnc.iv,
              'mac': reEnc.mac,
            });
          } catch (e) {
            debugPrint('Attachment re-encrypt skipped (${row['id']}): $e');
          }
        }
      }
    }

    await OfflineStorageService.saveAllItems(updatedStorageRows);
    CryptoService.wipe(_masterKey);
    _masterKey = List<int>.from(newMasterKey);
    notifyListeners();
  }

  /// Imports items and folders in bulk (e.g., from CSV/JSON password managers or backup).
  Future<int> importBulk({
    required List<VaultItem> itemsToImport,
    List<VaultFolder> foldersToImport = const [],
  }) async {
    int count = 0;
    for (final folder in foldersToImport) {
      await saveItem(
        folder.toVaultItem(userId: SupabaseService.currentUser?.id),
      );
    }
    for (final item in itemsToImport) {
      await saveItem(item);
      count++;
    }
    return count;
  }

  /// Updates the hardware-keystore-encrypted Android Autofill credential cache.
  Future<void> syncAutofillIndex(bool enabled) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (!enabled || _isDuressMode) {
      await NativeBridgeService.clearAutofillIndex();
      return;
    }
    if (!_isActive || _masterKey == null) {
      // Retain existing hardware-encrypted Keystore index while vault is locked
      return;
    }
    final entries = items
        .where((i) => i.type == VaultItemType.credential && !i.isTrash)
        .map(
          (i) => {
            'id': i.id,
            'title': i.title,
            'website': i.website,
            'username': i.username,
            'password': i.password,
            'totpSecret': i.totpSecret,
          },
        )
        .toList();
    await NativeBridgeService.updateAutofillIndex(entries);
  }

  Future<void> toggleFavorite(VaultItem item) async {
    await saveItem(item.copyWith(isFavorite: !item.isFavorite));
  }

  Future<void> togglePin(VaultItem item) async {
    await saveItem(item.copyWith(isPinned: !item.isPinned));
  }

  Future<void> moveToTrash(VaultItem item) async {
    await saveItem(item.copyWith(isTrash: true, isPinned: false));
  }

  Future<void> restoreFromTrash(VaultItem item) async {
    await saveItem(item.copyWith(isTrash: false));
  }

  Future<void> deleteItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    _conflicts.removeWhere((c) => c.itemId == id);
    notifyListeners();

    if (_isDuressMode) {
      await _saveDuressVault();
      return;
    }

    await OfflineStorageService.deleteAttachmentsForItem(id);

    final tombstone = {
      'id': id,
      'item_type': 'deleted',
      'encrypted_payload': '',
      'iv': '',
      'mac': '',
      'is_deleted': true,
      'client_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await OfflineStorageService.upsertLocalItem(
      tombstone,
      dirty: true,
      preserveExistingBaseHash: true,
    );

    if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
      try {
        await _supabaseService.deleteVaultItem(id);
        await OfflineStorageService.removeLocalItem(id);
      } catch (e) {
        debugPrint('Cloud delete deferred cleanly: $e');
      }
    }
    await syncAutofillIndex(_autofillEnabled);
  }

  Future<void> emptyTrash() async {
    final trashList = _items.where((i) => i.isTrash).toList();
    for (final item in trashList) {
      await deleteItem(item.id);
    }
  }

  // Factories for UI
  VaultItem createNewNote({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.note,
        title: '',
        content: '',
        folderId: folderId,
      );

  VaultItem createNewCredential({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.credential,
        title: '',
        folderId: folderId,
      );

  VaultItem createNewCard({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.card,
        title: '',
        folderId: folderId,
      );

  VaultItem createNewSecret({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.secret,
        title: '',
        folderId: folderId,
      );

  VaultItem createNewWifi({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.wifi,
        title: '',
        wifiSecurity: 'WPA',
        folderId: folderId,
      );

  VaultItem createNewIdentity({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.identity,
        title: '',
        folderId: folderId,
      );

  VaultItem createNewLicense({String? folderId}) => VaultItem(
        id: _uuid.v4(),
        type: VaultItemType.license,
        title: '',
        folderId: folderId,
      );

  @override
  void dispose() {
    CryptoService.wipe(_masterKey);
    _subscription?.unsubscribe();
    super.dispose();
  }
}
