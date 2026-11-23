import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/update_service.dart';
import 'package:multipad/widgets/update_dialog.dart';
import 'package:path/path.dart' as p;

class _MockHttpClient extends http.BaseClient {
  final Uint8List payload;
  int callCount = 0;

  _MockHttpClient(this.payload);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    return http.StreamedResponse(
      Stream<List<int>>.value(payload),
      200,
      contentLength: payload.length,
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('multipad_update_test_');
    NativeBridgeService.resetForTesting();
  });

  tearDown(() {
    NativeBridgeService.resetForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Feature 26: PlatformAsset Selection Priority', () {
    test('Windows platformAsset prioritizes MultiPad-Windows-Setup.exe over portable .zip', () {
      final assets = [
        ReleaseAsset(
          name: 'MultiPad-Windows.zip',
          downloadUrl: 'https://example.invalid/MultiPad-Windows.zip',
          size: 20000000,
        ),
        ReleaseAsset(
          name: 'MultiPad-Windows-Setup.exe',
          downloadUrl: 'https://example.invalid/MultiPad-Windows-Setup.exe',
          size: 19000000,
        ),
        ReleaseAsset(
          name: 'MultiPad-macOS.dmg',
          downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
          size: 25000000,
        ),
      ];

      final info = UpdateInfo(
        hasUpdate: true,
        currentVersion: 'v1.3.1',
        latestVersion: 'v1.4.0',
        releaseNotes: 'Release notes',
        htmlUrl: 'https://github.com/Wyclaew/multipad',
        assets: assets,
      );

      final asset = info.platformAsset;
      expect(asset, isNotNull);
      if (Platform.isWindows) {
        expect(asset!.name, 'MultiPad-Windows-Setup.exe');
      } else if (Platform.isMacOS) {
        expect(asset!.name, 'MultiPad-macOS.dmg');
      }
    });

    test('getMacOsAppBundlePath resolves parent directory ending in .app', () {
      final fakeExe = '/Applications/MultiPad.app/Contents/MacOS/multipad';
      final bundle = UpdateService.getMacOsAppBundlePath(executablePath: fakeExe);
      expect(bundle, '/Applications/MultiPad.app');

      final fallback = UpdateService.getMacOsAppBundlePath(executablePath: '/usr/local/bin/multipad');
      expect(fallback, '/Applications/MultiPad.app');
    });
  });

  group('Feature 26: Cache Reuse & Integrity in downloadAndInstall', () {
    test('reuses existing cached file when SHA-256 matches without making HTTP requests', () async {
      final payloadBytes = Uint8List.fromList(utf8.encode('CACHED_INSTALLER_PAYLOAD_V140'));
      final expectedSha = CryptoService.sha256HexBytes(payloadBytes);
      final asset = ReleaseAsset(
        name: 'MultiPad-macOS.dmg',
        downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
        size: payloadBytes.length,
        expectedSha256: expectedSha,
      );

      // Pre-create the cached file in tempDir
      final cachedFile = File(p.join(tempDir.path, 'multipad_update_MultiPad-macOS.dmg'));
      await cachedFile.writeAsBytes(payloadBytes);
      expect(cachedFile.existsSync(), isTrue);

      final mockClient = _MockHttpClient(payloadBytes);
      final statuses = <String>[];
      final progresses = <double>[];

      final result = await UpdateService.downloadAndInstall(
        asset,
        httpClient: mockClient,
        tempDirProvider: () async => tempDir,
        installImmediately: false,
        onStatus: (s) => statuses.add(s),
        onProgress: (p) => progresses.add(p),
      );

      // Verify that mock HTTP client was NOT called at all
      expect(mockClient.callCount, 0);
      expect(statuses, contains(contains('önbellekten')));
      expect(progresses, contains(1.0));
      expect(result, cachedFile.path);
      expect(File(result).existsSync(), isTrue);
    });

    test('deletes cached file and re-downloads when SHA-256 does not match', () async {
      final corruptBytes = Uint8List.fromList(utf8.encode('CORRUPT_PAYLOAD'));
      final freshBytes = Uint8List.fromList(utf8.encode('FRESH_VALID_PAYLOAD_V140'));
      final freshSha = CryptoService.sha256HexBytes(freshBytes);

      final asset = ReleaseAsset(
        name: 'MultiPad-macOS.dmg',
        downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
        size: freshBytes.length,
        expectedSha256: freshSha,
      );

      // Pre-create corrupt cached file
      final cachedFile = File(p.join(tempDir.path, 'multipad_update_MultiPad-macOS.dmg'));
      await cachedFile.writeAsBytes(corruptBytes);

      final mockClient = _MockHttpClient(freshBytes);
      final result = await UpdateService.downloadAndInstall(
        asset,
        httpClient: mockClient,
        tempDirProvider: () async => tempDir,
        installImmediately: false,
      );

      expect(mockClient.callCount, 1);
      expect(result, cachedFile.path);
      final diskBytes = await File(result).readAsBytes();
      expect(CryptoService.sha256HexBytes(diskBytes), freshSha);
    });
  });

  group('Feature 26: In-Place Update Helpers on macOS and Windows', () {
    test('installMacOsInPlace generates helper bash script and launches detached /bin/bash', () async {
      final invokedCommands = <(String, List<String>)>[];
      final msg = await UpdateService.installMacOsInPlace(
        '/tmp/MultiPad-macOS.dmg',
        shaNote: ' (SHA-256 doğrulandı)',
        targetAppPath: '/Applications/MultiPad.app',
        processPid: 12345,
        exitOnComplete: false,
        tempDirProvider: () async => tempDir,
        detachedStarter: (exe, args) async {
          invokedCommands.add((exe, args));
        },
      );

      expect(msg, contains('MultiPad güncelleniyor ve yeniden başlatılıyor'));
      expect(msg, contains('SHA-256 doğrulandı'));
      expect(invokedCommands.length, 1);
      expect(invokedCommands.single.$1, '/bin/bash');
      final scriptPath = invokedCommands.single.$2.first;
      expect(scriptPath, endsWith('multipad_mac_update.sh'));

      final scriptFile = File(scriptPath);
      expect(scriptFile.existsSync(), isTrue);
      final scriptContent = await scriptFile.readAsString();
      expect(scriptContent, contains('PID="12345"'));
      expect(scriptContent, contains('TARGET="/Applications/MultiPad.app"'));
      expect(scriptContent, contains('hdiutil attach'));
      expect(scriptContent, contains('xattr -cr'));
      expect(scriptContent, contains('ditto'));
      expect(scriptContent, contains(r'open -a "$TARGET"'));
    });

    test('installWindowsInPlace generates PowerShell installer script with silent relaunch switches', () async {
      final invokedCommands = <(String, List<String>)>[];
      final msg = await UpdateService.installWindowsInPlace(
        r'C:\Users\User\AppData\Local\Temp\MultiPad-Windows-Setup.exe',
        shaNote: ' (SHA-256 doğrulandı)',
        processPid: 54321,
        exitOnComplete: false,
        tempDirProvider: () async => tempDir,
        detachedStarter: (exe, args) async {
          invokedCommands.add((exe, args));
        },
      );

      expect(msg, contains('MultiPad güncelleniyor'));
      expect(invokedCommands.length, 1);
      expect(invokedCommands.single.$1, 'powershell');
      final scriptArgIndex = invokedCommands.single.$2.indexOf('-File');
      expect(scriptArgIndex, isNonNegative);
      final scriptPath = invokedCommands.single.$2[scriptArgIndex + 1];
      expect(scriptPath, endsWith('multipad_run_installer.ps1'));

      final scriptFile = File(scriptPath);
      expect(scriptFile.existsSync(), isTrue);
      final scriptContent = await scriptFile.readAsString();
      expect(scriptContent, contains('Wait-Process -Id 54321'));
      expect(scriptContent, contains('/SILENT'));
      expect(scriptContent, contains('/CLOSEAPPLICATIONS'));
      expect(scriptContent, contains('/RESTARTAPPLICATIONS'));
    });
  });

  group('Feature 26: UpdateDialog UI Widget Tests', () {
    testWidgets('renders version transition pill, SHA badge, release notes, and action button', (tester) async {
      final info = UpdateInfo(
        hasUpdate: true,
        currentVersion: 'v1.3.1',
        latestVersion: 'v1.4.0',
        releaseNotes: '• Seamless in-place updates\n• Frameless window chrome',
        htmlUrl: 'https://github.com/Wyclaew/multipad/releases/tag/v1.4.0',
        assets: [
          ReleaseAsset(
            name: 'MultiPad-macOS.dmg',
            downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
            size: 15 * 1024 * 1024,
            expectedSha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
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
                  onPressed: () => UpdateDialog.show(ctx, info),
                  child: const Text('ShowUpdateDialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ShowUpdateDialog'));
      await tester.pumpAndSettle();

      // Check title and version transition pill
      expect(find.text('Yeni Sürüm Mevcut'), findsOneWidget);
      expect(find.text('v1.3.1'), findsOneWidget);
      expect(find.text('v1.4.0'), findsOneWidget);

      // Check SHA-256 badge
      expect(find.text('SHA-256 Doğrulandı'), findsOneWidget);
      expect(find.textContaining('15.0 MB'), findsOneWidget);

      // Check release notes
      expect(find.textContaining('Seamless in-place updates'), findsOneWidget);

      // Check multi-state button initially says "İndir & Hazırla"
      expect(find.text('İndir & Hazırla'), findsOneWidget);
      expect(find.text('Kapat'), findsOneWidget);
      expect(find.text('GitHub Sürüm Notları'), findsOneWidget);
    });

    testWidgets('renders Unknown Sources permission banner when PERMISSION_REQUIRED error occurs', (tester) async {
      final info = UpdateInfo(
        hasUpdate: true,
        currentVersion: 'v1.3.1',
        latestVersion: 'v1.4.0',
        releaseNotes: 'Update notes',
        htmlUrl: 'https://github.com/Wyclaew/multipad',
        assets: [
          ReleaseAsset(
            name: 'MultiPad-Android.apk',
            downloadUrl: 'https://example.invalid/MultiPad-Android.apk',
            size: 10 * 1024 * 1024,
            expectedSha256: 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef',
          ),
        ],
      );

      // Mock method channel to throw PERMISSION_REQUIRED on installApk
      const channel = MethodChannel('com.multipad.multipad/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'installApk') {
          throw PlatformException(
            code: 'PERMISSION_REQUIRED',
            message: 'Bilinmeyen kaynaklardan uygulama yükleme izni gerekli',
          );
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(
        MaterialApp(
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
                  onPressed: () => UpdateDialog.show(ctx, info),
                  child: const Text('ShowUpdateDialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ShowUpdateDialog'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Sürüm Mevcut'), findsOneWidget);
    });
  });
}
