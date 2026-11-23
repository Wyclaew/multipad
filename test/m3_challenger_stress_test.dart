import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/offline_storage_service.dart';
import 'package:multipad/services/pending_capture_coordinator.dart';
import 'package:multipad/widgets/pending_capture_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MockAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _unlocked;
  _MockAuthProvider({required bool unlocked}) : _unlocked = unlocked;

  @override
  bool get isUnlocked => _unlocked;

  void setUnlocked(bool unlocked) {
    _unlocked = unlocked;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required Widget child,
  required VaultProvider vault,
  AuthProvider? auth,
  Size? mediaQuerySize,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VaultProvider>.value(value: vault),
      if (auth != null) ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('tr')],
      home: mediaQuerySize != null
          ? MediaQuery(
              data: MediaQueryData(size: mediaQuerySize),
              child: Scaffold(body: child),
            )
          : Scaffold(body: child),
    ),
  );
}

void main() {
  const MethodChannel nativeChannel = MethodChannel('com.multipad.multipad/native');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ClipboardService.setDefaultTimeoutSeconds(30);
    NativeBridgeService.resetForTesting();
    OfflineStorageService.resetLockForTesting();
    DatabaseService.configureForTesting(dbPath: inMemoryDatabasePath);
  });

  tearDown(() async {
    OfflineStorageService.resetLockForTesting();
    await DatabaseService.closeForTesting();
  });

  group('Group 1: VaultProvider Pending Capture & Matching Adversarial Tests', () {
    test('findMatchingCredential matches exact website and case-insensitive username', () {
      final vault = VaultProvider();
      final item = VaultItem(
        id: 'user-github',
        title: 'GitHub Enterprise',
        type: VaultItemType.credential,
        username: 'alice@company.com',
        website: 'https://github.com/login',
      );
      vault.setItemsForTesting([item]);

      final match = vault.findMatchingCredential(
        website: 'github.com',
        username: '  ALICE@COMPANY.COM  ',
      );
      expect(match, isNotNull);
      expect(match?.id, 'user-github');
    });

    test('findMatchingCredential matches subdomains and sister subdomains via eTLD+1', () {
      final vault = VaultProvider();
      final item = VaultItem(
        id: 'uber-cred',
        title: 'Uber Account',
        type: VaultItemType.credential,
        username: 'rider_99',
        website: 'https://riders.uber.com',
      );
      vault.setItemsForTesting([item]);

      // Subdomain matching
      final match1 = vault.findMatchingCredential(
        website: 'login.uber.com',
        username: 'rider_99',
      );
      expect(match1, isNotNull);
      expect(match1?.id, 'uber-cred');

      // Root domain matching
      final match2 = vault.findMatchingCredential(
        website: 'uber.com',
        username: 'rider_99',
      );
      expect(match2, isNotNull);
      expect(match2?.id, 'uber-cred');
    });

    test('findMatchingCredential matches multi-part ccTLDs (.co.uk, .com.tr)', () {
      final vault = VaultProvider();
      final ukItem = VaultItem(
        id: 'uk-service',
        title: 'UK Service',
        type: VaultItemType.credential,
        username: 'john@uk.org',
        website: 'https://secure.auth.service.co.uk/sign-in',
      );
      final trItem = VaultItem(
        id: 'tr-bank',
        title: 'Turkish Bank',
        type: VaultItemType.credential,
        username: 'customer123',
        website: 'https://sube.banka.com.tr',
      );
      vault.setItemsForTesting([ukItem, trItem]);

      final ukMatch = vault.findMatchingCredential(
        website: 'checkout.service.co.uk',
        username: 'john@uk.org',
      );
      expect(ukMatch, isNotNull);
      expect(ukMatch?.id, 'uk-service');

      final trMatch = vault.findMatchingCredential(
        website: 'banka.com.tr',
        username: 'customer123',
      );
      expect(trMatch, isNotNull);
      expect(trMatch?.id, 'tr-bank');
    });

    test('findMatchingCredential does NOT match distinct tenants on multi-tenant PSL domains', () {
      final vault = VaultProvider();
      final githubPagesItem = VaultItem(
        id: 'gh-pages',
        title: 'Alice Blog',
        type: VaultItemType.credential,
        username: 'admin',
        website: 'https://alice.github.io/admin',
      );
      final vercelItem = VaultItem(
        id: 'vercel-app',
        title: 'Team Alpha',
        type: VaultItemType.credential,
        username: 'admin',
        website: 'https://team-alpha.vercel.app',
      );
      vault.setItemsForTesting([githubPagesItem, vercelItem]);

      // bob.github.io must NOT match alice.github.io
      final ghMismatch = vault.findMatchingCredential(
        website: 'bob.github.io',
        username: 'admin',
      );
      expect(ghMismatch, isNull);

      // team-beta.vercel.app must NOT match team-alpha.vercel.app
      final vercelMismatch = vault.findMatchingCredential(
        website: 'team-beta.vercel.app',
        username: 'admin',
      );
      expect(vercelMismatch, isNull);
    });

    test('findMatchingCredential matches IP addresses with ports and query strings', () {
      final vault = VaultProvider();
      final routerItem = VaultItem(
        id: 'router-item',
        title: 'Local Gateway',
        type: VaultItemType.credential,
        username: 'admin',
        website: 'http://192.168.1.1:8080',
      );
      final ipv6Item = VaultItem(
        id: 'ipv6-item',
        title: 'IPv6 Server',
        type: VaultItemType.credential,
        username: 'root',
        website: 'http://[::1]:3000',
      );
      vault.setItemsForTesting([routerItem, ipv6Item]);

      final routerMatch = vault.findMatchingCredential(
        website: 'http://192.168.1.1:8080/dashboard?auth=true#main',
        username: 'admin',
      );
      expect(routerMatch, isNotNull);
      expect(routerMatch?.id, 'router-item');

      final ipv6Match = vault.findMatchingCredential(
        website: 'http://[::1]:3000/api',
        username: 'root',
      );
      expect(ipv6Match, isNotNull);
      expect(ipv6Match?.id, 'ipv6-item');
    });

    test('findMatchingCredential matches Android package names', () {
      final vault = VaultProvider();
      final spotifyItem = VaultItem(
        id: 'spotify-app',
        title: 'Spotify',
        type: VaultItemType.credential,
        username: 'music_lover',
        website: 'https://open.spotify.com',
        customFields: const [
          CustomField(id: 'f-pkg', label: 'Package', value: 'com.spotify.music', type: CustomFieldType.text),
        ],
      );
      final packageAsWebsiteItem = VaultItem(
        id: 'direct-pkg',
        title: 'Custom App',
        type: VaultItemType.credential,
        username: 'player1',
        website: 'com.mygame.app',
      );
      vault.setItemsForTesting([spotifyItem, packageAsWebsiteItem]);

      final spotifyMatch = vault.findMatchingCredential(
        website: '',
        username: 'music_lover',
        packageName: 'com.spotify.music',
      );
      expect(spotifyMatch, isNotNull);
      expect(spotifyMatch?.id, 'spotify-app');

      final directPkgMatch = vault.findMatchingCredential(
        website: '',
        username: 'player1',
        packageName: 'com.mygame.app',
      );
      expect(directPkgMatch, isNotNull);
      expect(directPkgMatch?.id, 'direct-pkg');
    });

    test('processPendingAutofillCapture creates new item and persists in SQLite storage', () async {
      final vault = VaultProvider();
      vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 7));
      await vault.loadVault();

      final captured = {
        'id': 'cap-new-1',
        'title': 'Stripe Dashboard',
        'website': 'https://dashboard.stripe.com',
        'username': 'merchant@stripe.com',
        'password': 'SuperStripeKey#2026',
        'packageName': 'com.stripe.android',
      };

      final created = await vault.processPendingAutofillCapture(
        captured: captured,
        updateExisting: false,
        customTitle: 'Stripe Merchant Account',
      );

      expect(created.title, 'Stripe Merchant Account');
      expect(created.username, 'merchant@stripe.com');
      expect(created.password, 'SuperStripeKey#2026');
      expect(created.website, 'https://dashboard.stripe.com');
      expect(created.passwordLastModified, isNotNull);
      expect(created.customFields.any((f) => f.label == 'Package' && f.value == 'com.stripe.android'), true);

      // Verify SQLite persistence in vault_items table via OfflineStorageService
      final rows = await OfflineStorageService.loadLocalItems();
      expect(rows.any((r) => r['id'] == created.id), true);
    });

    test('processPendingAutofillCapture title fallback hierarchy', () async {
      final vault = VaultProvider();
      vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 1));
      await vault.loadVault();

      // Case 1: Custom title provided
      final item1 = await vault.processPendingAutofillCapture(
        captured: {'title': 'CapTitle', 'website': 'web.com', 'username': 'u1', 'password': 'p1'},
        customTitle: 'CustomWins',
      );
      expect(item1.title, 'CustomWins');

      // Case 2: Custom title empty -> captured['title']
      final item2 = await vault.processPendingAutofillCapture(
        captured: {'title': 'CapTitle', 'website': 'web.com', 'username': 'u2', 'password': 'p2'},
        customTitle: '   ',
      );
      expect(item2.title, 'CapTitle');

      // Case 3: Custom title empty & captured['title'] empty -> captured['website']
      final item3 = await vault.processPendingAutofillCapture(
        captured: {'title': '', 'website': 'web.com', 'username': 'u3', 'password': 'p3'},
      );
      expect(item3.title, 'web.com');

      // Case 4: All empty -> 'New Login'
      final item4 = await vault.processPendingAutofillCapture(
        captured: {'title': '', 'website': '', 'username': 'u4', 'password': 'p4'},
      );
      expect(item4.title, 'New Login');
    });

    test('processPendingAutofillCapture password history max 10 revisions limit enforced strictly', () async {
      final vault = VaultProvider();
      vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 3));
      await vault.loadVault();

      // Initial item with 10 existing historical passwords
      final initialHistory = List.generate(10, (i) => 'HistoryPass_$i');
      final existingItem = VaultItem(
        id: 'history-stress-item',
        title: 'History Test Item',
        type: VaultItemType.credential,
        username: 'stress_user',
        password: 'CurrentPassword_0',
        website: 'historytest.com',
        passwordHistory: initialHistory,
      );
      vault.setItemsForTesting([existingItem]);

      // Perform 5 sequential updates
      var currentItem = existingItem;
      for (int i = 1; i <= 5; i++) {
        final captured = {
          'website': 'historytest.com',
          'username': 'stress_user',
          'password': 'CurrentPassword_$i',
        };

        currentItem = await vault.processPendingAutofillCapture(
          captured: captured,
          updateExisting: true,
          existingItem: currentItem,
        );

        // Verification after each update: history length must never exceed 10
        expect(currentItem.passwordHistory.length, 10);
        // The most recently discarded password must be at index 0
        expect(currentItem.passwordHistory[0], 'CurrentPassword_${i - 1}');
      }

      // After 5 updates, the 5 oldest items from initialHistory should have been purged
      expect(currentItem.passwordHistory, [
        'CurrentPassword_4',
        'CurrentPassword_3',
        'CurrentPassword_2',
        'CurrentPassword_1',
        'CurrentPassword_0',
        'HistoryPass_0',
        'HistoryPass_1',
        'HistoryPass_2',
        'HistoryPass_3',
        'HistoryPass_4',
      ]);
    });

    test('processPendingAutofillCapture does not modify history if password is unchanged or previously empty', () async {
      final vault = VaultProvider();
      vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 2));
      await vault.loadVault();

      // Case A: Identical password
      final itemA = VaultItem(
        id: 'item-a',
        title: 'Same Password',
        type: VaultItemType.credential,
        username: 'user_a',
        password: 'UnchangedPassword123',
        website: 'a.com',
        passwordHistory: ['Old_1'],
      );
      final updatedA = await vault.processPendingAutofillCapture(
        captured: {'website': 'a.com', 'username': 'user_a', 'password': 'UnchangedPassword123'},
        updateExisting: true,
        existingItem: itemA,
      );
      expect(updatedA.passwordHistory, ['Old_1']); // unchanged

      // Case B: Existing item had empty password
      final itemB = VaultItem(
        id: 'item-b',
        title: 'Empty Password',
        type: VaultItemType.credential,
        username: 'user_b',
        password: '',
        website: 'b.com',
        passwordHistory: [],
      );
      final updatedB = await vault.processPendingAutofillCapture(
        captured: {'website': 'b.com', 'username': 'user_b', 'password': 'InitialPassword123'},
        updateExisting: true,
        existingItem: itemB,
      );
      expect(updatedB.passwordHistory, isEmpty); // no empty string inserted
      expect(updatedB.password, 'InitialPassword123');
    });
  });

  group('Group 2: PendingCaptureDialog UI & Responsiveness Stress Tests', () {
    testWidgets('mobile width (<600dp) renders inside ModalBottomSheet with drag handle', (tester) async {
      final vault = VaultProvider();
      final captured = {
        'title': 'Mobile Service',
        'website': 'mobileservice.com',
        'username': 'mobile_user',
        'password': 'MobilePassword99',
      };

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          mediaQuerySize: const Size(390, 844),
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PendingCaptureDialog.show(ctx, captured: captured),
              child: const Text('Open Mobile'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Mobile'));
      await tester.pumpAndSettle();

      // BottomSheet should be present
      expect(find.byType(BottomSheet), findsOneWidget);
      // Dialog should NOT be present
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Save New Login'), findsOneWidget);
    });

    testWidgets('desktop width (>=600dp) renders inside Dialog with ConstrainedBox maxWidth 480', (tester) async {
      final vault = VaultProvider();
      final captured = {
        'title': 'Desktop Service',
        'website': 'desktopservice.com',
        'username': 'desktop_user',
        'password': 'DesktopPassword99',
      };

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          mediaQuerySize: const Size(1280, 800),
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PendingCaptureDialog.show(ctx, captured: captured),
              child: const Text('Open Desktop'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Desktop'));
      await tester.pumpAndSettle();

      // Dialog should be present
      expect(find.byType(Dialog), findsOneWidget);
      // BottomSheet should NOT be present
      expect(find.byType(BottomSheet), findsNothing);

      // Verify ConstrainedBox with maxWidth 480 exists inside Dialog
      expect(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 480,
        ),
        findsOneWidget,
      );
      expect(find.text('Save New Login'), findsOneWidget);
    });

    testWidgets('password masking toggles independently for previous and new passwords in Update mode', (tester) async {
      final vault = VaultProvider();
      final existing = VaultItem(
        id: 'toggle-item',
        title: 'Toggle App',
        type: VaultItemType.credential,
        username: 'toggle_user',
        password: 'OldSecretPass1',
        website: 'toggle.com',
      );
      final captured = {
        'title': 'Toggle App',
        'website': 'toggle.com',
        'username': 'toggle_user',
        'password': 'NewSecretPass2',
      };

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          child: PendingCaptureDialog(captured: captured, existingItem: existing),
        ),
      );
      await tester.pumpAndSettle();

      // Both passwords initially masked
      expect(find.text('OldSecretPass1'), findsNothing);
      expect(find.text('NewSecretPass2'), findsNothing);
      expect(find.text('••••••••'), findsNWidgets(2));

      // Toggle buttons (two visibility icons)
      final visibilityIcons = find.byIcon(Icons.visibility_outlined);
      expect(visibilityIcons, findsNWidgets(2));

      // Tap first visibility icon (Previous Password)
      await tester.tap(visibilityIcons.first);
      await tester.pumpAndSettle();

      // Previous password revealed, new password still masked
      expect(find.text('OldSecretPass1'), findsOneWidget);
      expect(find.text('NewSecretPass2'), findsNothing);

      // Tap second visibility icon (New Password)
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      // Both passwords now revealed
      expect(find.text('OldSecretPass1'), findsOneWidget);
      expect(find.text('NewSecretPass2'), findsOneWidget);
    });

    testWidgets('quick copy buttons copy username and password with clipboard confirmation', (tester) async {
      final vault = VaultProvider();
      final captured = {
        'title': 'Copy App',
        'website': 'copy.com',
        'username': 'copy_me_user',
        'password': 'copy_me_password',
      };

      String? mockClipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>?;
            mockClipboardContent = args?['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          child: PendingCaptureDialog(captured: captured),
        ),
      );
      await tester.pumpAndSettle();

      final copyButtons = find.byIcon(Icons.copy_rounded);
      expect(copyButtons, findsNWidgets(2));

      // Click copy username
      await tester.tap(copyButtons.first);
      await tester.pump();

      expect(mockClipboardContent, 'copy_me_user');
      expect(find.byType(SnackBar), findsOneWidget);

      // Dismiss snackbars
      ScaffoldMessenger.of(tester.element(find.byType(PendingCaptureDialog))).clearSnackBars();
      await tester.pump();

      // Click copy password
      await tester.tap(copyButtons.last);
      await tester.pump();

      expect(mockClipboardContent, 'copy_me_password');

      // Clear active snackbars
      ScaffoldMessenger.of(tester.element(find.byType(PendingCaptureDialog))).clearSnackBars();
      await tester.pumpAndSettle();
    });

    testWidgets('editing custom title saves item with edited title', (tester) async {
      final vault = VaultProvider();
      await tester.runAsync(() async {
        vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 1));
        await vault.loadVault();
      });
      vault.setItemsForTesting([]);

      final captured = {
        'title': 'Original Title',
        'website': 'customtitle.com',
        'username': 'title_user',
        'password': 'Password123!',
      };

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          mediaQuerySize: const Size(600, 900),
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PendingCaptureDialog.show(ctx, captured: captured),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear title and enter custom title
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'My Super Renamed Account');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final saveBtn = find.text('Save to Vault');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(saveBtn);
        await Future.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();

      final saved = vault.items.firstWhere((i) => i.username == 'title_user');
      expect(saved.title, 'My Super Renamed Account');
    });

    testWidgets('Save as New Item in Update Mode creates distinct item leaving existing intact', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final vault = VaultProvider();
      final originalItem = VaultItem(
        id: 'orig-item-id',
        title: 'Original Service',
        type: VaultItemType.credential,
        username: 'shared_user',
        password: 'OriginalPassword1',
        website: 'shared.com',
      );

      await tester.runAsync(() async {
        vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 1));
        await vault.loadVault();
        await vault.saveItem(originalItem);
      });

      final captured = {
        'title': 'Original Service',
        'website': 'shared.com',
        'username': 'shared_user',
        'password': 'SecondaryPassword2',
      };

      bool? dialogResult;

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                dialogResult = await PendingCaptureDialog.show(
                  ctx,
                  captured: captured,
                  existingItem: originalItem,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Ensure Save as New Item button is visible and tap
      final saveAsNewBtn = find.text('Save as New Item');
      await tester.ensureVisible(saveAsNewBtn);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(saveAsNewBtn);
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      expect(dialogResult, true);
      // Vault should now have two items
      expect(vault.items.length, 2);
      final orig = vault.items.firstWhere((i) => i.id == 'orig-item-id');
      expect(orig.password, 'OriginalPassword1'); // Unmodified!

      final newlyAdded = vault.items.firstWhere((i) => i.id != 'orig-item-id');
      expect(newlyAdded.password, 'SecondaryPassword2');
    });
  });

  group('Group 3: PendingCaptureCoordinator Concurrency & Lifecycle Stress Tests', () {
    testWidgets('multiple rapid concurrent calls execute cleanly without duplicate dialogs', (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      int getCalls = 0;
      int clearCalls = 0;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'getPendingAutofillCredentials') {
          getCalls++;
          return [
            {
              'website': 'concurrent.com',
              'username': 'user_c',
              'password': 'Pass_c',
            }
          ];
        }
        if (call.method == 'clearPendingAutofillCredentials') {
          clearCalls++;
          return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      final auth = _MockAuthProvider(unlocked: true);
      final vault = VaultProvider();
      vault.setItemsForTesting([]);

      late BuildContext testContext;
      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          auth: auth,
          child: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger 5 concurrent calls
      final f1 = PendingCaptureCoordinator.checkAndShow(testContext);
      final f2 = PendingCaptureCoordinator.checkAndShow(testContext);
      final f3 = PendingCaptureCoordinator.checkAndShow(testContext);
      final f4 = PendingCaptureCoordinator.checkAndShow(testContext);
      final f5 = PendingCaptureCoordinator.checkAndShow(testContext);

      await tester.pumpAndSettle();

      // Only 1 dialog should be visible on screen
      expect(find.byType(PendingCaptureDialog), findsOneWidget);
      expect(find.text('Ignore'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();

      await Future.wait([f1, f2, f3, f4, f5]);

      // Exactly 1 get call and 1 clear call
      expect(getCalls, 1);
      expect(clearCalls, 1);
    });

    testWidgets('locked vault suppresses prompt; subsequent unlock executes prompt and clears queue', (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      bool getCalled = false;
      bool clearCalled = false;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'getPendingAutofillCredentials') {
          getCalled = true;
          return [
            {
              'website': 'unlocked-prompt.com',
              'username': 'vault_user',
              'password': 'VaultPassword123',
            }
          ];
        }
        if (call.method == 'clearPendingAutofillCredentials') {
          clearCalled = true;
          return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      final auth = _MockAuthProvider(unlocked: false);
      final vault = VaultProvider();
      vault.setItemsForTesting([]);
      late BuildContext testCtx;

      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          auth: auth,
          child: Builder(
            builder: (ctx) {
              testCtx = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. When locked: checkAndShow must immediately abort
      await PendingCaptureCoordinator.checkAndShow(testCtx);
      await tester.pumpAndSettle();

      expect(getCalled, false);
      expect(clearCalled, false);
      expect(find.byType(PendingCaptureDialog), findsNothing);

      // 2. Unlock vault and re-trigger checkAndShow
      auth.setUnlocked(true);
      await tester.pumpAndSettle();

      final future = PendingCaptureCoordinator.checkAndShow(testCtx);
      await tester.pumpAndSettle();

      expect(find.byType(PendingCaptureDialog), findsOneWidget);
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();
      await future;

      expect(getCalled, true);
      expect(clearCalled, true);
    });

    testWidgets('coordinator immediately aborts when vault is loading', (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      bool getCalled = false;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'getPendingAutofillCredentials') {
          getCalled = true;
          return [
            {'website': 'loading.com', 'username': 'user', 'password': 'pass'}
          ];
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      final auth = _MockAuthProvider(unlocked: true);
      final vault = VaultProvider();
      // Start vault loading
      vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 1));
      // vault.isLoading is true now

      late BuildContext testCtx;
      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          auth: auth,
          child: Builder(
            builder: (ctx) {
              testCtx = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      await PendingCaptureCoordinator.checkAndShow(testCtx);
      await tester.pumpAndSettle();

      expect(getCalled, false);
      expect(find.byType(PendingCaptureDialog), findsNothing);
    });

    testWidgets('duplicate captures in queue: second capture skips prompt once first is saved', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'getPendingAutofillCredentials') {
          return [
            // Duplicate captures with identical credentials
            {
              'website': 'dedup.com',
              'username': 'dedup_user',
              'password': 'DedupPassword123',
            },
            {
              'website': 'dedup.com',
              'username': 'dedup_user',
              'password': 'DedupPassword123',
            },
          ];
        }
        if (call.method == 'clearPendingAutofillCredentials') {
          return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      final auth = _MockAuthProvider(unlocked: true);
      final vault = VaultProvider();
      await tester.runAsync(() async {
        vault.syncAuthState(isUnlocked: true, masterKey: List.filled(32, 1));
        await vault.loadVault();
      });
      vault.setItemsForTesting([]);

      late BuildContext testCtx;
      await tester.pumpWidget(
        _buildTestApp(
          vault: vault,
          auth: auth,
          child: Builder(
            builder: (ctx) {
              testCtx = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final future = PendingCaptureCoordinator.checkAndShow(testCtx);
      await tester.pumpAndSettle();

      expect(find.byType(PendingCaptureDialog), findsOneWidget);
      final saveBtn = find.text('Save to Vault');
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(saveBtn);
        await Future.delayed(const Duration(milliseconds: 250));
      });
      await tester.pumpAndSettle();

      // The second item has identical password to the newly saved item, so it skips!
      await future;

      expect(find.byType(PendingCaptureDialog), findsNothing);
      expect(vault.items.where((i) => i.website == 'dedup.com').length, 1);
    });
  });
}
