import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

class OfflineStorageService {
  // Asynchronous queue lock to serialize read-modify-write operations cleanly
  static Future<void> _lock = Future.value();

  @visibleForTesting
  static void resetLockForTesting() {
    _lock = Future.value();
  }

  static Future<T> _sync<T>(Future<T> Function() computation) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        final result = await computation();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static Map<String, dynamic> _rowToMap(Map<String, Object?> row) {
    return {
      'id': row['id'] as String,
      if (row['user_id'] != null) 'user_id': row['user_id'] as String,
      'item_type': row['item_type'] as String,
      'encrypted_payload': row['encrypted_payload'] as String,
      'iv': row['iv'] as String,
      'mac': row['mac'] as String,
      'is_deleted': (row['is_deleted'] as int? ?? 0) == 1,
      'client_updated_at': row['client_updated_at'] as String,
      'dirty': (row['dirty'] as int? ?? 0) == 1,
      'base_hash': row['base_hash'] as String?,
    };
  }

  /// Loads all locally cached encrypted items from indexed SQLite storage.
  static Future<List<Map<String, dynamic>>> loadLocalItems() async {
    return _sync(() async {
      final db = await DatabaseService.database;
      final rows = await db.query(
        'vault_items',
        orderBy: 'client_updated_at DESC',
      );
      return rows.map(_rowToMap).toList();
    });
  }

  /// Saves or updates a single encrypted item in SQLite atomically.
  static Future<void> upsertLocalItem(
    Map<String, dynamic> itemMap, {
    bool dirty = false,
    String? baseHash,
    bool preserveExistingBaseHash = false,
  }) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      final id = itemMap['id']?.toString() ?? '';
      if (id.isEmpty) return;

      String? effectiveBaseHash = baseHash;
      if (preserveExistingBaseHash && effectiveBaseHash == null) {
        final existing = await db.query(
          'vault_items',
          columns: ['base_hash'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          effectiveBaseHash = existing.first['base_hash'] as String?;
        }
      }

      await db.insert(
        'vault_items',
        {
          'id': id,
          'user_id': itemMap['user_id']?.toString(),
          'item_type': itemMap['item_type']?.toString() ?? 'note',
          'encrypted_payload': itemMap['encrypted_payload']?.toString() ?? '',
          'iv': itemMap['iv']?.toString() ?? '',
          'mac': itemMap['mac']?.toString() ?? '',
          'is_deleted':
              (itemMap['is_deleted'] == true || itemMap['is_deleted'] == 1)
                  ? 1
                  : 0,
          'client_updated_at': itemMap['client_updated_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
          'dirty': dirty ? 1 : 0,
          'base_hash': effectiveBaseHash,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Marks an item clean once synced to cloud and updates its known clean [baseHash].
  static Future<void> markItemSynced(String id, String baseHash) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.update(
        'vault_items',
        {'dirty': 0, 'base_hash': baseHash},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Removes an item from SQLite cache atomically.
  static Future<void> removeLocalItem(String id) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.delete('vault_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Saves the complete list of encrypted items to SQLite atomically.
  static Future<void> saveAllItems(List<Map<String, dynamic>> items) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.transaction((txn) async {
        await txn.delete('vault_items');
        for (final itemMap in items) {
          final id = itemMap['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          await txn.insert(
            'vault_items',
            {
              'id': id,
              'user_id': itemMap['user_id']?.toString(),
              'item_type': itemMap['item_type']?.toString() ?? 'note',
              'encrypted_payload':
                  itemMap['encrypted_payload']?.toString() ?? '',
              'iv': itemMap['iv']?.toString() ?? '',
              'mac': itemMap['mac']?.toString() ?? '',
              'is_deleted':
                  (itemMap['is_deleted'] == true || itemMap['is_deleted'] == 1)
                      ? 1
                      : 0,
              'client_updated_at': itemMap['client_updated_at']?.toString() ??
                  DateTime.now().toUtc().toIso8601String(),
              'dirty':
                  (itemMap['dirty'] == true || itemMap['dirty'] == 1) ? 1 : 0,
              'base_hash': itemMap['base_hash']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    });
  }

  // --- Encrypted File Attachments in SQLite ---

  static Future<void> upsertAttachment(Map<String, dynamic> attachment) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.insert(
        'vault_attachments',
        {
          'id': attachment['id'] as String,
          'item_id': attachment['item_id'] as String,
          'file_name': attachment['file_name'] as String,
          'mime_type': attachment['mime_type'] as String,
          'size_bytes': attachment['size_bytes'] as int,
          'sha256': attachment['sha256'] as String,
          'ciphertext': attachment['ciphertext'] as String,
          'iv': attachment['iv'] as String,
          'mac': attachment['mac'] as String,
          'created_at': attachment['created_at'] as String,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static Future<Map<String, dynamic>?> loadAttachmentById(String id) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      final rows = await db.query(
        'vault_attachments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    });
  }

  static Future<List<Map<String, dynamic>>> loadAttachmentsForItem(
    String itemId,
  ) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      final rows = await db.query(
        'vault_attachments',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'created_at ASC',
      );
      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    });
  }

  static Future<void> deleteAttachment(String id) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.delete('vault_attachments', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> deleteAttachmentsForItem(String itemId) async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.delete(
        'vault_attachments',
        where: 'item_id = ?',
        whereArgs: [itemId],
      );
    });
  }

  /// Clears local SQLite vault & attachment caches (used on logout).
  static Future<void> clearLocal() async {
    return _sync(() async {
      final db = await DatabaseService.database;
      await db.transaction((txn) async {
        await txn.delete('vault_items');
        await txn.delete('vault_attachments');
      });
    });
  }
}
