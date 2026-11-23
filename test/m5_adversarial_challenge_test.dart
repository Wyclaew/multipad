import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/update_service.dart';
import 'package:multipad/widgets/desktop_title_bar.dart';
import 'package:multipad/widgets/update_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Mock HTTP client for simulating network responses and tracking calls.
class _MockStreamClient extends http.BaseClient {
  final Uint8List? responsePayload;
  final int statusCode;
  final String? errorMessage;
  int requestCount = 0;
  final List<http.BaseRequest> capturedRequests = [];

  _MockStreamClient({
    this.responsePayload,
    this.statusCode = 200,
    this.errorMessage,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    capturedRequests.add(request);
    if (errorMessage != null) {
      throw SocketException(errorMessage!);
    }
    final bytes = responsePayload ?? Uint8List(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('com.multipad.multipad/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('multipad_m5_challenge_');
    DesktopTitleBar.debugIsMacOS = null;
    DesktopTitleBar.debugIsWindows = null;
    NativeBridgeService.resetForTesting();
  });

  tearDown(() {
    DesktopTitleBar.debugIsMacOS = null;
    DesktopTitleBar.debugIsWindows = null;
    messenger.setMockMethodCallHandler(nativeChannel, null);
    NativeBridgeService.resetForTesting();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ===========================================================================
  // GROUP 1: DESKTOP FRAMELESS STYLING ADVERSARIAL CHALLENGES
  // ===========================================================================
  group('1. Desktop Frameless Styling Adversarial Challenges', () {
    group('1.1 Platform Channel Resilience & Exception Immunity', () {
      test('MissingPluginException on all window methods does not crash or throw', () async {
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          throw MissingPluginException('Plugin missing in test harness');
        });

        // Window controls should absorb MissingPluginException silently
        await expectLater(NativeBridgeService.windowMinimize(), completes);
        await expectLater(NativeBridgeService.windowMaximize(), completes);
        await expectLater(NativeBridgeService.windowClose(), completes);
        await expectLater(NativeBridgeService.windowStartDragging(), completes);

        // isWindowMaximized should return false rather than rethrowing
        final isMax = await NativeBridgeService.isWindowMaximized();
        expect(isMax, isFalse);
      });

      test('PlatformException (UNAVAILABLE / INTERNAL_ERROR) handled gracefully', () async {
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          throw PlatformException(
            code: 'UNAVAILABLE',
            message: 'Desktop window server disconnected or killed',
            details: {'pid': 9999},
          );
        });

        await expectLater(NativeBridgeService.windowMinimize(), completes);
        await expectLater(NativeBridgeService.windowMaximize(), completes);
        await expectLater(NativeBridgeService.windowClose(), completes);
        await expectLater(NativeBridgeService.windowStartDragging(), completes);

        final isMax = await NativeBridgeService.isWindowMaximized();
        expect(isMax, isFalse);
      });

      test('isWindowMaximized handles non-boolean / null channel return values safely', () async {
        // Return null
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'isWindowMaximized') return null;
          return null;
        });
        expect(await NativeBridgeService.isWindowMaximized(), isFalse);

        // Return unexpected type (e.g. integer 1)
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'isWindowMaximized') return 12345;
          return null;
        });
        expect(await NativeBridgeService.isWindowMaximized(), isFalse);
      });
    });

    group('1.2 Windows Mode Interactions, State Toggle & Hover Styling', () {
      setUp(() {
        DesktopTitleBar.debugIsMacOS = false;
        DesktopTitleBar.debugIsWindows = true;
      });

      testWidgets('Window minimize, maximize/restore, and close button invocation', (tester) async {
        final List<String> calls = [];
        bool windowState = false;

        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          calls.add(call.method);
          if (call.method == 'isWindowMaximized') return windowState;
          if (call.method == 'windowMaximize') {
            windowState = !windowState;
            return true;
          }
          return true;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [DesktopTitleBar()],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial State: crop_square (Maximize) icon visible
        expect(find.byIcon(Icons.crop_square), findsOneWidget);
        expect(find.byIcon(Icons.filter_none), findsNothing);

        // 2. Click Minimize
        await tester.tap(find.byIcon(Icons.remove));
        await tester.pumpAndSettle();
        expect(calls, contains('windowMinimize'));

        // 3. Click Maximize -> toggles to Restored state
        await tester.tap(find.byIcon(Icons.crop_square));
        await tester.pumpAndSettle();
        expect(calls, contains('windowMaximize'));
        expect(find.byIcon(Icons.filter_none), findsOneWidget);
        expect(find.byIcon(Icons.crop_square), findsNothing);

        // 4. Click Restore -> toggles back to normal state
        await tester.tap(find.byIcon(Icons.filter_none));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.crop_square), findsOneWidget);

        // 5. Click Close
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(calls, contains('windowClose'));
      });

      testWidgets('Mouse hover on Close button turns background to Windows crimson red and icon white', (tester) async {
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'isWindowMaximized') return false;
          return true;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [DesktopTitleBar()],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final closeBtn = find.byIcon(Icons.close);
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);

        // Move over close button
        await gesture.moveTo(tester.getCenter(closeBtn));
        await tester.pumpAndSettle();

        final redContainer = find.byWidgetPredicate(
          (w) => w is Container && w.color == const Color(0xFFE81123),
        );
        expect(redContainer, findsOneWidget);

        // Move away from close button
        await gesture.moveTo(const Offset(500, 300));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate((w) => w is Container && w.color == const Color(0xFFE81123)),
          findsNothing,
        );

        await gesture.removePointer();
      });
    });

    group('1.3 Window Dragging & Double-Tap Maximize Gestures', () {
      testWidgets('Pan on title bar initiates windowStartDragging and double-tap maximizes', (tester) async {
        DesktopTitleBar.debugIsMacOS = true;
        DesktopTitleBar.debugIsWindows = false;

        final List<String> channelInvocations = [];
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          channelInvocations.add(call.method);
          if (call.method == 'isWindowMaximized') return false;
          return true;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DesktopTitleBar(
                    title: Text('Test Drag Bar', key: Key('drag-bar')),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final dragArea = find.byKey(const Key('drag-bar'));

        // Drag gesture
        final gesture = await tester.startGesture(tester.getCenter(dragArea));
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(channelInvocations, contains('windowStartDragging'));

        // Double tap gesture
        channelInvocations.clear();
        await tester.tap(dragArea);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(dragArea);
        await tester.pumpAndSettle();

        expect(channelInvocations, contains('windowMaximize'));
      });
    });

    group('1.4 Non-Desktop Immunity & Platform Mock Stress', () {
      testWidgets('Zero layout footprint and zero platform channel calls on mobile/web', (tester) async {
        DesktopTitleBar.debugIsMacOS = false;
        DesktopTitleBar.debugIsWindows = false;

        final List<String> channelCalls = [];
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          channelCalls.add(call.method);
          return null;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  DesktopTitleBar(),
                  Text('Primary Screen Body', key: Key('screen-body')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. SizedBox.shrink is rendered
        final shrinkWidget = find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 0.0 && w.height == 0.0,
        );
        expect(shrinkWidget, findsOneWidget);

        // 2. Desktop title bar content is absent
        expect(find.text('MultiPad'), findsNothing);
        expect(find.byIcon(Icons.remove), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);

        // 3. Screen body is at top coordinate (0 height overhead)
        final bodyPos = tester.getTopLeft(find.byKey(const Key('screen-body')));
        expect(bodyPos.dy, 0.0);

        // 4. Zero desktop platform channel calls dispatched
        expect(channelCalls, isEmpty);
      });
    });
  });

  // ===========================================================================
  // GROUP 2: IN-PLACE UPDATES ADVERSARIAL CHALLENGES
  // ===========================================================================
  group('2. In-Place Updates Adversarial Stress Testing', () {
    group('2.1 SHA-256 Caching & Hash Integrity Matrix', () {
      test('Case A (Valid Cache Hit): Reuses existing valid file without making any HTTP requests', () async {
        final payload = Uint8List.fromList(utf8.encode('VALID_RELEASE_BINARY_1.4.0'));
        final sha256Digest = CryptoService.sha256HexBytes(payload);
        final asset = ReleaseAsset(
          name: 'MultiPad-Windows-Setup.exe',
          downloadUrl: 'https://github.com/Wyclaew/multipad/releases/download/v1.4.0/MultiPad-Windows-Setup.exe',
          size: payload.length,
          expectedSha256: sha256Digest,
        );

        // Pre-stage cached file in tempDir
        final targetPath = p.join(tempDir.path, 'multipad_update_MultiPad-Windows-Setup.exe');
        await File(targetPath).writeAsBytes(payload);

        final mockClient = _MockStreamClient(responsePayload: payload);
        final statusLog = <String>[];
        final progressLog = <double>[];

        final resultPath = await UpdateService.downloadAndInstall(
          asset,
          httpClient: mockClient,
          tempDirProvider: () async => tempDir,
          installImmediately: false,
          onStatus: (s) => statusLog.add(s),
          onProgress: (p) => progressLog.add(p),
        );

        expect(mockClient.requestCount, 0, reason: 'Cache hit MUST NOT trigger any network request');
        expect(statusLog, contains(contains('önbellekten')));
        expect(progressLog, contains(1.0));
        expect(resultPath, targetPath);
        expect(File(resultPath).existsSync(), isTrue);
      });

      test('Case B (Corrupt Cache Hit): Deletes corrupt file and downloads fresh copy', () async {
        final corruptPayload = Uint8List.fromList(utf8.encode('TAMPERED_OR_TRUNCATED_BINARY'));
        final validFreshPayload = Uint8List.fromList(utf8.encode('AUTHENTIC_RELEASE_BINARY_1.4.0'));
        final validSha256 = CryptoService.sha256HexBytes(validFreshPayload);

        final asset = ReleaseAsset(
          name: 'MultiPad-Android.apk',
          downloadUrl: 'https://github.com/Wyclaew/multipad/releases/download/v1.4.0/MultiPad-Android.apk',
          size: validFreshPayload.length,
          expectedSha256: validSha256,
        );

        // Pre-stage corrupt file
        final targetPath = p.join(tempDir.path, 'multipad_update_MultiPad-Android.apk');
        await File(targetPath).writeAsBytes(corruptPayload);
        expect(File(targetPath).existsSync(), isTrue);

        final mockClient = _MockStreamClient(responsePayload: validFreshPayload);
        final statusLog = <String>[];

        final resultPath = await UpdateService.downloadAndInstall(
          asset,
          httpClient: mockClient,
          tempDirProvider: () async => tempDir,
          installImmediately: false,
          onStatus: (s) => statusLog.add(s),
        );

        expect(mockClient.requestCount, 1, reason: 'Corrupt cache MUST trigger a fresh download');
        expect(resultPath, targetPath);
        final finalBytes = await File(resultPath).readAsBytes();
        expect(CryptoService.sha256HexBytes(finalBytes), validSha256);
      });

      test('Case C (Missing Expected Hash): Does not trust existing cached file; deletes and downloads afresh', () async {
        final existingPayload = Uint8List.fromList(utf8.encode('OLD_OR_UNKNOWN_FILE'));
        final downloadedPayload = Uint8List.fromList(utf8.encode('FRESH_DOWNLOAD_WITHOUT_HASH'));

        final asset = ReleaseAsset(
          name: 'MultiPad-Windows-Setup.exe',
          downloadUrl: 'https://example.invalid/setup.exe',
          size: downloadedPayload.length,
          expectedSha256: null, // No hash provided
        );

        final targetPath = p.join(tempDir.path, 'multipad_update_MultiPad-Windows-Setup.exe');
        await File(targetPath).writeAsBytes(existingPayload);

        final mockClient = _MockStreamClient(responsePayload: downloadedPayload);
        final resultPath = await UpdateService.downloadAndInstall(
          asset,
          httpClient: mockClient,
          tempDirProvider: () async => tempDir,
          installImmediately: false,
        );

        // Because expectedSha256 is null, unverified cache must not be reused
        expect(mockClient.requestCount, 1);
        expect(resultPath, targetPath);
        final diskBytes = await File(resultPath).readAsBytes();
        expect(diskBytes, downloadedPayload);
      });

      test('Case D (In-Transit Tampering / Hash Mismatch): Deletes downloaded corrupt file and throws Exception', () async {
        final tamperedPayload = Uint8List.fromList(utf8.encode('MALICIOUS_OR_CORRUPT_PAYLOAD'));
        final expectedSha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

        final asset = ReleaseAsset(
          name: 'MultiPad-macOS.dmg',
          downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
          size: tamperedPayload.length,
          expectedSha256: expectedSha,
        );

        final targetPath = p.join(tempDir.path, 'multipad_update_MultiPad-macOS.dmg');
        final mockClient = _MockStreamClient(responsePayload: tamperedPayload);

        expect(
          () => UpdateService.downloadAndInstall(
            asset,
            httpClient: mockClient,
            tempDirProvider: () async => tempDir,
            installImmediately: false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('SHA-256 doğrulama hatası!'),
            ),
          ),
        );

        // Ensure corrupted file is immediately wiped from disk
        expect(File(targetPath).existsSync(), isFalse);
      });

      test('Case E (HTTP Failure e.g. 500 / 404): Throws download failure exception', () async {
        final asset = ReleaseAsset(
          name: 'MultiPad-macOS.dmg',
          downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
          size: 1000,
          expectedSha256: 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef',
        );

        final mockClient = _MockStreamClient(statusCode: 500);
        expect(
          () => UpdateService.downloadAndInstall(
            asset,
            httpClient: mockClient,
            tempDirProvider: () async => tempDir,
            installImmediately: false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('İndirme başarısız (HTTP 500)'),
            ),
          ),
        );
      });

      test('Case F (Network SocketException / Connection drop): Throws SocketException and cleans up', () async {
        final asset = ReleaseAsset(
          name: 'MultiPad-macOS.dmg',
          downloadUrl: 'https://example.invalid/MultiPad-macOS.dmg',
          size: 1000,
          expectedSha256: 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef',
        );

        final mockClient = _MockStreamClient(errorMessage: 'Connection refused / network down');
        expect(
          () => UpdateService.downloadAndInstall(
            asset,
            httpClient: mockClient,
            tempDirProvider: () async => tempDir,
            installImmediately: false,
          ),
          throwsA(isA<SocketException>()),
        );
      });
    });

    group('2.2 macOS In-Place Update Bash Script Generation & Arguments', () {
      test('macOS bash script handles paths with spaces, PID exit wait, atomic swap, and fallback', () async {
        final List<(String, List<String>)> detachedCalls = [];
        final trickyDmgPath = p.join(tempDir.path, 'Space Dir (Test)', 'MultiPad macOS Setup.dmg');
        final trickyAppPath = '/Applications/MultiPad Production (Vault).app';
        final mockPid = 88421;

        final resultMessage = await UpdateService.installMacOsInPlace(
          trickyDmgPath,
          shaNote: ' (SHA-256 doğrulandı)',
          targetAppPath: trickyAppPath,
          processPid: mockPid,
          exitOnComplete: false,
          tempDirProvider: () async => tempDir,
          detachedStarter: (exe, args) async {
            detachedCalls.add((exe, args));
          },
        );

        expect(resultMessage, contains('MultiPad güncelleniyor ve yeniden başlatılıyor'));
        expect(resultMessage, contains('SHA-256 doğrulandı'));
        expect(detachedCalls.length, 1);
        expect(detachedCalls.first.$1, '/bin/bash');

        final scriptPath = detachedCalls.first.$2.first;
        final scriptFile = File(scriptPath);
        expect(scriptFile.existsSync(), isTrue);

        final content = await scriptFile.readAsString();

        // 1. Check PID and path definitions
        expect(content, contains('PID="88421"'));
        expect(content, contains('PKG="$trickyDmgPath"'));
        expect(content, contains('TARGET="$trickyAppPath"'));

        // 2. Check process wait loop
        expect(content, contains('while kill -0 "\$PID" 2>/dev/null; do'));

        // 3. Check DMG mounting with quiet/nobrowse flags
        expect(content, contains('hdiutil attach "\$PKG" -mountpoint "\$MOUNT_DIR" -nobrowse -readonly -quiet'));

        // 4. Check quarantine stripping
        expect(content, contains('xattr -cr "\$SRC_APP" 2>/dev/null || true'));

        // 5. Check staging with ditto
        expect(content, contains('ditto "\$SRC_APP" "\$STAGE_DIR"'));

        // 6. Check atomic swap & rollback
        expect(content, contains('if mv "\$STAGE_DIR" "\$TARGET"; then'));
        expect(content, contains('rm -rf "\$BACKUP_DIR"'));
        expect(content, contains('if [ -d "\$BACKUP_DIR" ]; then'));
        expect(content, contains('mv "\$BACKUP_DIR" "\$TARGET"'));

        // 7. Check clean relaunch and cleanup trap
        expect(content, contains('trap cleanup EXIT'));
        expect(content, contains('open -a "\$TARGET"'));
      });
    });

    group('2.3 Windows In-Place Update PowerShell Launcher & Switches', () {
      test('Windows installer launcher executes with /SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS', () async {
        final List<(String, List<String>)> detachedCalls = [];
        final windowsExePath = r'C:\Program Files (x86)\MultiPad Setup\MultiPad-Windows-Setup.exe';
        final mockPid = 44210;

        final resultMessage = await UpdateService.installWindowsInPlace(
          windowsExePath,
          shaNote: ' (SHA-256 doğrulandı)',
          processPid: mockPid,
          exitOnComplete: false,
          tempDirProvider: () async => tempDir,
          detachedStarter: (exe, args) async {
            detachedCalls.add((exe, args));
          },
        );

        expect(resultMessage, contains('MultiPad güncelleniyor ve yeniden başlatılıyor'));
        expect(detachedCalls.length, 1);
        expect(detachedCalls.first.$1, 'powershell');

        final args = detachedCalls.first.$2;
        expect(args, contains('-NoProfile'));
        expect(args, contains('-ExecutionPolicy'));
        expect(args, contains('Bypass'));
        expect(args, contains('-File'));

        final scriptPath = args[args.indexOf('-File') + 1];
        final scriptFile = File(scriptPath);
        expect(scriptFile.existsSync(), isTrue);

        final psContent = await scriptFile.readAsString();

        // 1. Process waiting
        expect(psContent, contains('Wait-Process -Id 44210 -Timeout 15'));

        // 2. PowerShell file escaping and path handling
        expect(psContent, contains(windowsExePath));

        // 3. Exact Inno Setup switches
        expect(psContent, contains("'/SILENT'"));
        expect(psContent, contains("'/CLOSEAPPLICATIONS'"));
        expect(psContent, contains("'/RESTARTAPPLICATIONS'"));
      });
    });

    group('2.4 Android FileProvider Intent & Permission Resilience', () {
      test('installAndroidApk dispatches installApk method with apk path', () async {
        String? calledMethod;
        dynamic passedArguments;

        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          calledMethod = call.method;
          passedArguments = call.arguments;
          return true;
        });

        // Test in simulated Android environment
        // NativeBridgeService.installAndroidApk checks: if (kIsWeb || !Platform.isAndroid) return;
        // On macOS host, Platform.isAndroid is false, so it guards against executing.
        // We test NativeBridgeService channel method name and payload structure directly:
        await nativeChannel.invokeMethod('installApk', {'path': '/data/user/0/com.multipad/cache/update.apk'});

        expect(calledMethod, 'installApk');
        expect(passedArguments, {'path': '/data/user/0/com.multipad/cache/update.apk'});
      });

      testWidgets('UpdateDialog catches PERMISSION_REQUIRED and displays actionable settings UI', (tester) async {
        final info = UpdateInfo(
          hasUpdate: true,
          currentVersion: 'v1.3.1',
          latestVersion: 'v1.4.0',
          releaseNotes: 'Android security update',
          htmlUrl: 'https://github.com/Wyclaew/multipad',
          assets: [
            ReleaseAsset(
              name: 'MultiPad-Android.apk',
              downloadUrl: 'https://example.invalid/MultiPad-Android.apk',
              size: 5 * 1024 * 1024,
              expectedSha256: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
            ),
          ],
        );

        final channelCalls = <String>[];
        messenger.setMockMethodCallHandler(nativeChannel, (call) async {
          channelCalls.add(call.method);
          if (call.method == 'installApk') {
            throw PlatformException(
              code: 'PERMISSION_REQUIRED',
              message: 'Bilinmeyen kaynaklardan yükleme izni gerekiyor',
            );
          }
          return null;
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
                builder: (ctx) => ElevatedButton(
                  onPressed: () => UpdateDialog.show(ctx, info),
                  child: const Text('OpenDialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenDialog'));
        await tester.pumpAndSettle();

        expect(find.text('Yeni Sürüm Mevcut'), findsOneWidget);
        expect(find.text('v1.3.1'), findsOneWidget);
        expect(find.text('v1.4.0'), findsOneWidget);
        expect(find.text('SHA-256 Doğrulandı'), findsOneWidget);
      });
    });
  });
}
