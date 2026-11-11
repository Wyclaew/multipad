import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/main.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/offline_storage_service.dart';
import 'package:multipad/services/pairing_service.dart';
import 'package:multipad/services/update_service.dart';
import 'package:multipad/widgets/password_generator_dialog.dart';
import 'package:multipad/widgets/quick_search_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StubHttpClient extends http.BaseClient {
  final Uint8List payload;
  final int statusCode;

  _StubHttpClient(this.payload, {this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      statusCode,
      contentLength: payload.length,
    );
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ClipboardService.setDefaultTimeoutSeconds(30);
    NativeBridgeService.resetForTesting();
    tempDir = Directory.systemTemp.createTempSync('multipad_fixes_test_');
    DatabaseService.configureForTesting(
      dbPath: p.join(tempDir.path, 'fixes_test.db'),
    );
  });

  tearDown(() async {
    ClipboardService.cancelScheduledClear();
    NativeBridgeService.resetForTesting();
    await DatabaseService.closeForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UpdateService parsing, version comparison & macOS installer safety', () {
    test('parseSha256Sums parses binary asterisk and path prefixes correctly', () {
      const sample = '''
# release checksums
0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef *dist/MultiPad-Windows.zip
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  MultiPad-Android.apk
invalid line ignored
''';
      final parsed = UpdateService.parseSha256Sums(sample);
      expect(parsed.length, 2);
      expect(
        parsed['MultiPad-Windows.zip'],
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      );
      expect(
        parsed['MultiPad-Android.apk'],
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
    });

    test('isVersionNewer compares semantic major.minor.patch versions accurately', () {
      expect(UpdateService.isVersionNewer('1.2.0', '1.1.9'), isTrue);
      expect(UpdateService.isVersionNewer('1.1.10', '1.1.2'), isTrue);
      expect(UpdateService.isVersionNewer('1.1.0', '1.1.0'), isFalse);
      expect(UpdateService.isVersionNewer('1.0.9', '1.1.0'), isFalse);
    });

    test('openMacOsInstaller invokes only open without xattr and returns Apple GUI guidance', () async {
      final invokedCommands = <(String, List<String>)>[];
      final msg = await UpdateService.openMacOsInstaller(
        '/tmp/MultiPad-macOS.dmg',
        shaNote: ' (SHA-256 doğrulandı)',
        startDetached: (exe, args) async {
          invokedCommands.add((exe, args));
        },
      );

      expect(invokedCommands.length, 1);
      expect(invokedCommands.single.$1, 'open');
      expect(invokedCommands.single.$2, ['/tmp/MultiPad-macOS.dmg']);
      expect(
        invokedCommands.any((c) => c.$1.contains('xattr') || c.$2.join(' ').contains('quarantine')),
        isFalse,
      );
      expect(msg, contains('Applications'));
      expect(msg, contains('Sağ tık -> Aç'));
      expect(msg, contains('Sistem Ayarları -> Gizlilik ve Güvenlik -> Yine de Aç'));
      expect(msg.toLowerCase(), isNot(contains('xattr')));
      expect(msg.toLowerCase(), isNot(contains('quarantine')));
    });

    test('downloadAndInstall verifies SHA-256 and opens macOS DMG without calling xattr', () async {
      final dmgBytes = Uint8List.fromList(utf8.encode('FAKE_DMG_BINARY_PAYLOAD_V110'));
      final expectedSha = CryptoService.sha256HexBytes(dmgBytes);

      final invokedCommands = <(String, List<String>)>[];
      final resultMsg = await UpdateService.downloadAndInstall(
        ReleaseAsset(
          name: 'MultiPad-macOS.dmg',
          downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
          size: dmgBytes.length,
          expectedSha256: expectedSha,
        ),
        httpClient: _StubHttpClient(dmgBytes),
        tempDirProvider: () async => tempDir,
        isMacOsOverride: true,
        detachedProcessStarter: (exe, args) async {
          invokedCommands.add((exe, args));
        },
      );

      expect(invokedCommands.length, 1);
      expect(invokedCommands.first.$1, 'open');
      expect(invokedCommands.first.$2.single, endsWith('multipad_update_MultiPad-macOS.dmg'));
      expect(
        invokedCommands.any((c) => c.$1 == 'xattr' || c.$2.contains('com.apple.quarantine')),
        isFalse,
      );
      expect(resultMsg, contains('SHA-256 doğrulandı'));
      expect(resultMsg, contains('Sağ tık -> Aç'));
    });

    test('downloadAndInstall rejects SHA-256 mismatch, deletes file, and never launches installer', () async {
      final dmgBytes = Uint8List.fromList(utf8.encode('CORRUPT_DMG_PAYLOAD'));
      final invokedCommands = <(String, List<String>)>[];

      await expectLater(
        () => UpdateService.downloadAndInstall(
          ReleaseAsset(
            name: 'MultiPad-macOS.dmg',
            downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
            size: dmgBytes.length,
            expectedSha256: '0' * 64,
          ),
          httpClient: _StubHttpClient(dmgBytes),
          tempDirProvider: () async => tempDir,
          isMacOsOverride: true,
          detachedProcessStarter: (exe, args) async {
            invokedCommands.add((exe, args));
          },
        ),
        throwsException,
      );

      expect(invokedCommands, isEmpty);
      expect(
        File(p.join(tempDir.path, 'multipad_update_MultiPad-macOS.dmg')).existsSync(),
        isFalse,
      );
    });

    test('downloadAndInstall throws on non-200 HTTP response without launching installer', () async {
      final invokedCommands = <(String, List<String>)>[];
      await expectLater(
        () => UpdateService.downloadAndInstall(
          ReleaseAsset(
            name: 'MultiPad-macOS.dmg',
            downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
            size: 10,
          ),
          httpClient: _StubHttpClient(Uint8List(0), statusCode: 500),
          tempDirProvider: () async => tempDir,
          isMacOsOverride: true,
          detachedProcessStarter: (exe, args) async {
            invokedCommands.add((exe, args));
          },
        ),
        throwsException,
      );
      expect(invokedCommands, isEmpty);
    });
  });

  group('NativeBridgeService Quick Settings Tile & cold-start action', () {
    test('consumes pending quick_search launch action on initialize and handles live calls', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? pending = 'quick_search';
      int consumeCount = 0;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'consumePendingLaunchAction') {
          consumeCount++;
          final value = pending;
          pending = null;
          return value;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      int quickSearchCount = 0;
      int lockCount = 0;
      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => quickSearchCount++,
        onLockVaultRequested: () => lockCount++,
      );

      expect(consumeCount, 1);
      expect(quickSearchCount, 1);
      expect(lockCount, 0);

      // Re-calling initialize should be idempotent and not re-consume
      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => quickSearchCount++,
        onLockVaultRequested: () => lockCount++,
      );
      expect(consumeCount, 1);

      // Simulate warm-start live MethodChannel invocation from Android onNewIntent
      await messenger.handlePlatformMessage(
        nativeChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onQuickSearchRequested'),
        ),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        nativeChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onLockVaultRequested'),
        ),
        (_) {},
      );
      expect(quickSearchCount, 2);
      expect(lockCount, 1);
    });

    testWidgets('MultiPadApp opens QuickSearchDialog on cold-start pending quick_search action', (tester) async {
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? pending = 'quick_search';

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'consumePendingLaunchAction') {
          final val = pending;
          pending = null;
          return val;
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      await tester.pumpWidget(const MultiPadApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(QuickSearchDialog), findsOneWidget);
    });

    testWidgets('MultiPadApp opens QuickSearchDialog once on duplicate warm-start onQuickSearchRequested calls', (tester) async {
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'consumePendingLaunchAction') {
          return null;
        }
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(nativeChannel, null);
        NativeBridgeService.resetForTesting();
      });

      await tester.pumpWidget(const MultiPadApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(QuickSearchDialog), findsNothing);

      for (int i = 0; i < 2; i++) {
        await messenger.handlePlatformMessage(
          nativeChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onQuickSearchRequested'),
          ),
          (_) {},
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(QuickSearchDialog), findsOneWidget);
    });
  });

  group('AuthProvider pairing base_hash & dirty preservation', () {
    test('completePairingSetup preserves base_hash and dirty state from offlineItems', () async {
      final auth = AuthProvider();
      final payload = PairingPayload(
        supabaseUrl: '',
        supabaseAnonKey: '',
        email: 'paired@example.com',
        masterSalt: 'argon2id\$v=19\$m=19456,t=2,p=1\$AAAAAAAAAAAAAAAAAAAAAA',
        masterKeyBase64: null,
        offlineItems: [
          {
            'id': 'synced-item',
            'user_id': 'u-1',
            'item_type': 'note',
            'encrypted_payload': 'ct_clean',
            'iv': 'iv_clean',
            'mac': 'mac_clean',
            'is_deleted': false,
            'client_updated_at': '2026-06-01T10:00:00.000Z',
            'dirty': false,
            'base_hash': 'hash_clean_abc',
          },
          {
            'id': 'offline-edited-item',
            'user_id': 'u-1',
            'item_type': 'credential',
            'encrypted_payload': 'ct_dirty',
            'iv': 'iv_dirty',
            'mac': 'mac_dirty',
            'is_deleted': false,
            'client_updated_at': '2026-06-01T11:00:00.000Z',
            'dirty': true,
            'base_hash': 'hash_prior_xyz',
          },
        ],
      );

      final ok = await auth.completePairingSetup(payload);
      expect(ok, isTrue);

      final items = await OfflineStorageService.loadLocalItems();
      expect(items.length, 2);

      final synced = items.firstWhere((e) => e['id'] == 'synced-item');
      expect(synced['dirty'], isFalse);
      expect(synced['base_hash'], 'hash_clean_abc');

      final dirtyItem = items.firstWhere((e) => e['id'] == 'offline-edited-item');
      expect(dirtyItem['dirty'], isTrue);
      expect(dirtyItem['base_hash'], 'hash_prior_xyz');
    });

    test('completePairingSetup handles integer dirty flags, null base_hash, and enables accurate 3-way reconciliation', () async {
      final auth = AuthProvider();
      final payload = PairingPayload(
        supabaseUrl: '',
        supabaseAnonKey: '',
        email: 'paired2@example.com',
        masterSalt: 'argon2id\$v=19\$m=19456,t=2,p=1\$AAAAAAAAAAAAAAAAAAAAAA',
        masterKeyBase64: null,
        offlineItems: [
          {
            'id': 'int-dirty-item',
            'user_id': 'u-1',
            'item_type': 'note',
            'encrypted_payload': 'ct_dirty_int',
            'iv': 'iv_1',
            'mac': 'mac_1',
            'is_deleted': false,
            'client_updated_at': '2026-06-01T12:00:00.000Z',
            'dirty': 1,
            'base_hash': 'base_v1',
          },
          {
            'id': 'null-base-item',
            'user_id': 'u-1',
            'item_type': 'note',
            'encrypted_payload': 'ct_clean_null',
            'iv': 'iv_2',
            'mac': 'mac_2',
            'is_deleted': false,
            'client_updated_at': '2026-06-01T12:05:00.000Z',
            'dirty': 0,
            'base_hash': null,
          },
        ],
      );

      final ok = await auth.completePairingSetup(payload);
      expect(ok, isTrue);

      final items = await OfflineStorageService.loadLocalItems();
      final intDirty = items.firstWhere((e) => e['id'] == 'int-dirty-item');
      expect(intDirty['dirty'], isTrue);
      expect(intDirty['base_hash'], 'base_v1');

      final nullBase = items.firstWhere((e) => e['id'] == 'null-base-item');
      expect(nullBase['dirty'], isFalse);
      expect(nullBase['base_hash'], isNull);

      // With preserved base_hash == remoteHash, local edit pushes cleanly without false conflict
      final pushDecision = VaultProvider.reconcileThreeWay(
        localDirty: intDirty['dirty'] == true,
        baseHash: intDirty['base_hash'] as String?,
        localHash: 'local_v2',
        remoteHash: 'base_v1',
        localDeleted: false,
        remoteDeleted: false,
      );
      expect(pushDecision, SyncMergeDecision.pushLocal);

      // When remote diverged from preserved base_hash, real 3-way conflict is detected
      final conflictDecision = VaultProvider.reconcileThreeWay(
        localDirty: intDirty['dirty'] == true,
        baseHash: intDirty['base_hash'] as String?,
        localHash: 'local_v2',
        remoteHash: 'remote_v2',
        localDeleted: false,
        remoteDeleted: false,
      );
      expect(conflictDecision, SyncMergeDecision.conflict);
    });
  });

  group('AuthProvider Quick PIN 4-12 digits & logout cleanup', () {
    test('supports 10-digit Quick PIN setup and unlock, rejects <4 and >12 digits', () async {
      final auth = AuthProvider();
      final registered = await auth.register(
        email: 'pinuser@example.com',
        masterPassword: 'StrongMasterPassword#2026',
        useArgon2id: false,
      );
      expect(registered, isTrue);
      expect(auth.isUnlocked, isTrue);

      expect(await auth.enableQuickPin('123'), isFalse);
      expect(await auth.enableQuickPin('1234567890123'), isFalse);

      final enabled = await auth.enableQuickPin('1234567890');
      expect(enabled, isTrue);
      expect(auth.isQuickPinEnabled, isTrue);

      auth.lockVault();
      expect(auth.isUnlocked, isFalse);

      final unlocked = await auth.unlockWithQuickPin('1234567890');
      expect(unlocked, isTrue);
      expect(auth.isUnlocked, isTrue);

      await auth.logout();
      expect(auth.isUnlocked, isFalse);
      expect(auth.isQuickPinEnabled, isFalse);
    });
  });

  group('PasswordGeneratorDialog clipboard timeout setting', () {
    testWidgets('uses configured SettingsProvider clipboardTimeoutSeconds in SnackBar', (tester) async {
      final settings = SettingsProvider();
      await settings.setClipboardTimeoutSeconds(10);

      bool nativeCopyCalled = false;
      String? fallbackClipboardText;
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'copyConfidential') {
          nativeCopyCalled = true;
          return false;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          fallbackClipboardText = args?['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(nativeChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            locale: const Locale('tr'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('tr'), Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
                        context: ctx,
                        builder: (_) => const PasswordGeneratorDialog(),
                      );
                    },
                    child: const Text('OpenGenerator'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('OpenGenerator'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kopyala'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(nativeCopyCalled, isTrue);
      expect(fallbackClipboardText, isNotEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('10 sn'), findsOneWidget);
      ClipboardService.cancelScheduledClear();
    });
  });
}
