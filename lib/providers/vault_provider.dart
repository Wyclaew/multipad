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
  List<int> _masterKey;

  List<VaultItem> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';
  VaultCategoryFilter _currentCategory = VaultCategoryFilter.all;
  RealtimeChannel? _subscription;
  bool _isOnlineSyncActive = false;

  VaultProvider({
    required CryptoService cryptoService,
    required SupabaseService supabaseService,
    required List<int> masterKey,
  })  : _cryptoService = cryptoService,
        _supabaseService = supabaseService,
        _masterKey = List<int>.from(masterKey) {
    loadVault();
    _subscribeToRealtime();
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  VaultCategoryFilter get currentCategory => _currentCategory;
  bool get isOnlineSyncActive => _isOnlineSyncActive;
  List<VaultItem> get allItems => List.unmodifiable(_items);

  /// Filtered items based on search query and current category filter
  List<VaultItem> get filteredItems {
    return _items.where((item) {
      if (item.isDeleted) return false;

      // Handle trash filter
      if (_currentCategory == VaultCategoryFilter.trash) {
        if (!item.isTrash) return false;
      } else {
        if (item.isTrash) return false; // Hide trash in normal views

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

  /// Initial load and decryption of all vault items (Offline-First)
  Future<void> loadVault() async {
    _isLoading = true;
    notifyListeners();

    try {
      List<Map<String, dynamic>> rawRows = [];

      // Try fetching from Supabase if connected
      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          rawRows = await _supabaseService.fetchVaultItems();
          _isOnlineSyncActive = true;
          // Cache locally for offline availability
          await OfflineStorageService.saveAllItems(rawRows);
        } catch (e) {
          debugPrint('Remote fetch failed, falling back to local: $e');
          _isOnlineSyncActive = false;
          rawRows = await OfflineStorageService.loadLocalItems();
        }
      } else {
        // Fallback to local offline cache
        _isOnlineSyncActive = false;
        rawRows = await OfflineStorageService.loadLocalItems();
      }

      final List<VaultItem> decryptedList = [];

      for (final row in rawRows) {
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
      // Pinned items first
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.clientUpdatedAt.compareTo(a.clientUpdatedAt);
    });
  }

  /// Subscribe to Supabase Realtime changes
  void _subscribeToRealtime() {
    if (!SupabaseService.isInitialized) return;

    _subscription = _supabaseService.subscribeToVaultChanges((payload) async {
      try {
        final record = payload.newRecord;
        if (record.isEmpty) return;

        final isDeleted = record['is_deleted'] == true;
        final id = record['id'] as String;

        if (isDeleted) {
          _items.removeWhere((item) => item.id == id);
          await OfflineStorageService.removeLocalItem(id);
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
    final ciphertext = row['encrypted_payload'] as String?;
    final iv = row['iv'] as String?;
    final mac = row['mac'] as String?;
    final id = row['id'] as String;
    final itemTypeStr = row['item_type'] as String? ?? 'note';
    final isDeleted = row['is_deleted'] == true;
    final clientUpdatedAtStr = row['client_updated_at'] as String?;
    final updatedAtStr = row['updated_at'] as String?;

    if (ciphertext == null || iv == null || mac == null) return null;

    final plainJsonStr = await _cryptoService.decryptData(
      ciphertextBase64: ciphertext,
      ivBase64: iv,
      macBase64: mac,
      masterKey: _masterKey,
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
    final plainJson = item.toPlainJson();
    final encrypted = await _cryptoService.encryptData(plainJson, _masterKey);

    final itemWithCipher = item.copyWith(
      rawCiphertext: encrypted.ciphertext,
      rawIv: encrypted.iv,
      rawMac: encrypted.mac,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    // Optimistic UI update
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = itemWithCipher;
    } else {
      _items.insert(0, itemWithCipher);
    }
    _sortItems(_items);
    notifyListeners();

    // Map for storage
    final storageMap = itemWithCipher.toStorageMap(
      encryptedPayload: encrypted.ciphertext,
      iv: encrypted.iv,
      mac: encrypted.mac,
    );

    // Save to local offline cache
    await OfflineStorageService.upsertLocalItem(storageMap);

    // If online, sync to Supabase
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

      // If online, update remote record
      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        try {
          await _supabaseService.upsertVaultItem(storageMap);
        } catch (e) {
          debugPrint('Remote re-encrypt upsert error for item ${item.id}: $e');
        }
      }
    }

    // Save all to local storage
    await OfflineStorageService.saveAllItems(updatedStorageList);

    // Securely replace the in-memory master key
    CryptoService.wipe(_masterKey);
    _masterKey = List<int>.from(newMasterKey);
    notifyListeners();
  }

  /// Toggle item favorite status
  Future<void> toggleFavorite(VaultItem item) async {
    final updated = item.copyWith(isFavorite: !item.isFavorite);
    await saveItem(updated);
  }

  /// Toggle item pin status
  Future<void> togglePin(VaultItem item) async {
    final updated = item.copyWith(isPinned: !item.isPinned);
    await saveItem(updated);
  }

  /// Move item to Trash
  Future<void> moveToTrash(VaultItem item) async {
    final updated = item.copyWith(isTrash: true);
    await saveItem(updated);
  }

  /// Restore item from Trash
  Future<void> restoreFromTrash(VaultItem item) async {
    final updated = item.copyWith(isTrash: false);
    await saveItem(updated);
  }

  /// Permanently delete an item
  Future<void> deleteItem(String id) async {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();

    await OfflineStorageService.removeLocalItem(id);

    if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
      try {
        await _supabaseService.deleteVaultItem(id);
      } catch (e) {
        debugPrint('Remote delete failed: $e');
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

  // Helper factory methods for new empty items
  VaultItem createNewNote() => VaultItem(id: const Uuid().v4(), type: VaultItemType.note, title: '', content: '');
  VaultItem createNewCredential() => VaultItem(id: const Uuid().v4(), type: VaultItemType.credential, title: '');
  VaultItem createNewCard() => VaultItem(id: const Uuid().v4(), type: VaultItemType.card, title: '');
  VaultItem createNewSecret() => VaultItem(id: const Uuid().v4(), type: VaultItemType.secret, title: '');

  @override
  void dispose() {
    _subscription?.unsubscribe();
    // Memory hygiene: wipe master key and clear decrypted objects from RAM
    CryptoService.wipe(_masterKey);
    _items.clear();
    super.dispose();
  }
}
