import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/main.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/screens/auth_screen.dart';
import 'package:multipad/services/biometric_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/security_log_service.dart';
import 'package:multipad/services/totp_ticker_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBiometricService extends BiometricService {
  bool canCheck = true;
  bool isEnabled = true;
  List<int>? keyToReturn;
  bool throwOnRetrieve = false;
  int retrieveCallCount = 0;

  @override
  Future<bool> canCheckBiometrics() async => canCheck;

  @override
  Future<bool> isBiometricUnlockEnabled() async => isEnabled;

  @override
  Future<List<int>?> retrieveBiometricMasterKey() async {
    retrieveCallCount++;
    if (throwOnRetrieve) {
      throw Exception('Biometric hardware error');
    }
    return keyToReturn;
  }
}

class FakeSecurityLogService extends SecurityLogService {
  @override
  Future<void> logEvent(
    SecurityEventType type,
    String detail, {
    bool isWarning = false,
  }) async {}

  @override
  Future<void> resetFailedAttempts({bool clearBiometricDisable = true}) async {}

  @override
  Future<int> getFailedAttempts() async => 0;

  @override
  Future<bool> isBiometricTemporarilyDisabled() async => false;

  @override
  Future<Duration> getRemainingLockout() async => Duration.zero;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    const nativeChannel = MethodChannel('com.multipad.multipad/native');
    const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
      switch (call.method) {
        case 'consumePendingLaunchAction':
          return null;
        case 'setFlagSecure':
        case 'setMulticastLock':
        case 'configureDesktopShell':
        case 'bringWindowToFront':
        case 'openAutofillSettings':
          return true;
        case 'copyConfidential':
          return true;
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (MethodCall call) async {
      switch (call.method) {
        case 'isDeviceSupported':
          return true;
        case 'canCheckBiometrics':
          return true;
        case 'getAvailableBiometrics':
          return ['fingerprint'];
        case 'authenticate':
          return true;
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ClipboardService.setDefaultTimeoutSeconds(30);
    NativeBridgeService.resetForTesting();
    DatabaseService.configureForTesting(
      dbPath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    TotpTickerService.instance.pause();
    const nativeChannel = MethodChannel('com.multipad.multipad/native');
    const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
    await DatabaseService.closeForTesting();
  });

  group('SettingsProvider - macOS & Desktop Background Lock Configuration', () {
    test('defaultLockOnBackground is false on macOS/desktop and true on Android/iOS', () {
      final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      expect(SettingsProvider.defaultLockOnBackground, isMobile);
    });

    test('fresh SettingsProvider initializes lockOnBackground to defaultLockOnBackground', () async {
      final settings = SettingsProvider();
      expect(settings.lockOnBackground, SettingsProvider.defaultLockOnBackground);

      await settings.load();
      expect(settings.lockOnBackground, SettingsProvider.defaultLockOnBackground);
    });

    test('setLockOnBackground toggles and persists preference in SharedPreferences', () async {
      final settings = SettingsProvider();
      await settings.load();

      final initial = settings.lockOnBackground;
      bool notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setLockOnBackground(!initial);
      expect(settings.lockOnBackground, !initial);
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLockOnBackground), !initial);

      // Reloading from SharedPreferences preserves the explicit choice
      final reloaded = SettingsProvider();
      await reloaded.load();
      expect(reloaded.lockOnBackground, !initial);
    });
  });

