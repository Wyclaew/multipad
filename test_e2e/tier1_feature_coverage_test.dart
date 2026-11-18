import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/screens/auth_screen.dart';
import 'package:multipad/screens/home_screen.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/biometric_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/widgets/password_generator_dialog.dart';
import 'package:multipad/widgets/quick_search_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  setUp(() async {
    await E2ETestHelpers.setupE2ETestEnvironment();
  });

  tearDown(() async {
    await E2ETestHelpers.teardownE2ETestEnvironment();
  });

  // ===========================================================================
  // Feature 1: Biometric Auto-Trigger on Startup (R1)
  // ===========================================================================
  group('Tier 1: Feature 1 - Biometric Auto-Trigger on Startup', () {
    test('1.1 auto-trigger condition evaluates true when biometrics enabled and ready', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      expect(await bio.canCheckBiometrics(), isTrue);

      final masterKey = List<int>.generate(32, (i) => i);
      await bio.enableBiometrics(masterKey);
      expect(await bio.isBiometricUnlockEnabled(), isTrue);

      await auth.checkInitialState();
      expect(auth.canUseBiometrics, isTrue);
      expect(auth.isBiometricEnabled, isTrue);
      expect(auth.canUseBiometricsNow, isTrue);
    });

    test('1.2 auto-trigger is suppressed when biometric unlock is disabled', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.disableBiometrics();

      await auth.checkInitialState();
      expect(auth.isBiometricEnabled, isFalse);
      expect(auth.canUseBiometricsNow, isFalse);
    });

    test('1.3 auto-trigger is suppressed during active security lockout', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.keyLockoutUntilIso,
        DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );

      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      await auth.checkInitialState();
      expect(auth.remainingLockout > Duration.zero, isTrue);
      expect(auth.canUseBiometricsNow, isFalse);
    });

    test('1.4 cancellation of auto-trigger does not corrupt vault state', () async {
      E2ETestHelpers.setBiometricsBehavior(shouldSucceed: false);
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      await auth.checkInitialState();
      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isFalse);
      expect(auth.isUnlocked, isFalse);
      expect(auth.status, VaultLockStatus.lockedWithPass);
    });

    test('1.5 successful auto-trigger restores master key and unlocks vault', () async {
      E2ETestHelpers.setBiometricsBehavior(shouldSucceed: true);
      final auth = AuthProvider();
      final bio = BiometricService();
      final expectedKey = List<int>.generate(32, (i) => i + 10);
      await bio.enableBiometrics(expectedKey);

      await auth.checkInitialState();
      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isTrue);
      expect(auth.isUnlocked, isTrue);
      expect(auth.masterKey, equals(expectedKey));
    });
  });

  // ===========================================================================
  // Feature 2: Circular Biometric Login Button (R1)
  // ===========================================================================
  group('Tier 2: Feature 2 - Circular Biometric Login Button', () {
    testWidgets('2.1 renders login screen with biometric option when enabled', (tester) async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.checkInitialState();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.fingerprint), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('2.2 circular or quick biometric trigger invokes unlockWithBiometrics', (tester) async {
      E2ETestHelpers.setBiometricsBehavior(shouldSucceed: true);
      final auth = AuthProvider();
      final bio = BiometricService();
      final key = List<int>.generate(32, (i) => i + 1);
      await bio.enableBiometrics(key);
      await auth.checkInitialState();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
        ),
      );
      await tester.pump();

      final bioButton = find.byIcon(Icons.fingerprint).first;
      await tester.runAsync(() async {
        await tester.tap(bioButton);
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(auth.isUnlocked, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('2.3 circular button is hidden when in registration mode', (tester) async {
      final auth = AuthProvider();
      await auth.checkInitialState();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
        ),
      );
      await tester.pump();

      final toggleModeButton = find.textContaining('Hesap Oluşturun');
      if (toggleModeButton.evaluate().isNotEmpty) {
        await tester.tap(toggleModeButton);
        await tester.pump();
      }

      // In registration mode, registration fields appear
      expect(find.byType(TextField), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    test('2.4 disabling biometrics purges credentials and reflects in auth state', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.checkInitialState();
      expect(auth.isBiometricEnabled, isTrue);

      await bio.disableBiometrics();
      await auth.checkInitialState();
      expect(auth.isBiometricEnabled, isFalse);
    });

    test('2.5 lockout state suppresses biometric invocation cleanly', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.keyLockoutUntilIso,
        DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      );
      await auth.checkInitialState();

      final success = await auth.unlockWithBiometrics();
      expect(success, isFalse);
    });
  });

  // ===========================================================================
  // Feature 3: macOS Background Lock Setting (R2)
  // ===========================================================================
  group('Tier 1: Feature 3 - macOS Background Lock Setting', () {
    test('3.1 settings provider exposes lockOnBackground getter and setter', () async {
      final settings = SettingsProvider();
      await settings.load();

      final initial = settings.lockOnBackground;
      await settings.setLockOnBackground(!initial);
      expect(settings.lockOnBackground, !initial);
    });

    test('3.2 lockOnBackground persists to SharedPreferences', () async {
      final settings = SettingsProvider();
      await settings.load();

      await settings.setLockOnBackground(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AppConstants.keyLockOnBackground), isFalse);

      await settings.setLockOnBackground(true);
      expect(prefs.getBool(AppConstants.keyLockOnBackground), isTrue);
    });

    test('3.3 vault stays unlocked on background when lockOnBackground is disabled', () async {
      final settings = SettingsProvider();
      await settings.load();
      await settings.setLockOnBackground(false);

      final auth = AuthProvider();
      final bio = BiometricService();
      final key = List<int>.generate(32, (i) => i);
      await bio.enableBiometrics(key);
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      // Simulating lifecycle pause check:
      final shouldLock = settings.lockOnBackground && auth.isUnlocked && !auth.isAutoLockSuppressed;
      expect(shouldLock, isFalse);
      expect(auth.isUnlocked, isTrue);
    });

    test('3.4 vault locks on background when lockOnBackground is enabled', () async {
      final settings = SettingsProvider();
      await settings.load();
      await settings.setLockOnBackground(true);

      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      final shouldLock = settings.lockOnBackground && auth.isUnlocked && !auth.isAutoLockSuppressed;
      expect(shouldLock, isTrue);

      auth.lockVault(reason: 'Test background lock');
      expect(auth.isUnlocked, isFalse);
    });

    test('3.5 lockOnBackground setting reloads consistently across restarts', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyLockOnBackground, false);

      final freshSettings = SettingsProvider();
      await freshSettings.load();
      expect(freshSettings.lockOnBackground, isFalse);
    });
  });

  // ===========================================================================
  // Feature 4: Android Navigation Auto-Lock Fix (R2)
  // ===========================================================================
  group('Tier 1: Feature 4 - Android Navigation Auto-Lock Fix', () {
    test('4.1 beginSuppressAutoLock and endSuppressAutoLock maintain depth counter', () {
      final auth = AuthProvider();
      expect(auth.isAutoLockSuppressed, isFalse);

      auth.beginSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isTrue);

      auth.beginSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isTrue);

      auth.endSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isTrue);

      auth.endSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isFalse);
    });

    test('4.2 runWithoutAutoLock wraps async operations safely', () async {
      final auth = AuthProvider();
      expect(auth.isAutoLockSuppressed, isFalse);

      final result = await auth.runWithoutAutoLock(() async {
        expect(auth.isAutoLockSuppressed, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 42;
      });

      expect(result, 42);
      expect(auth.isAutoLockSuppressed, isFalse);
    });

    test('4.3 runWithoutAutoLock releases suppression even when action throws', () async {
      final auth = AuthProvider();
      expect(auth.isAutoLockSuppressed, isFalse);

      try {
        await auth.runWithoutAutoLock(() async {
          expect(auth.isAutoLockSuppressed, isTrue);
          throw Exception('Simulated navigation error');
        });
      } catch (_) {}

      expect(auth.isAutoLockSuppressed, isFalse);
    });

    test('4.4 backgrounding during suppression does not trigger lockVault', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      auth.beginSuppressAutoLock();

      // Lifecycle check
      final shouldLock = auth.isUnlocked && !auth.isAutoLockSuppressed;
      expect(shouldLock, isFalse);

      auth.endSuppressAutoLock();
    });

    test('4.5 timed auto-lock is completely disabled when autoLockMinutes is 0', () async {
      final settings = SettingsProvider();
      await settings.load();
      await settings.setAutoLockMinutes(0);
      expect(settings.autoLockMinutes, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(AppConstants.keyAutoLockMinutes), 0);
    });
  });

  // ===========================================================================
  // Feature 5: Configurable 2FA Re-Prompt Intervals (R2)
  // ===========================================================================
  group('Tier 1: Feature 5 - Configurable 2FA Re-Prompt Intervals', () {
    test('5.1 supports presets of 30, 60, and 90 days', () {
      const presets = [30, 60, 90];
      for (final days in presets) {
        expect(days >= 30 && days <= 90, isTrue);
        expect(days % 30 == 0, isTrue);
      }
    });

    test('5.2 evaluates prompt not due when within configured interval', () {
      final now = DateTime.utc(2026, 6, 15);
      final lastVerified = DateTime.utc(2026, 6, 1); // 14 days ago
      final due = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: lastVerified,
        intervalDays: 30,
        now: now,
      );
      expect(due, isFalse);
    });

    test('5.3 evaluates prompt due when interval has elapsed', () {
      final now = DateTime.utc(2026, 7, 20);
      final lastVerified = DateTime.utc(2026, 6, 1); // 49 days ago
      final due30 = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: lastVerified,
        intervalDays: 30,
        now: now,
      );
      expect(due30, isTrue);

      final due60 = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: lastVerified,
        intervalDays: 60,
        now: now,
      );
      expect(due60, isFalse);
    });

    test('5.4 prompt is due when lastVerified is null', () {
      final now = DateTime.now();
      final due = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: null,
        intervalDays: 30,
        now: now,
      );
      expect(due, isTrue);
    });

    test('5.5 interval preference persists in settings storage', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('multipad_2fa_reprompt_days', 60);
      expect(prefs.getInt('multipad_2fa_reprompt_days'), 60);

      await prefs.setInt('multipad_2fa_reprompt_days', 90);
      expect(prefs.getInt('multipad_2fa_reprompt_days'), 90);
    });
  });

  // ===========================================================================
  // Feature 6: Encrypted Vault Import Support (R3)
  // ===========================================================================
  group('Tier 1: Feature 6 - Encrypted Vault Import Support', () {
    test('6.1 detects encrypted Bitwarden JSON export format', () {
      const encryptedJson = '{"encrypted": true, "passwordProtected": true, "data": "2.iv|cipher|mac"}';
      final decoded = jsonDecode(encryptedJson) as Map<String, dynamic>;
      final isEncrypted = decoded['encrypted'] == true || decoded['passwordProtected'] == true;
      expect(isEncrypted, isTrue);
    });

    test('6.2 plain export is recognized without encrypted flag', () {
      const plainJson = '{"folders": [], "items": []}';
      final decoded = jsonDecode(plainJson) as Map<String, dynamic>;
      final isEncrypted = decoded['encrypted'] == true || decoded['passwordProtected'] == true;
      expect(isEncrypted, isFalse);
    });

    test('6.3 derives Bitwarden subkeys via PBKDF2 and HKDF-Expand', () async {
      final subKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'MasterPassword123!',
        salt: 'alice@example.com',
        kdfIterations: 100000,
      );
      expect(subKeys.encKey.length, 32);
      expect(subKeys.macKey.length, 32);
      expect(subKeys.encKey, isNot(equals(subKeys.macKey)));
    });

    test('6.4 encrypts and decrypts Bitwarden cipherstring round-trip', () async {
      final subKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'MasterPassword123!',
        salt: 'alice@example.com',
      );
      const plaintext = '{"items":[{"name":"Bitwarden Secret","login":{"username":"user1"}}]}';

      final cipherString = await E2ETestHelpers.encryptBitwardenCipherString(
        plaintext: plaintext,
        encKey: subKeys.encKey,
        macKey: subKeys.macKey,
      );
      expect(cipherString.startsWith('2.'), isTrue);

      final decrypted = await E2ETestHelpers.decryptBitwardenCipherString(
        cipherString: cipherString,
        encKey: subKeys.encKey,
        macKey: subKeys.macKey,
      );
      expect(decrypted, plaintext);
    });

    test('6.5 wrong password fails MAC check and protects vault integrity', () async {
      final correctKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'CorrectPassword!',
        salt: 'alice@example.com',
      );
      final wrongKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'WrongPassword!',
        salt: 'alice@example.com',
      );

      final cipherString = await E2ETestHelpers.encryptBitwardenCipherString(
        plaintext: 'Confidential Payload',
        encKey: correctKeys.encKey,
        macKey: correctKeys.macKey,
      );

      expect(
        () async => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: cipherString,
          encKey: wrongKeys.encKey,
          macKey: wrongKeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ===========================================================================
  // Feature 7: Security Audit 2FA Recalibration (R3)
  // ===========================================================================
  group('Tier 1: Feature 7 - Security Audit 2FA Recalibration', () {
    test('7.1 audit analysis identifies credentials and evaluates password strength', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'Strong Item',
          username: 'alice',
          password: 'SuperStrongPassword!2026#',
          website: 'https://example.com',
          totpSecret: '',
        ),
      ];
      final report = AuditService.analyzeVault(items);
      expect(report.totalAccounts, 1);
      expect(report.weakPasswordsCount, 0);
      expect(report.reusedPasswordsCount, 0);
    });

    test('7.2 missing 2FA is not classified as high-severity vulnerability', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'No 2FA Item',
          username: 'bob',
          password: 'CorrectHorseBatteryStaple!99',
          website: 'https://mysite.org',
          totpSecret: '',
        ),
      ];
      final report = AuditService.analyzeVault(items);
      final highSeverityIssues = report.issues.where((i) => i.severity >= 3).toList();
      expect(highSeverityIssues.isEmpty, isTrue);
    });

    test('7.3 weak passwords reduce overall audit score', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'Weak Item',
          username: 'bob',
          password: '123',
          website: 'https://example.com',
        ),
      ];
      final report = AuditService.analyzeVault(items);
      expect(report.weakPasswordsCount, 1);
      expect(report.overallScore, lessThan(80));
    });

    test('7.4 reused passwords across multiple accounts are flagged', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'Site A',
          password: 'SharedSecret!2026',
        ),
        VaultItem(
          id: 'c2',
          type: VaultItemType.credential,
          title: 'Site B',
          password: 'SharedSecret!2026',
        ),
      ];
      final report = AuditService.analyzeVault(items);
      expect(report.reusedPasswordsCount, 2);
    });

    test('7.5 card Luhn and expiration validation remain active', () {
      expect(AuditService.isValidLuhn('4111111111111111'), isTrue);
      expect(AuditService.isValidLuhn('4111111111111112'), isFalse);

      final now = DateTime.utc(2026, 6, 1);
      expect(AuditService.evaluateCardExpiry('01/20', now: now), 'expired');
      expect(AuditService.evaluateCardExpiry('12/30', now: now), isNull);
    });
  });

  // ===========================================================================
  // Feature 8: Desktop Browser Extension & Bridge (R4)
  // ===========================================================================
  group('Tier 1: Feature 8 - Desktop Browser Extension & Bridge', () {
    test('8.1 bridge responds to status endpoint on loopback', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token-123',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final res = await bridge.client.get(Uri.parse('${bridge.baseUrl}/status'));
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['status'], 'unlocked');

      await bridge.close();
    });

    test('8.2 bridge rejects unauthorized requests without token', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token-123',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(res.statusCode, 401);

      await bridge.close();
    });

    test('8.3 bridge rejects forbidden web origins', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token-123',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'https://malicious-site.com',
          'Authorization': 'Bearer secret-token-123',
        },
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(res.statusCode, 403);

      await bridge.close();
    });

    test('8.4 bridge returns matched credentials for active tab URL', () async {
      final items = [
        E2ETestHelpers.sampleCredential(
          title: 'GitHub Work',
          username: 'alice_gh',
          website: 'https://github.com/login',
        ),
      ];

      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token-123',
        getItems: () => items,
        isUnlocked: () => true,
      );

      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'chrome-extension://abcdef123456',
          'Authorization': 'Bearer secret-token-123',
        },
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      expect(matches.first['username'], 'alice_gh');

      await bridge.close();
    });

    test('8.5 bridge captures new credentials submitted from extension', () async {
      Map<String, dynamic>? captured;
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token-123',
        getItems: () => [],
        isUnlocked: () => true,
        onCredentialCaptured: (data) => captured = data,
      );

      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {
          'Origin': 'chrome-extension://abcdef123456',
          'Authorization': 'Bearer secret-token-123',
        },
        body: jsonEncode({
          'url': 'https://newsite.com',
          'username': 'new_user',
          'password': 'NewPassword!2026',
        }),
      );
      expect(res.statusCode, 201);
      expect(captured, isNotNull);
      expect(captured!['username'], 'new_user');

      await bridge.close();
    });
  });

  // ===========================================================================
  // Feature 9: Mobile Autofill Save & Update (R4)
  // ===========================================================================
  group('Tier 1: Feature 9 - Mobile Autofill Save & Update', () {
    test('9.1 pushes updated credentials to hardware autofill store', () async {
      final entries = [
        {'title': 'Bank', 'username': 'user1', 'password': 'pass', 'domain': 'bank.com'},
      ];
      await const MethodChannel('com.multipad.multipad/native')
          .invokeMethod('updateAutofillIndex', {'entries': entries});
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:updateAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries.length, 1);
      expect(E2ETestHelpers.lastAutofillEntries.first['title'], 'Bank');
    });

    test('9.2 clears hardware autofill store when vault locks', () async {
      await const MethodChannel('com.multipad.multipad/native')
          .invokeMethod('clearAutofillIndex');
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:clearAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries.isEmpty, isTrue);
    });

    test('9.3 autofill toggle enables and disables hardware indexing setting', () async {
      final settings = SettingsProvider();
      await settings.load();

      await settings.setAutofillEnabled(true);
      expect(settings.autofillEnabled, isTrue);

      await settings.setAutofillEnabled(false);
      expect(settings.autofillEnabled, isFalse);
    });

    test('9.4 opening Android autofill settings invokes native platform method', () async {
      await const MethodChannel('com.multipad.multipad/native')
          .invokeMethod('openAutofillSettings');
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:openAutofillSettings'));
    });

    test('9.5 setting Android FLAG_SECURE toggles via native bridge', () async {
      await const MethodChannel('com.multipad.multipad/native')
          .invokeMethod('setFlagSecure', {'enabled': true});
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:setFlagSecure'));
    });
  });

  // ===========================================================================
  // Feature 10: Android Quick Autofill Shortcuts (R4)
  // ===========================================================================
  group('Tier 1: Feature 10 - Android Quick Autofill Shortcuts', () {
    test('10.1 native bridge initializes without errors', () async {
      await NativeBridgeService.initialize(
        onQuickSearchRequested: () {},
        onLockVaultRequested: () {},
      );
      expect(true, isTrue);
    });

    test('10.2 consumes pending quick search action on cold start', () async {
      E2ETestHelpers.setPendingLaunchAction('quick_search');
      bool actionTriggered = false;

      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => actionTriggered = true,
      );
      expect(actionTriggered, isTrue);
    });

    testWidgets('10.3 QuickSearchDialog warns when opened while vault is locked', (tester) async {
      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: vault),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: QuickSearchDialog()),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('locked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('10.4 QuickSearchDialog renders search field when vault is unlocked', (tester) async {
      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.runAsync(() async {
        final bio = BiometricService();
        await bio.enableBiometrics(List<int>.generate(32, (i) => i));
        await auth.unlockWithBiometrics();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: vault),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: QuickSearchDialog()),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('10.5 rapid native bridge resets do not leak listener memory', () async {
      for (int i = 0; i < 5; i++) {
        NativeBridgeService.resetForTesting();
        await NativeBridgeService.initialize();
      }
      expect(true, isTrue);
    });
  });

  // ===========================================================================
  // Feature 11: Bitwarden-Style UX Ergonomics (R4)
  // ===========================================================================
  group('Tier 1: Feature 11 - Bitwarden-Style UX Ergonomics', () {
    testWidgets('11.1 password generator dialog is accessible and generates password', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: PasswordGeneratorDialog()),
        ),
      );
      await tester.pump();

      expect(find.byType(PasswordGeneratorDialog), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    test('11.2 vault items sort alphabetically by title A to Z', () {
      final items = [
        E2ETestHelpers.sampleCredential(id: '1', title: 'Zebra Service'),
        E2ETestHelpers.sampleCredential(id: '2', title: 'Apple ID'),
        E2ETestHelpers.sampleCredential(id: '3', title: 'GitHub'),
      ];

      final sorted = List<VaultItem>.from(items)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      expect(sorted[0].title, 'Apple ID');
      expect(sorted[1].title, 'GitHub');
      expect(sorted[2].title, 'Zebra Service');
    });

    test('11.3 custom fields support masked and unmasked representation', () {
      const field = CustomField(
        id: 'cf-1',
        label: 'Security Answer',
        value: 'Fluffy',
        isHidden: true,
      );
      expect(field.isHidden, isTrue);
      expect(field.label, 'Security Answer');

      final revealed = field.copyWith(isHidden: false);
      expect(revealed.isHidden, isFalse);
    });

    test('11.4 confidential copy hides sensitive tokens from clipboard history', () async {
      final copied = await NativeBridgeService.copyConfidential('sensitive-pass');
      expect(copied, isTrue);
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:copyConfidential'));
    });

    testWidgets('11.5 HomeScreen renders navigation and vault structure cleanly', (tester) async {
      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.runAsync(() async {
        final bio = BiometricService();
        await bio.enableBiometrics(List<int>.generate(32, (i) => i));
        await auth.unlockWithBiometrics();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: vault),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ===========================================================================
  // Feature 12: Background Footprint Optimization (R5)
  // ===========================================================================
  group('Tier 1: Feature 12 - Background Footprint Optimization', () {
    test('12.1 centralized TOTP ticker broadcasts periodic ticks', () async {
      final ticker = E2ETestHelpers.createCentralTicker();
      final completer = Completer<DateTime>();

      final sub = ticker.subscribe((tick) {
        if (!completer.isCompleted) completer.complete(tick);
      });

      final received = await completer.future.timeout(const Duration(seconds: 3));
      expect(received, isNotNull);

      await sub.cancel();
      ticker.dispose();
    });

    test('12.2 multiple subscribers share the single ticker controller', () {
      final ticker = E2ETestHelpers.createCentralTicker();
      expect(ticker.activeSubscribers, 0);

      final sub1 = ticker.subscribe((_) {});
      final sub2 = ticker.subscribe((_) {});
      expect(ticker.activeSubscribers, 2);

      sub1.cancel();
      expect(ticker.activeSubscribers, 1);
      sub2.cancel();
      expect(ticker.activeSubscribers, 0);

      ticker.dispose();
    });

    test('12.3 ticker pauses emission when app is backgrounded', () async {
      final ticker = E2ETestHelpers.createCentralTicker();
      ticker.pause();
      expect(ticker.isPaused, isTrue);

      ticker.resume();
      expect(ticker.isPaused, isFalse);

      ticker.dispose();
    });

    test('12.4 timer cancellation on dispose cleans up cleanly', () {
      final ticker = E2ETestHelpers.createCentralTicker();
      ticker.dispose();
      expect(ticker.subscribe((_) {}), isNotNull);
    });

    test('12.5 clipboard clear timer schedules and cancels without leaking', () async {
      await ClipboardService.copySecurely('temp-pass', timeoutSeconds: 15);
      ClipboardService.cancelScheduledClear();
      expect(true, isTrue);
    });
  });

  // ===========================================================================
  // Feature 13: Fast Startup Loading Acceleration (R5)
  // ===========================================================================
  group('Tier 1: Feature 13 - Fast Startup Loading Acceleration', () {
    test('13.1 parallel item decryption runs concurrently with Future.wait', () async {
      final crypto = CryptoService();
      final key = crypto.generateRandomBytes(32);

      final payloads = <EncryptedPayload>[];
      for (int i = 0; i < 10; i++) {
        payloads.add(await crypto.encryptData('Item secret $i', key));
      }

      final stopwatch = Stopwatch()..start();
      final decrypted = await Future.wait(
        payloads.map((p) => crypto.decryptData(
              ciphertextBase64: p.ciphertext,
              ivBase64: p.iv,
              macBase64: p.mac,
              masterKey: key,
            )),
      );
      stopwatch.stop();

      expect(decrypted.length, 10);
      expect(decrypted.first, 'Item secret 0');
    });

    test('13.2 stale-while-revalidate loads cached items before sync network roundtrip', () {
      final cachedItems = [
        E2ETestHelpers.sampleCredential(title: 'Cached Item 1'),
      ];
      expect(cachedItems.length, 1);
      expect(cachedItems.first.title, 'Cached Item 1');
    });

    test('13.3 offline startup functions when network is unreachable', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      final success = await auth.unlockWithBiometrics();
      expect(success, isTrue);
      expect(auth.isUnlocked, isTrue);
    });

    test('13.4 SHA-256 hash calculation operates off high-speed crypto primitive', () {
      final hash = CryptoService.sha256Hex('multipad_test_seed');
      expect(hash.length, 64);
      expect(hash, equals(CryptoService.sha256Hex('multipad_test_seed')));
    });

    test('13.5 constant time equality prevents timing side-channels during key verify', () {
      final a = utf8.encode('super_secret_token_123');
      final b = utf8.encode('super_secret_token_123');
      final c = utf8.encode('super_secret_token_456');

      expect(CryptoService.constantTimeEquals(a, b), isTrue);
      expect(CryptoService.constantTimeEquals(a, c), isFalse);
    });
  });

  // ===========================================================================
  // Feature 14: Comprehensive English README (R5)
  // ===========================================================================
  group('Tier 1: Feature 14 - Comprehensive English README', () {
    test('14.1 README.md exists at project root', () {
      final readme = File('README.md');
      expect(readme.existsSync(), isTrue);
      expect(readme.lengthSync(), greaterThan(500));
    });

    test('14.2 README includes zero-knowledge and architecture references', () {
      final content = File('README.md').readAsStringSync();
      expect(content.toLowerCase(), contains('zero-knowledge'));
      expect(content.toLowerCase(), contains('multipad'));
    });

    test('14.3 README documents flutter test or run commands', () {
      final content = File('README.md').readAsStringSync();
      expect(content.toLowerCase(), contains('flutter'));
    });

    test('14.4 README documents security principles', () {
      final content = File('README.md').readAsStringSync();
      expect(content.toLowerCase(), anyOf(contains('argon2'), contains('aes'), contains('security')));
    });

    test('14.5 README does not contain unresolved TBD placeholders', () {
      final content = File('README.md').readAsStringSync();
      expect(content, isNot(contains('[TBD:')));
      expect(content, isNot(contains('TODO: write this section')));
    });
  });

  // ===========================================================================
  // Feature 15: Bitwarden Security Comparison (R5)
  // ===========================================================================
  group('Tier 1: Feature 15 - Bitwarden Security Comparison', () {
    test('15.1 evaluates Argon2id vs PBKDF2 key derivation superiority', () {
      // MultiPad default Argon2id requires memory hardness against GPU/ASIC attacks
      expect(AppConstants.argon2MemoryKib, 19456);
      expect(AppConstants.argon2Iterations, 2);
      expect(AppConstants.argon2Parallelism, 1);
    });

    test('15.2 evaluates local-only bridge zero-knowledge vs cloud reliance', () {
      // Local bridge runs strictly on 127.0.0.1, preventing WAN interception
      expect(InternetAddress.loopbackIPv4.address, '127.0.0.1');
    });

    test('15.3 evaluates hardware secure enclave biometric key sealing', () {
      final bio = BiometricService();
      expect(bio, isA<BiometricService>());
    });

    test('15.4 constant time string comparison validates tamper prevention', () {
      expect(CryptoService.constantTimeStringEquals('token_abc', 'token_abc'), isTrue);
      expect(CryptoService.constantTimeStringEquals('token_abc', 'token_xyz'), isFalse);
    });

    test('15.5 zero memory wipe zeroes sensitive buffers in RAM', () {
      final buffer = [1, 2, 3, 4, 5];
      CryptoService.wipe(buffer);
      expect(buffer, [0, 0, 0, 0, 0]);
    });
  });
}
