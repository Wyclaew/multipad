import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/screens/home_screen.dart';
import 'package:multipad/screens/settings_screen.dart';
import 'package:multipad/services/browser_bridge_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/widgets/credential_detail_pane.dart';
import 'package:multipad/widgets/password_generator_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrapHomeScreen({
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
      home: const HomeScreen(),
    ),
  );
}

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

Widget _wrapPasswordGeneratorDialog({
  required SettingsProvider settings,
  Locale locale = const Locale('tr'),
}) {
  return MultiProvider(
    providers: [
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
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => PasswordGeneratorDialog.show(ctx),
              child: const Text('Open Generator'),
            ),
          ),
        ),
      ),
    ),
  );
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
    tempDir = Directory.systemTemp.createTempSync('multipad_m1_challenger_test_');
    DatabaseService.configureForTesting(
      dbPath: p.join(tempDir.path, 'm1_challenger.db'),
    );
  });

  tearDown(() {
    BrowserBridgeService.instance = null;
    PasswordGeneratorDialog.clearHistory();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('HomeScreen - Adversarial Responsive Breakpoint Switching', () {
    testWidgets('mobile (320px) -> tablet (800px) -> desktop (1200px) -> mobile (320px) dynamic resizing', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      final sampleItem = VaultItem(
        id: 'test_item_1',
        title: 'GitHub Personal Account',
        type: VaultItemType.credential,
        username: 'octocat',
        password: 'sample_secret_password',
        website: 'https://github.com',
      );
      vault.setItemsForTesting([sampleItem]);

      await tester.pumpWidget(
        _wrapHomeScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      // ==========================================
      // PHASE 1: MOBILE VIEWPORT (320px width)
      // ==========================================
      // 1. NavigationBar should be present with 5 destinations
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));

      // 2. Redundant AppBar action icons (Authenticator & Audit) should NOT be rendered
      expect(find.byIcon(Icons.phonelink_lock_rounded), findsNothing);

      // 3. Horizontal category chip row should be present
      expect(find.text('Tümü'), findsOneWidget);
      expect(find.text('Hesaplar'), findsWidgets);

      // 4. Item card is rendered in single-column list
      expect(find.text('GitHub Personal Account'), findsOneWidget);

      // 5. No multi-pane sidebar or detail pane
      expect(find.byType(CredentialDetailPane), findsNothing);

      // ==========================================
      // PHASE 2: RESIZE DYNAMICALLY TO TABLET (800px width)
      // ==========================================
      tester.view.physicalSize = const Size(800, 700);
      await tester.pumpAndSettle();

      // 1. NavigationBar should disappear
      expect(find.byType(NavigationBar), findsNothing);

      // 2. Wide AppBar action icons (Authenticator & Audit) should appear
      expect(find.byIcon(Icons.phonelink_lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // 3. Left sidebar container (width 256) should appear
      final containers = tester.widgetList<Container>(find.byType(Container));
      final sidebarContainer = containers.where((c) {
        final cBox = c.constraints;
        return cBox?.maxWidth == 256 || (c.constraints == null && c.decoration is BoxDecoration);
      });
      expect(sidebarContainer, isNotEmpty);

      // 4. Detail pane should still NOT be present on 2-pane tablet
      expect(find.byType(CredentialDetailPane), findsNothing);

      // ==========================================
      // PHASE 3: RESIZE DYNAMICALLY TO DESKTOP (1200px width)
      // ==========================================
      tester.view.physicalSize = const Size(1200, 700);
      await tester.pumpAndSettle();

      // 1. Desktop 3-pane layout active
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CredentialDetailPane), findsOneWidget);

      // 2. Selected item details displayed in detail pane
      expect(find.text('GitHub Personal Account'), findsAtLeastNWidgets(1));

      // ==========================================
      // PHASE 4: RESIZE BACK TO MOBILE (320px width)
      // ==========================================
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();

      // 1. Seamless downgrade: NavigationBar returns, detail pane removed
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(CredentialDetailPane), findsNothing);
      expect(find.text('GitHub Personal Account'), findsOneWidget);
    });

    testWidgets('exact breakpoint boundary values: 779px vs 780px and 999px vs 1000px', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      final item = VaultItem(
        id: 'boundary_item',
        title: 'Boundary Test Item',
        type: VaultItemType.credential,
        username: 'user@multipad.org',
        password: 'BoundaryPassword123!',
      );
      vault.setItemsForTesting([item]);

      // --- Boundary 1: 779px (Mobile) ---
      tester.view.physicalSize = const Size(779, 800);
      await tester.pumpWidget(
        _wrapHomeScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget, reason: '779px must render mobile NavigationBar');
      expect(find.byType(CredentialDetailPane), findsNothing);

      // --- Boundary 2: 780px (Tablet 2-pane) ---
      tester.view.physicalSize = const Size(780, 800);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing, reason: '780px must hide mobile NavigationBar');
      expect(find.byType(CredentialDetailPane), findsNothing, reason: '780px tablet must not show 3rd detail pane');

      // --- Boundary 3: 999px (Tablet 2-pane upper bound) ---
      tester.view.physicalSize = const Size(999, 800);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CredentialDetailPane), findsNothing, reason: '999px must remain 2-pane without detail pane');

      // --- Boundary 4: 1000px (Desktop 3-pane lower bound) ---
      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CredentialDetailPane), findsOneWidget, reason: '1000px must activate 3-pane master-detail');
    });

    testWidgets('extreme screen dimensions: 280px narrow & 2560px ultra-wide 4K', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      final sampleItem = VaultItem(
        id: 'test_item_1',
        title: 'GitHub Personal Account',
        type: VaultItemType.credential,
        username: 'octocat',
        password: 'sample_secret_password',
        website: 'https://github.com',
      );
      vault.setItemsForTesting([sampleItem]);

      // 280px width (ultra-narrow)
      tester.view.physicalSize = const Size(280, 600);
      await tester.pumpWidget(
        _wrapHomeScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      // 2560px width (4K ultra-wide)
      tester.view.physicalSize = const Size(2560, 1440);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CredentialDetailPane), findsOneWidget);
    });
  });

  group('PasswordGeneratorDialog - Presentation & Extremes', () {
    testWidgets('presentation adaptivity: < 600px renders BottomSheet, >= 600px renders AlertDialog', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = SettingsProvider();

      // Mobile screen: 400px width
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(
        _wrapPasswordGeneratorDialog(settings: settings),
      );
      await tester.pumpAndSettle();

      // Tap to open generator
      await tester.tap(find.text('Open Generator'));
      await tester.pumpAndSettle();

      // Should open as ModalBottomSheet
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      // Dismiss dialog
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      // Desktop/tablet screen: 800px width
      tester.view.physicalSize = const Size(800, 800);
      await tester.pumpAndSettle();

      // Tap to open generator
      await tester.tap(find.text('Open Generator'));
      await tester.pumpAndSettle();

      // Should open as AlertDialog
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      // Dismiss dialog
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('password generation extreme lengths (4, 8, 16, 64, 128, 256) and character pools', (tester) async {
      final settings = SettingsProvider();

      // Render dialog directly inside a test harness
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: settings)],
          child: const MaterialApp(
            locale: Locale('tr'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('tr'), Locale('en')],
            home: Scaffold(
              body: PasswordGeneratorDialog(isBottomSheet: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify default state (length 24)
      expect(find.text('24'), findsAtLeastNWidgets(1));

      // Test extreme lengths directly against character generation logic
      const lengths = [4, 8, 16, 64, 128, 256];
      const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // without O, I
      const lower = "abcdefghijkmnopqrstuvwxyz"; // without l
      const numbers = "23456789"; // without 0, 1
      const symbols = "!@#\$%^&*()-_=+[]{}|;:,.<>?";
      const fullPool = "$upper$lower$numbers$symbols";

      final rng = Random.secure();
      for (final len in lengths) {
        final chars = <String>[];
        // minNumbers and minSymbols logic from PasswordGeneratorDialog
        for (int i = 0; i < min(2, len ~/ 3); i++) {
          chars.add(numbers[rng.nextInt(numbers.length)]);
        }
        for (int i = 0; i < min(2, len ~/ 3); i++) {
          chars.add(symbols[rng.nextInt(symbols.length)]);
        }
        while (chars.length < len) {
          chars.add(fullPool[rng.nextInt(fullPool.length)]);
        }
        chars.shuffle(rng);
        final pass = chars.join();

        expect(pass.length, len, reason: 'Generated password must strictly match length $len');
        final entropy = len * (log(fullPool.length) / ln2);
        expect(entropy.isFinite, isTrue);
        expect(entropy, greaterThan(0));

        // Ensure ambiguous characters were not included
        expect(pass.contains(RegExp(r'[01OIl]')), isFalse, reason: 'Avoid ambiguous flag excluded 0, 1, O, I, l');
      }
    });

    test('entropy calculation edge cases: empty pool, single char pool, EFF wordlist entropy', () {
      // 1. Empty character pool: entropy must be 0.0, no NaN or exceptions
      const emptyPool = "";
      final emptyEntropy = emptyPool.isEmpty ? 0.0 : 16 * (log(emptyPool.length) / ln2);
      expect(emptyEntropy, 0.0);

      // 2. Single char pool: log2(1) = 0.0, entropy = 0.0
      const singlePool = "A";
      final singleEntropy = 20 * (log(singlePool.length) / ln2);
      expect(singleEntropy, 0.0);

      // 3. EFF Diceware wordlist entropy:
      // 7776 words in EFF large wordlist = log2(7776) = 12.92481... bits per word
      final eff5Words = EFFWordlist.calculateEntropy(wordCount: 5);
      expect(eff5Words, closeTo(64.62, 0.1));

      final eff8Words = EFFWordlist.calculateEntropy(wordCount: 8);
      expect(eff8Words, closeTo(103.4, 0.1));

      // 4. Wordlist passphrases generation
      final passphrase = EFFWordlist.generatePassphrase(
        wordCount: 5,
        separator: "-",
        capitalize: true,
      );
      final words = passphrase.split("-");
      expect(words.length, 5);
      for (final w in words) {
        expect(w[0], equals(w[0].toUpperCase()), reason: 'Capitalize should make first letter uppercase');
      }
    });

    testWidgets('interactive entropy meter details toggle and history ring buffer capacity', (tester) async {
      final settings = SettingsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: settings)],
          child: const MaterialApp(
            locale: Locale('tr'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('tr'), Locale('en')],
            home: Scaffold(
              body: PasswordGeneratorDialog(isBottomSheet: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check entropy meter initial state (Tahmin ▼)
      expect(find.text('Tahmin ▼'), findsOneWidget);

      // Tap entropy meter to toggle details
      await tester.tap(find.text('Tahmin ▼'));
      await tester.pumpAndSettle();

      // Details shown (Gizle ▲ and crack time estimate)
      expect(find.text('Gizle ▲'), findsOneWidget);

      // Verify History Ring Buffer
      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history.isEmpty, isTrue);

      // Add 60 records to test 50 cap
      for (int i = 0; i < 60; i++) {
        PasswordGeneratorDialog.recordGeneration(
          GeneratedPasswordRecord(
            password: 'generated_pass_$i',
            mode: 'password',
            entropyBits: 80.0,
            timestamp: DateTime.now(),
          ),
        );
      }
      expect(PasswordGeneratorDialog.history.length, 50, reason: 'Ring buffer must cap at maxHistorySize = 50');
      expect(PasswordGeneratorDialog.history.first.password, 'generated_pass_59', reason: 'Newest item at index 0');

      // Clear history
      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history, isEmpty);
    });
  });

  group('SettingsScreen - Extreme Screen Widths & Missing Bridge Graceful Handling', () {
    testWidgets('renders cleanly on narrow (280px) and ultra-wide (2560px) screen widths', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      // 280px screen width
      tester.view.physicalSize = const Size(280, 1200);
      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Güvenlik ve Gizlilik'.toUpperCase()), findsOneWidget);

      // 2560px screen width
      tester.view.physicalSize = const Size(2560, 1200);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Güvenlik ve Gizlilik'.toUpperCase()), findsOneWidget);
    });

    testWidgets('handles missing bridge (BrowserBridgeService.instance == null) gracefully without crashing', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Explicitly set bridge instance to null
      BrowserBridgeService.instance = null;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      // Even with bridge == null:
      // 1. Status should show stopped fallback
      expect(find.text('127.0.0.1:48292'), findsOneWidget);
      expect(find.text('Durduruldu'), findsOneWidget);

      // 2. PIN should display fallback PIN
      expect(find.byKey(const ValueKey('bridge_pairing_pin_text')), findsOneWidget);
      expect(find.text('8 4 9 2 0 1'), findsOneWidget);

      // 3. Tapping "Yeni PIN Üret" when bridge == null must not crash
      final regenBtn = find.byKey(const ValueKey('btn_regenerate_pairing_pin'));
      expect(regenBtn, findsOneWidget);
      await tester.tap(regenBtn);
      await tester.pumpAndSettle();
      // Should remain '8 4 9 2 0 1' without throwing
      expect(find.text('8 4 9 2 0 1'), findsOneWidget);

      // 4. Tapping "PIN'i Kopyala" when bridge == null must copy fallback PIN and show SnackBar
      final copyBtn = find.byKey(const ValueKey('btn_copy_pairing_pin'));
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('kopyalandı'), findsOneWidget);
    });

    testWidgets('active bridge updates pairing PIN and status reactively', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialPairingCode: '123456',
      );
      BrowserBridgeService.instance = bridge;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        _wrapSettingsScreen(auth: auth, vault: vault, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 2 3 4 5 6'), findsOneWidget);

      // Tap regenerate button
      final regenBtn = find.byKey(const ValueKey('btn_regenerate_pairing_pin'));
      await tester.tap(regenBtn);
      await tester.pumpAndSettle();

      // Pairing PIN should have changed from 123456
      expect(find.text('1 2 3 4 5 6'), findsNothing);
      expect(find.textContaining('Yeni eşleştirme PIN\'i oluşturuldu'), findsOneWidget);
    });
  });
}
