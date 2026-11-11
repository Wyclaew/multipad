import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/offline_storage_service.dart';
import 'package:multipad/services/security_log_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('multipad_sqlite_test_');
    DatabaseService.configureForTesting(dbPath: p.join(tempDir.path, 'vault_test.db'));
  });

  tearDown(() async {
    await DatabaseService.closeForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SQLite OfflineStorageService & Attachments', () {
    test('persists dirty state, preserves original base_hash on offline edits, and marks synced cleanly', () async {
      await OfflineStorageService.upsertLocalItem(
        {
          'id': 'item-a',
          'user_id': 'u-1',
          'encrypted_payload': 'ct1',
          'iv': 'iv1',
          'mac': 'mac1',
          'item_type': 'note',
          'is_deleted': false,
          'client_updated_at': '2026-06-01T10:00:00.000Z',
        },
        dirty: false,
        baseHash: 'hash_v1',
      );

      // Simulate offline local edit preserving baseHash
      await OfflineStorageService.upsertLocalItem(
        {
          'id': 'item-a',
          'user_id': 'u-1',
          'encrypted_payload': 'ct2',
          'iv': 'iv2',
          'mac': 'mac2',
          'item_type': 'note',
          'is_deleted': false,
          'client_updated_at': '2026-06-01T11:00:00.000Z',
        },
        dirty: true,
        preserveExistingBaseHash: true,
      );

      var rows = await OfflineStorageService.loadLocalItems();
      expect(rows.length, 1);
      expect(rows.first['encrypted_payload'], 'ct2');
      expect(rows.first['dirty'], isTrue);
      expect(rows.first['base_hash'], 'hash_v1');

      await OfflineStorageService.markItemSynced('item-a', 'hash_v2');
      rows = await OfflineStorageService.loadLocalItems();
      expect(rows.first['dirty'], isFalse);
      expect(rows.first['base_hash'], 'hash_v2');
    });

    test('stores, loads, and cascades encrypted attachments by item id', () async {
      await OfflineStorageService.upsertAttachment({
        'id': 'att-1',
        'item_id': 'item-note',
        'file_name': 'passport.png',
        'mime_type': 'image/png',
        'size_bytes': 1234,
        'sha256': 'deadbeef',
        'ciphertext': 'encCt',
        'iv': 'encIv',
        'mac': 'encMac',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final byId = await OfflineStorageService.loadAttachmentById('att-1');
      expect(byId, isNotNull);
      expect(byId!['file_name'], 'passport.png');

      final forItem = await OfflineStorageService.loadAttachmentsForItem('item-note');
      expect(forItem.length, 1);

      await OfflineStorageService.deleteAttachmentsForItem('item-note');
      expect(await OfflineStorageService.loadAttachmentById('att-1'), isNull);
    });
  });

  group('3-Way Sync Merge & Revision Snapshots', () {
    test('reconcileThreeWay covers clean update, offline push, clean match, and concurrent conflict', () {
      // Clean local accepts remote
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: false,
          baseHash: 'h1',
          localHash: 'h1',
          remoteHash: 'h2',
          localDeleted: false,
          remoteDeleted: false,
        ),
        SyncMergeDecision.useRemote,
      );

      // Dirty local with identical remote content marks clean
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h2',
          remoteHash: 'h2',
          localDeleted: false,
          remoteDeleted: false,
        ),
        SyncMergeDecision.markCleanMatching,
      );

      // Dirty local while remote unchanged pushes local
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h2',
          remoteHash: 'h1',
          localDeleted: false,
          remoteDeleted: false,
        ),
        SyncMergeDecision.pushLocal,
      );

      // Both local and remote changed differently since baseHash -> conflict!
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h2',
          remoteHash: 'h3',
          localDeleted: false,
          remoteDeleted: false,
        ),
        SyncMergeDecision.conflict,
      );

      // Dirty local vs remote delete -> conflict!
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h2',
          remoteHash: 'h1',
          localDeleted: false,
          remoteDeleted: true,
        ),
        SyncMergeDecision.conflict,
      );

      // Local delete vs remote modified -> conflict!
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h1',
          remoteHash: 'h3',
          localDeleted: true,
          remoteDeleted: false,
        ),
        SyncMergeDecision.conflict,
      );

      // Local delete vs remote unchanged -> pushLocal!
      expect(
        VaultProvider.reconcileThreeWay(
          localDirty: true,
          baseHash: 'h1',
          localHash: 'h1',
          remoteHash: 'h1',
          localDeleted: true,
          remoteDeleted: false,
        ),
        SyncMergeDecision.pushLocal,
      );
    });

    test('withRevisionSnapshot creates snapshot on material edit and caps at VaultItem.maxRevisions', () {
      var item = VaultItem(
        id: 'n1',
        type: VaultItemType.note,
        title: 'Title 0',
        content: 'Body 0',
      );

      // Same content does not add duplicate snapshot
      final unchanged = VaultProvider.withRevisionSnapshot(item, item.copyWith());
      expect(unchanged.revisions, isEmpty);

      for (int i = 1; i <= VaultItem.maxRevisions + 5; i++) {
        final next = item.copyWith(title: 'Title $i', content: 'Body $i');
        item = VaultProvider.withRevisionSnapshot(item, next);
      }
      expect(item.revisions.length, VaultItem.maxRevisions);
      expect(item.revisions.first.title, 'Title ${VaultItem.maxRevisions + 4}');
    });
  });

  group('SecurityLogService Encrypted Log & Brute-Force Lockout', () {
    test('encrypts security logs, escalates lockout durations, and resets cleanly', () async {
      final logService = SecurityLogService();

      await logService.logEvent(
        SecurityEventType.unlockSuccess,
        'Kasa açıldı',
      );
      final logs = await logService.loadLogs();
      expect(logs.length, 1);
      expect(logs.first.detail, 'Kasa açıldı');

      // Ensure raw stored SharedPreferences string is encrypted, not plaintext
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.contains('security_log'));
      for (final k in keys) {
        final val = prefs.get(k)?.toString() ?? '';
        expect(val.contains('Kasa açıldı'), isFalse);
      }

      // Trigger 1..6 and verify exact lockout & biometric disable ladder
      for (int i = 1; i <= 6; i++) {
        final res = await logService.recordFailedAttempt(sourceLabel: 'Test');
        expect(res.failedCount, i);
        if (i < 3) {
          expect(res.lockoutDuration, Duration.zero);
          expect(res.biometricDisabled, isFalse);
        } else if (i == 3) {
          expect(res.lockoutDuration, const Duration(seconds: 15));
          expect(res.biometricDisabled, isTrue);
        } else if (i == 4) {
          expect(res.lockoutDuration, const Duration(seconds: 30));
          expect(res.biometricDisabled, isTrue);
        } else if (i == 5) {
          expect(res.lockoutDuration, const Duration(seconds: 60));
          expect(res.biometricDisabled, isTrue);
        } else {
          expect(res.lockoutDuration, const Duration(minutes: 5));
          expect(res.biometricDisabled, isTrue);
        }
      }

      expect(await logService.isBiometricTemporarilyDisabled(), isTrue);
      expect((await logService.getRemainingLockout()).inSeconds, greaterThan(0));

      await logService.resetFailedAttempts();
      expect(await logService.getFailedAttempts(), 0);
      expect(await logService.isBiometricTemporarilyDisabled(), isFalse);
      expect(await logService.getRemainingLockout(), Duration.zero);

      final allLogs = await logService.loadLogs();
      expect(allLogs.any((e) => e.isWarning), isTrue);
      expect(Uint8List(0).length, 0);
    });
  });
}
