import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/vault_item.dart';
import '../services/crypto_service.dart';
import '../services/offline_storage_service.dart';
import '../services/supabase_service.dart';

enum VaultCategoryFilter {
  all,
  notes,
  credentials,
  cards,
  secrets,
  favorites,
  trash,
}

class VaultProvider with ChangeNotifier {
  final CryptoService _cryptoService;
  final SupabaseService _supabaseService;
  List<int>? _masterKey;
  bool _isActive = false;

  List<VaultItem> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';
  VaultCategoryFilter _currentCategory = VaultCategoryFilter.all;
  RealtimeChannel? _subscription;
  bool _isOnlineSyncActive = false;

  VaultProvider({
    required CryptoService cryptoService,
    required SupabaseService supabaseService,
    List<int>? masterKey,
  })  : _cryptoService = cryptoService,
        _supabaseService = supabaseService {
    if (masterKey != null) {
      syncAuthState(isUnlocked: true, masterKey: masterKey);
    }
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  VaultCategoryFilter get currentCategory => _currentCategory;
  bool get isOnlineSyncActive => _isOnlineSyncActive;
  List<VaultItem> get allItems => List.unmodifiable(_items);

  /// Called cleanly by ChangeNotifierProxyProvider when AuthProvider state changes.
  /// Avoids recreating VaultProvider and leaking realtime subscriptions on unrelated auth updates.
  void syncAuthState({required bool isUnlocked, required List<int>? masterKey}) {
    if (isUnlocked && masterKey != null) {
      if (_isActive && _masterKey != null) {
        // Already unlocked; keep active session intact
        return;
      }
      CryptoService.wipe(_masterKey);
      _masterKey = List<int>.from(masterKey);
      _isActive = true;
      loadVault();
      _subscribeToRealtime();
    } else {
      if (!_isActive && _masterKey == null && _items.isEmpty) return;
      _subscription?.unsubscribe();
      _subscription = null;
      CryptoService.wipe(_masterKey);
      _masterKey = null;
      _items.clear();
      _isActive = false;
      _isOnlineSyncActive = false;
      _searchQuery = '';
      notifyListeners();
    }
  }

  /// Filtered items based on search query and current category filter
  List<VaultItem> get filteredItems {
    return _items.where((item) {
      if (item.isDeleted) return false;

      if (_currentCategory == VaultCategoryFilter.trash) {
        if (!item.isTrash) return false;
      } else {
        if (item.isTrash) return false;

        switch (_currentCategory) {
          case VaultCategoryFilter.notes:
            if (item.type != VaultItemType.note) return false;
            break;
          case VaultCategoryFilter.credentials:
            if (item.type != VaultItemType.credential) return false;
            break;
          case VaultCategoryFilter.cards:
            if (item.type != VaultItemType.card) return false;
            break;
          case VaultCategoryFilter.secrets:
            if (item.type != VaultItemType.secret) return false;
            break;
          case VaultCategoryFilter.favorites:
            if (!item.isFavorite) return false;
            break;
          case VaultCategoryFilter.all:
          default:
            break;
        }
      }

      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final titleMatch = item.title.toLowerCase().contains(q);
      final contentMatch = item.content.toLowerCase().contains(q);
      final usernameMatch = item.username.toLowerCase().contains(q);
      final websiteMatch = item.website.toLowerCase().contains(q);
      final cardMatch = item.cardNumber.contains(q) || item.cardHolder.toLowerCase().contains(q);
      final tagMatch = item.tags.any((t) => t.toLowerCase().contains(q));

      return titleMatch || contentMatch || usernameMatch || websiteMatch || cardMatch || tagMatch;
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(VaultCategoryFilter category) {
    _currentCategory = category;
    notifyListeners();
  }

  /// Initial load and bidirectional merge sync of all vault items (Offline-First)
  Future<void> loadVault() async {
    if (_masterKey == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final localRows = await OfflineStorageService.loadLocalItems();
      List<Map<String, dynamic>> effectiveRows = localRows;

      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          final remoteRows = await _supabaseService.fetchVaultItems();
          _isOnlineSyncActive = true;

          // Bidirectional merge by id + client_updated_at timestamp
          final Map<String, Map<String, dynamic>> merged = {};
          for (final r in remoteRows) {
            final id = r['id'] as String?;
            if (id != null) merged[id] = r;
          }

          for (final local in localRows) {
            final id = local['id'] as String?;
            if (id == null) continue;

            final remote = merged[id];
            if (remote == null) {
              // Created offline or paired locally before cloud upload -> push to Supabase
              if (local['is_deleted'] == true) {
                await _supabaseService.deleteVaultItem(id);
              } else {
                await _supabaseService.upsertVaultItem(local);
              }
              merged[id] = local;
            } else {
              final localTime = DateTime.tryParse(local['client_updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
              final remoteTime = DateTime.tryParse(remote['client_updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
              if (localTime.isAfter(remoteTime)) {
                if (local['is_deleted'] == true) {
                  await _supabaseService.deleteVaultItem(id);
                } else {
                  await _supabaseService.upsertVaultItem(local);
                }
                merged[id] = local;
              }
            }
          }

          effectiveRows = merged.values.toList();
          await OfflineStorageService.saveAllItems(effectiveRows);
        } catch (e) {
          debugPrint('Remote fetch/merge failed, falling back to local: $e');
          _isOnlineSyncActive = false;
          effectiveRows = localRows;
        }
      } else {
        _isOnlineSyncActive = false;
      }

      final List<VaultItem> decryptedList = [];

      for (final row in effectiveRows) {
        if (row['is_deleted'] == true) continue;
        try {
          final decrypted = await _decryptRow(row);
          if (decrypted != null && !decrypted.isDeleted) {
            decryptedList.add(decrypted);
          }
        } catch (e) {
          debugPrint('Failed to decrypt item ${row['id']}: $e');
        }
      }

      _sortItems(decryptedList);
      _items = decryptedList;
    } catch (e) {
      debugPrint('Error loading vault: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _sortItems(List<VaultItem> list) {
    list.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
    });
  }

  /// Subscribe to Supabase Realtime changes
  void _subscribeToRealtime() {
    _subscription?.unsubscribe();
    _subscription = null;
    if (!SupabaseService.isInitialized || SupabaseService.currentUser == null) return;

    _subscription = _supabaseService.subscribeToVaultChanges((payload) async {
      if (!_isActive || _masterKey == null) return;
      try {
        final record = payload.newRecord;
        if (record.isEmpty) return;

        final isDeleted = record['is_deleted'] == true;
        final id = record['id'] as String?;
        if (id == null) return;

        if (isDeleted) {
          _items.removeWhere((item) => item.id == id);
          await OfflineStorageService.upsertLocalItem(record);
          notifyListeners();
          return;
        }

        final decrypted = await _decryptRow(record);
        if (decrypted != null) {
          final index = _items.indexWhere((item) => item.id == id);
          if (index != -1) {
            _items[index] = decrypted;
          } else {
            _items.insert(0, decrypted);
          }
          _sortItems(_items);
          await OfflineStorageService.upsertLocalItem(record);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Realtime payload handle error: $e');
      }
    });
  }

  /// Decrypt a single database record
  Future<VaultItem?> _decryptRow(Map<String, dynamic> row) async {
    if (_masterKey == null) return null;
    final ciphertext = row['encrypted_payload'] as String?;
    final iv = row['iv'] as String?;
    final mac = row['mac'] as String?;
    final id = row['id'] as String?;
    final itemTypeStr = row['item_type'] as String? ?? 'note';
    final isDeleted = row['is_deleted'] == true;
    final clientUpdatedAtStr = row['client_updated_at'] as String?;
    final updatedAtStr = row['updated_at'] as String?;

    if (id == null || ciphertext == null || iv == null || mac == null) return null;

    final plainJsonStr = await _cryptoService.decryptData(
      ciphertextBase64: ciphertext,
      ivBase64: iv,
      macBase64: mac,
      masterKey: _masterKey!,
    );

    final Map<String, dynamic> payload = jsonDecode(plainJsonStr);
    return VaultItem.fromDecryptedJson(
      id: id,
      type: VaultItem.typeFromString(itemTypeStr),
      decryptedPayload: payload,
      isDeleted: isDeleted,
      clientUpdatedAt: clientUpdatedAtStr != null ? DateTime.parse(clientUpdatedAtStr) : DateTime.now(),
      updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : null,
      rawCiphertext: ciphertext,
      rawIv: iv,
      rawMac: mac,
    );
  }

  /// Save or update an item (encrypts before saving)
  Future<void> saveItem(VaultItem item) async {
    if (_masterKey == null) return;
    final plainJson = item.toPlainJson();
    final encrypted = await _cryptoService.encryptData(plainJson, _masterKey!);

    final itemWithCipher = item.copyWith(
      rawCiphertext: encrypted.ciphertext,
      rawIv: encrypted.iv,
      rawMac: encrypted.mac,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
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

    await OfflineStorageService.upsertLocalItem(storageMap);

    if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
      try {
        await _supabaseService.upsertVaultItem(storageMap);
      } catch (e) {
        debugPrint('Remote upsert failed (will sync later): $e');
      }
    }
  }

  /// Re-encrypts all items with a new master key during master password rotation
  Future<void> reEncryptAllWithNewKey(List<int> newMasterKey) async {
    final List<Map<String, dynamic>> updatedStorageList = [];

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final plainJson = item.toPlainJson();
      final encrypted = await _cryptoService.encryptData(plainJson, newMasterKey);

      final updatedItem = item.copyWith(
        rawCiphertext: encrypted.ciphertext,
        rawIv: encrypted.iv,
        rawMac: encrypted.mac,
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      _items[i] = updatedItem;

      final storageMap = updatedItem.toStorageMap(
        encryptedPayload: encrypted.ciphertext,
        iv: encrypted.iv,
        mac: encrypted.mac,
      );
      updatedStorageList.add(storageMap);

      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          await _supabaseService.upsertVaultItem(storageMap);
        } catch (e) {
          debugPrint('Remote re-encrypt upsert error for item ${item.id}: $e');
        }
      }
    }

    await OfflineStorageService.saveAllItems(updatedStorageList);

    CryptoService.wipe(_masterKey);
    _masterKey = List<int>.from(newMasterKey);
    notifyListeners();
  }

  Future<void> toggleFavorite(VaultItem item) async {
    await saveItem(item.copyWith(isFavorite: !item.isFavorite));
  }

  Future<void> togglePin(VaultItem item) async {
    await saveItem(item.copyWith(isPinned: !item.isPinned));
  }

  Future<void> moveToTrash(VaultItem item) async {
    await saveItem(item.copyWith(isTrash: true));
  }

  Future<void> restoreFromTrash(VaultItem item) async {
    await saveItem(item.copyWith(isTrash: false));
  }

  /// Permanently delete an item (writes tombstone locally if offline so remote deletion syncs later)
  Future<void> deleteItem(String id) async {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();

    final tombstone = {
      'id': id,
      'is_deleted': true,
      'client_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await OfflineStorageService.upsertLocalItem(tombstone);

    if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
      try {
        await _supabaseService.deleteVaultItem(id);
      } catch (e) {
        debugPrint('Remote delete failed (tombstone saved for later sync): $e');
      }
    }
  }

  /// Empty all items from Trash permanently
  Future<void> emptyTrash() async {
    final trashItems = _items.where((i) => i.isTrash).toList();
    for (final item in trashItems) {
      await deleteItem(item.id);
    }
  }

  VaultItem createNewNote() => VaultItem(id: const Uuid().v4(), type: VaultItemType.note, title: '', content: '');
  VaultItem createNewCredential() => VaultItem(id: const Uuid().v4(), type: VaultItemType.credential, title: '');
  VaultItem createNewCard() => VaultItem(id: const Uuid().v4(), type: VaultItemType.card, title: '');
  VaultItem createNewSecret() => VaultItem(id: const Uuid().v4(), type: VaultItemType.secret, title: '');

  @override
  void dispose() {
    _subscription?.unsubscribe();
    CryptoService.wipe(_masterKey);
    _items.clear();
    super.dispose();
  }
}