  group('AuthProvider - Android Navigation Auto-Lock Suppression & 500ms Grace Window', () {
    test('runWithoutAutoLockUntilResumed holds suppression after action returns', () async {
      final auth = AuthProvider();
      expect(auth.isAutoLockSuppressed, isFalse);

      bool actionExecuted = false;
      await auth.runWithoutAutoLockUntilResumed(() async {
        actionExecuted = true;
        expect(auth.isAutoLockSuppressed, isTrue);
      });

      expect(actionExecuted, isTrue);
      // Crucial: suppression is NOT immediately dropped when action finishes
      expect(auth.isAutoLockSuppressed, isTrue);

      // Calling notifyAppResumed starts the 500ms grace window
      auth.notifyAppResumed();
      expect(auth.isAutoLockSuppressed, isTrue);

      // After 500ms grace window, suppression is released
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(auth.isAutoLockSuppressed, isFalse);

      auth.dispose();
    });

    test('runWithoutAutoLockUntilResumed gracefully recovers if action throws', () async {
      final auth = AuthProvider();
      expect(auth.isAutoLockSuppressed, isFalse);

      try {
        await auth.runWithoutAutoLockUntilResumed(() async {
          throw Exception('Activity failed to start');
        });
      } catch (_) {}

      // notifyAppResumed is scheduled on error so it enters 500ms grace window
      expect(auth.isAutoLockSuppressed, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(auth.isAutoLockSuppressed, isFalse);

      auth.dispose();
    });

    test('endSuppressAutoLockUntilResumed immediate clears suppression immediately', () {
      final auth = AuthProvider();
      auth.beginSuppressAutoLockUntilResumed();
      expect(auth.isAutoLockSuppressed, isTrue);

      auth.endSuppressAutoLockUntilResumed(immediate: true);
      expect(auth.isAutoLockSuppressed, isFalse);

      auth.dispose();
    });
  });

  group('AuthProvider - Biometrics Silent Auto-Trigger & Error Handling', () {
    test('unlockWithBiometrics with isSilentAutoTrigger=true does not set errorMessage on cancellation', () async {
      final fakeBio = FakeBiometricService();
      fakeBio.keyToReturn = null; // simulates user cancelling biometric prompt

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      final result = await auth.unlockWithBiometrics(isSilentAutoTrigger: true);
      expect(result, isFalse);
      expect(fakeBio.retrieveCallCount, 1);
      expect(auth.errorMessage, isNull); // No error banner on screen!

      auth.dispose();
    });

    test('unlockWithBiometrics with isSilentAutoTrigger=false sets errorMessage on user tap cancellation', () async {
      final fakeBio = FakeBiometricService();
      fakeBio.keyToReturn = null;

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      final result = await auth.unlockWithBiometrics(isSilentAutoTrigger: false);
      expect(result, isFalse);
      expect(fakeBio.retrieveCallCount, 1);
      expect(auth.errorMessage, isNotNull);
      expect(auth.errorMessage, contains('Biyometrik doğrulama'));

      auth.dispose();
    });

    test('unlockWithBiometrics with isSilentAutoTrigger=true does not set errorMessage on hardware exception', () async {
      final fakeBio = FakeBiometricService();
      fakeBio.throwOnRetrieve = true;

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      final result = await auth.unlockWithBiometrics(isSilentAutoTrigger: true);
      expect(result, isFalse);
      expect(auth.errorMessage, isNull);

      auth.dispose();
    });
  });

  group('AuthScreen - Biometrics Auto-Trigger & Circular FAB Widget Tests', () {
    Widget buildTestApp({
      required AuthProvider auth,
      SettingsProvider? settings,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settings ?? (SettingsProvider()..load()),
          ),
          ChangeNotifierProvider<VaultProvider>(
            create: (_) => VaultProvider(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AuthScreen(),
        ),
      );
    }

    testWidgets('renders small circular biometric FAB at bottom-right and inline button when biometrics enabled', (tester) async {
      final fakeBio = FakeBiometricService();
      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      // Circular FloatingActionButton.small at bottom-right
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);

      final fab = tester.widget<FloatingActionButton>(fabFinder);
      expect(fab.mini, isTrue); // small FAB
      expect(fab.heroTag, 'biometric_quick_fab');
      expect(find.descendant(of: fabFinder, matching: find.byIcon(Icons.fingerprint)), findsOneWidget);

      // Inline OutlinedButton also rendered
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Unlock with Biometrics'), findsOneWidget);

      auth.dispose();
    });

    testWidgets('does not render circular biometric FAB when biometrics disabled', (tester) async {
      final fakeBio = FakeBiometricService();
      fakeBio.isEnabled = false;
      fakeBio.canCheck = false;

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(false);

      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Unlock with Biometrics'), findsNothing);

      auth.dispose();
    });

    testWidgets('tapping circular biometric FAB invokes unlockWithBiometrics', (tester) async {
      final fakeBio = FakeBiometricService();
      fakeBio.keyToReturn = null; // cancellation

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      final initialCallCount = fakeBio.retrieveCallCount;

      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);

      await tester.tap(fabFinder);
      await tester.pumpAndSettle();

      expect(fakeBio.retrieveCallCount, greaterThan(initialCallCount));

      auth.dispose();
    });

    testWidgets('auto-triggers biometric prompt on startup and silent cancellation leaves no error message', (tester) async {
      final fakeBio = FakeBiometricService();
      fakeBio.keyToReturn = null; // user cancels prompt

      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      await tester.pumpWidget(buildTestApp(auth: auth));
      // First frame schedules postFrameCallback
      await tester.pump();
      await tester.pumpAndSettle();

      // On mobile or macOS, startup auto-trigger called retrieveBiometricMasterKey
      final isMobileOrMac = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
      if (isMobileOrMac) {
        expect(fakeBio.retrieveCallCount, greaterThanOrEqualTo(1));
      }

      // No error message displayed on silent auto-trigger cancellation
      expect(auth.errorMessage, isNull);
      expect(find.text('Biometric authentication failed or cancelled.'), findsNothing);

      auth.dispose();
    });
  });

  group('Lifecycle & Auto-Lock Integration in MultiPadApp', () {
    testWidgets('AppLifecycleState.paused does NOT lock vault when lockOnBackground is false', (tester) async {
      final fakeBio = FakeBiometricService();
      final auth = AuthProvider(
        biometricService: fakeBio,
        securityLogService: FakeSecurityLogService(),
      );
      auth.setBiometricsEnabledForTesting(false);

      final settings = SettingsProvider();
      await settings.load();
      await settings.setAutoLockMinutes(0);
      await settings.setLockOnBackground(false);

      final masterKey = List<int>.generate(32, (i) => i);
      fakeBio.keyToReturn = masterKey;
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const MaterialApp(
            home: VaultLifecycleShell(
              child: Scaffold(body: Text('Test Vault Content')),
            ),
          ),
        ),
      );
      await tester.pump();

      final shellObserver = tester.state<VaultLifecycleShellState>(
        find.byType(VaultLifecycleShell),
      );

      // Simulate app minimizing / hiding (AppLifecycleState.hidden)
      shellObserver.didChangeAppLifecycleState(AppLifecycleState.hidden);
      // Vault MUST stay unlocked because lockOnBackground is false!
      expect(auth.isUnlocked, isTrue);

      // Simulate app paused
      shellObserver.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(auth.isUnlocked, isTrue);

      shellObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      TotpTickerService.instance.pause();
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    });

    testWidgets('AppLifecycleState.paused does NOT lock vault when auto-lock is suppressed (e.g. Android navigation)', (tester) async {
      final fakeBio = FakeBiometricService();
      final auth = AuthProvider(
        biometricService: fakeBio,
        securityLogService: FakeSecurityLogService(),
      );
      final settings = SettingsProvider();
      await settings.load();
      await settings.setAutoLockMinutes(0);
      await settings.setLockOnBackground(true);

      final masterKey = List<int>.generate(32, (i) => i);
      fakeBio.keyToReturn = masterKey;
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const MaterialApp(
            home: VaultLifecycleShell(
              child: Scaffold(body: Text('Test Vault Content')),
            ),
          ),
        ),
      );
      await tester.pump();

      final shellObserver = tester.state<VaultLifecycleShellState>(
        find.byType(VaultLifecycleShell),
      );

      // Simulate starting external activity (e.g. Android autofill settings or file picker)
      await auth.runWithoutAutoLockUntilResumed(
        () async {},
        fallbackTimeout: const Duration(milliseconds: 100),
      );
      expect(auth.isAutoLockSuppressed, isTrue);

      // Android transitions app to paused
      shellObserver.didChangeAppLifecycleState(AppLifecycleState.paused);
      // Vault MUST stay unlocked due to suppression!
      expect(auth.isUnlocked, isTrue);

      // User returns from Android settings: app resumes
      shellObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      TotpTickerService.instance.pause();
      await tester.pump();

      // In 500ms grace window, suppression is still active
      expect(auth.isAutoLockSuppressed, isTrue);
      expect(auth.isUnlocked, isTrue);

      // After grace window, suppression is released
      await tester.pump(const Duration(milliseconds: 550));
      expect(auth.isAutoLockSuppressed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    });

    testWidgets('AppLifecycleState.paused locks vault when lockOnBackground is true and not suppressed', (tester) async {
      final fakeBio = FakeBiometricService();
      final auth = AuthProvider(
        biometricService: fakeBio,
        securityLogService: FakeSecurityLogService(),
      );
      final settings = SettingsProvider();
      await settings.load();
      await settings.setAutoLockMinutes(0);
      await settings.setLockOnBackground(true);

      final masterKey = List<int>.generate(32, (i) => i);
      fakeBio.keyToReturn = masterKey;
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ],
          child: const MaterialApp(
            home: VaultLifecycleShell(
              child: Scaffold(body: Text('Test Vault Content')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(auth.isAutoLockSuppressed, isFalse);

      final shellObserver = tester.state<VaultLifecycleShellState>(
        find.byType(VaultLifecycleShell),
      );

      // App is paused / hidden while lockOnBackground is true
      shellObserver.didChangeAppLifecycleState(AppLifecycleState.paused);
      // Vault locks!
      expect(auth.isUnlocked, isFalse);

      shellObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
      TotpTickerService.instance.pause();
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    });
  });
}
