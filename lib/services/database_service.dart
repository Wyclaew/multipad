import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../constants.dart';

class DatabaseService {
  static Database? _db;
  static Future<Database>? _initFuture;
  static String? _testDbPathOverride;
  static bool _ffiInitialized = false;

  static void configureForTesting({String? dbPath}) {
    _testDbPathOverride = dbPath;
  }

  static Future<void> closeForTesting() async {
    _initFuture = null;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  static void _ensureFfiFactory() {
    if (_ffiInitialized) return;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux) ||
        _testDbPathOverride != null) {
      sqfliteFfiInit();
      databaseFactory = _testDbPathOverride != null
          ? databaseFactoryFfiNoIsolate
          : databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  static Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _initFuture ??= _openAndMigrate();
    return _initFuture!;
  }

  static Future<Database> _openAndMigrate() async {
    _ensureFfiFactory();

    final String dbPath;
    if (_testDbPathOverride != null) {
      dbPath = _testDbPathOverride!;
    } else if (Platform.isWindows || Platform.isLinux) {
      final supportDir = await getApplicationSupportDirectory();
      if (!supportDir.existsSync()) {
        supportDir.createSync(recursive: true);
      }
      dbPath = p.join(supportDir.path, 'multipad_vault.db');
    } else {
      final databasesPath = await getDatabasesPath();
      dbPath = p.join(databasesPath, 'multipad_vault.db');
    }

    final db = await openDatabase(
      dbPath,
      version: 1,
      singleInstance: _testDbPathOverride == null,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vault_items (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            item_type TEXT NOT NULL,
            encrypted_payload TEXT NOT NULL,
            iv TEXT NOT NULL,
            mac TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            client_updated_at TEXT NOT NULL,
            dirty INTEGER NOT NULL DEFAULT 0,
            base_hash TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_vault_items_type_updated
          ON vault_items(item_type, is_deleted, client_updated_at DESC)
        ''');

        await db.execute('''
          CREATE TABLE vault_attachments (
            id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            file_name TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            ciphertext TEXT NOT NULL,
            iv TEXT NOT NULL,
            mac TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_vault_attachments_item
          ON vault_attachments(item_id)
        ''');

        await db.execute('''
          CREATE TABLE security_logs (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            ciphertext TEXT NOT NULL,
            iv TEXT NOT NULL,
            mac TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_security_logs_created
          ON security_logs(created_at DESC)
        ''');
      },
    );

    await _migrateFromSharedPreferencesIfNeeded(db);
    _db = db;
    return db;
  }

  static Future<void> _migrateFromSharedPreferencesIfNeeded(Database db) async {
    if (_testDbPathOverride != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyMigrated =
          prefs.getBool(AppConstants.keySqliteMigrated) ?? false;
      if (alreadyMigrated) return;

      final jsonStr = prefs.getString(AppConstants.keyOfflineItems);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as List<dynamic>;
        await db.transaction((txn) async {
          for (final raw in decoded) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final id = map['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            await txn.insert(
              'vault_items',
              {
                'id': id,
                'user_id': map['user_id']?.toString(),
                'item_type': map['item_type']?.toString() ?? 'note',
                'encrypted_payload': map['encrypted_payload']?.toString() ?? '',
                'iv': map['iv']?.toString() ?? '',
                'mac': map['mac']?.toString() ?? '',
                'is_deleted': (map['is_deleted'] == true || map['is_deleted'] == 1)
                    ? 1
                    : 0,
                'client_updated_at':
                    map['client_updated_at']?.toString() ??
                        DateTime.now().toUtc().toIso8601String(),
                'dirty': 0,
                'base_hash': null,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        });
        await prefs.remove(AppConstants.keyOfflineItems);
      }
      await prefs.setBool(AppConstants.keySqliteMigrated, true);
    } catch (e) {
      debugPrint('Legacy offline migration warning: $e');
    }
  }
}
