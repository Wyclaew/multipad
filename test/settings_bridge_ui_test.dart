import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/screens/settings_screen.dart';
import 'package:multipad/services/browser_bridge_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapSettingsScreen({
  required AuthProvider auth,
  required VaultProvider vault,
  required SettingsProvider settings,
  Locale locale = const Locale('tr'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<VaultProvider>.value(value: vault),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    BrowserBridgeService.instance = null;
  });

  group('SettingsScreen - Browser Bridge Pairing UI & Modern Cards', () {
    testWidgets('renders Browser Bridge card with port 48292 and formatted 6-digit PIN', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialPairingCode: '849201',
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      // Check bridge status & port (exact match on subtitle)
      expect(find.text('127.0.0.1:48292'), findsOneWidget);
      expect(find.text('Durduruldu'), findsOneWidget);

      // Check formatted PIN (8 4 9 2 0 1)
      expect(find.byKey(const ValueKey('bridge_pairing_pin_text')), findsOneWidget);
      expect(find.text('8 4 9 2 0 1'), findsOneWidget);

      // Check action buttons
      expect(find.byKey(const ValueKey('btn_copy_pairing_pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_regenerate_pairing_pin')), findsOneWidget);
    });

    testWidgets('Copy PIN button copies pairing code to clipboard with tactile feedback', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialPairingCode: '654321',
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();
      await settings.setClipboardTimeoutSeconds(10);

      String? clipboardText;
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'copyConfidential') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          clipboardText = args?['text'] as String?;
          return false;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          clipboardText = args?['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        ClipboardService.cancelScheduledClear();
        messenger.setMockMethodCallHandler(nativeChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      // Tap copy PIN
      await tester.tap(find.byKey(const ValueKey('btn_copy_pairing_pin')));
      await tester.pumpAndSettle();

      expect(clipboardText, '654321');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('PIN'), findsWidgets);

      // Advance time so _copyTimer (2s) fires cleanly and cancel scheduled clipboard clear
      await tester.pump(const Duration(seconds: 3));
      ClipboardService.cancelScheduledClear();
    });

    testWidgets('Regenerate PIN button rotates code and updates display immediately', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialPairingCode: '111111',
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 1 1 1 1 1'), findsOneWidget);

      // Tap regenerate button
      await tester.tap(find.byKey(const ValueKey('btn_regenerate_pairing_pin')));
      await tester.pumpAndSettle();

      // Ensure new PIN is generated
      expect(bridge.pairingCode, isNot('111111'));
      expect(find.text('1 1 1 1 1 1'), findsNothing);
      expect(find.text(bridge.pairingCode.split('').join(' ')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('renders extension pairing instructions for Chrome, Edge, and Firefox', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Chrome, Edge veya Firefox'), findsOneWidget);
      expect(find.textContaining('127.0.0.1:48292'), findsWidgets);
    });

    testWidgets('renders settings inside modern grouped cards with category headers', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      // Check card presence
      expect(find.byType(Card), findsAtLeast(4));

      // Check section headers
      expect(find.text('Güvenlik ve Gizlilik'.toUpperCase()), findsOneWidget);
      expect(find.text('Görünüm ve Dil'.toUpperCase()), findsOneWidget);
      expect(find.text('Veri Yönetimi ve Güncellemeler'.toUpperCase()), findsOneWidget);
    });
  });
}
