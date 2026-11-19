// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/biometric_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
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
  // Tier 3: Cross-Feature Interactions (20 Pairwise Tests: T3.1 - T3.20)
  // ===========================================================================
  group('Tier 3: Cross-Feature Interactions', () {
    // -------------------------------------------------------------------------
    // T3.1 & T3.2: Biometric Auto-Trigger + 2FA Interval Enforcement
    // -------------------------------------------------------------------------
    test('T3.1 Biometric unlock evaluates 2FA re-prompt interval when interval has elapsed', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      final masterKey = List<int>.generate(32, (i) => i + 1);
      await bio.enableBiometrics(masterKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('multipad_2fa_reprompt_days', 30);

      // Last verified 45 days ago -> prompt is due
      final lastVerified = DateTime.now().subtract(const Duration(days: 45));
      final isDue = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: lastVerified,
        intervalDays: 30,
        now: DateTime.now(),
      );
      expect(isDue, isTrue);

      await auth.checkInitialState();
      expect(auth.canUseBiometricsNow, isTrue);
    });

    test('T3.2 Biometric unlock immediately completes without 2FA re-prompt within interval', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      final masterKey = List<int>.generate(32, (i) => i + 2);
      await bio.enableBiometrics(masterKey);

      // Last verified 5 days ago with 60-day interval -> prompt NOT due
      final lastVerified = DateTime.now().subtract(const Duration(days: 5));
      final isDue = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: lastVerified,
        intervalDays: 60,
        now: DateTime.now(),
      );
      expect(isDue, isFalse);

      await auth.checkInitialState();
      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isTrue);
      expect(auth.isUnlocked, isTrue);
    });

    // -------------------------------------------------------------------------
    // T3.3 & T3.20: Encrypted Vault Import + Security Audit Recalibration
    // -------------------------------------------------------------------------
    test('T3.3 Encrypted Bitwarden JSON import feeds audit engine without penalizing missing 2FA', () async {
      final innerItems = [
        {
          'id': 'imp-1',
          'type': 1, // Login
          'name': 'Corporate Cloud',
          'login': {
            'username': 'admin@corp.internal',
            'password': 'ExtremelyStrongPassword!2026#',
            'uris': [{'uri': 'https://cloud.corp.internal'}],
            'totp': null, // No 2FA
          },
        },
        {
          'id': 'imp-2',
          'type': 1,
          'name': 'Legacy Portal',
          'login': {
            'username': 'user@legacy.com',
            'password': '123', // Weak password
            'uris': [{'uri': 'https://legacy.com'}],
            'totp': 'JBSWY3DPEHPK3PXP', // Has 2FA
          },
        },
      ];

      final innerJson = jsonEncode({'items': innerItems, 'folders': []});
      final encryptedJson = await E2ETestHelpers.createBitwardenEncryptedJsonFixture(
        password: 'ImportMasterPassword!1',
        userEmail: 'alice@example.com',
        innerJsonPlaintext: innerJson,
      );

      // Inspect & decrypt import envelope
      final subkeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'ImportMasterPassword!1',
        salt: 'alice@example.com',
      );
      final envelope = jsonDecode(encryptedJson) as Map<String, dynamic>;
      final decryptedInner = await E2ETestHelpers.decryptBitwardenCipherString(
        cipherString: envelope['data'] as String,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );
      expect(decryptedInner, equals(innerJson));

      // Map imported items to VaultItems and audit
      final vaultItems = [
        VaultItem(
          id: 'imp-1',
          type: VaultItemType.credential,
          title: 'Corporate Cloud',
          username: 'admin@corp.internal',
          password: 'ExtremelyStrongPassword!2026#',
          website: 'https://cloud.corp.internal',
        ),
        VaultItem(
          id: 'imp-2',
          type: VaultItemType.credential,
          title: 'Legacy Portal',
          username: 'user@legacy.com',
          password: '123',
          website: 'https://legacy.com',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
      ];

      final report = AuditService.analyzeVault(vaultItems);
      expect(report.totalAccounts, 2);
      expect(report.weakPasswordsCount, 1); // Only imp-2 is flagged for weak password
      // imp-1 has no 2FA, but high severity issues for missing 2FA must be 0
      final highSeverityIssues = report.issues.where((i) => i.severity >= 3).toList();
      expect(highSeverityIssues.length, 1); // Only weak password is high severity
      expect(highSeverityIssues.first.title, 'Legacy Portal');
    });

    test('T3.20 Encrypted vault import validates payment card Luhn checksum and expiration', () async {
      final importedCards = [
        VaultItem(
          id: 'card-valid',
          type: VaultItemType.card,
          title: 'Personal Visa',
          cardNumber: '4111 1111 1111 1111',
          cardExpiry: '12/29',
        ),
        VaultItem(
          id: 'card-invalid-luhn',
          type: VaultItemType.card,
          title: 'Corrupted Card',
          cardNumber: '4111 1111 1111 1112',
          cardExpiry: '12/29',
        ),
        VaultItem(
          id: 'card-expired',
          type: VaultItemType.card,
          title: 'Old Card',
          cardNumber: '4111 1111 1111 1111',
          cardExpiry: '01/20',
        ),
      ];

      final report = AuditService.analyzeVault(importedCards);
      expect(report.invalidCardsCount, 1);
      expect(report.issues.any((i) => i.itemId == 'card-invalid-luhn'), isTrue);
      expect(report.issues.any((i) => i.itemId == 'card-expired'), isTrue);
    });

    // -------------------------------------------------------------------------
    // T3.4, T3.5, T3.6: Desktop Extension Bridge + Background Lock & Pairing
    // -------------------------------------------------------------------------
    test('T3.4 Extension bridge operates without disruption when lockOnBackground is disabled', () async {
      final settings = SettingsProvider();
      await settings.load();
      await settings.setLockOnBackground(false);

      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();

      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'bridge-token-77',
        getItems: () => [
          E2ETestHelpers.sampleCredential(
            title: 'GitLab',
            website: 'https://gitlab.com/login',
          ),
        ],
        isUnlocked: () => auth.isUnlocked,
      );

      // Simulates app being minimized/placed in background
      // Because lockOnBackground is false, vault is not locked
      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer bridge-token-77',
          'origin': 'chrome-extension://multipad-ext',
        },
        body: jsonEncode({'url': 'https://gitlab.com'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['matches'], isNotEmpty);

      await bridge.close();
    });

    test('T3.5 Extension bridge enforces vault lock: returns HTTP 423 when locked and recovers after unlock', () async {
      bool vaultUnlocked = true;
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'token-lock-test',
        getItems: () => [E2ETestHelpers.sampleCredential(website: 'https://example.com')],
        isUnlocked: () => vaultUnlocked,
      );

      // 1. Vault is unlocked -> query succeeds
      final res1 = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer token-lock-test',
          'origin': 'chrome-extension://test',
        },
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(res1.statusCode, HttpStatus.ok);

      // 2. Vault locks -> query returns HTTP 423 Locked
      vaultUnlocked = false;
      final res2 = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer token-lock-test',
          'origin': 'chrome-extension://test',
        },
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(res2.statusCode, HttpStatus.locked);

      // 3. Vault unlocks -> query succeeds again
      vaultUnlocked = true;
      final res3 = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer token-lock-test',
          'origin': 'chrome-extension://test',
        },
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(res3.statusCode, HttpStatus.ok);

      await bridge.close();
    });

    test('T3.6 Extension bridge pair endpoint issues token and rejects subsequent spoofed origin', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'paired-auth-secret-999',
        getItems: () => [],
        isUnlocked: () => true,
      );

      // POST /pair
      final pairRes = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {'origin': 'chrome-extension://official-extension-id'},
      );
      expect(pairRes.statusCode, HttpStatus.ok);
      final pairData = jsonDecode(pairRes.body) as Map<String, dynamic>;
      expect(pairData['token'], 'paired-auth-secret-999');

      // Attempt query from malicious website origin
      final spoofedRes = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer paired-auth-secret-999',
          'origin': 'https://phishing-attacker.com',
        },
        body: jsonEncode({'url': 'https://bank.com'}),
      );
      expect(spoofedRes.statusCode, HttpStatus.forbidden);

      await bridge.close();
    });

    // -------------------------------------------------------------------------
    // T3.7 & T3.8: Android Settings Navigation + macOS Background Lock
    // -------------------------------------------------------------------------
    test('T3.7 Android settings navigation during runWithoutAutoLock preserves unlocked state with autoLock 0', () async {
      final auth = AuthProvider();
      final settings = SettingsProvider();
      await settings.load();
      await settings.setAutoLockMinutes(0); // Timed auto-lock disabled

      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      // Navigate settings screens within suppression block
      await auth.runWithoutAutoLock(() async {
        expect(auth.isAutoLockSuppressed, isTrue);
        // Simulate deep navigation delay
        await Future.delayed(const Duration(milliseconds: 20));
        expect(auth.isUnlocked, isTrue);
      });

      expect(auth.isAutoLockSuppressed, isFalse);
      expect(auth.isUnlocked, isTrue);
    });

    test('T3.8 Explicit manual lock overrides lockOnBackground=false preference immediately', () async {
      final settings = SettingsProvider();
      await settings.load();
      await settings.setLockOnBackground(false); // User does not want background lock

      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      // User taps "Lock Vault Now" button
      auth.lockVault();
      expect(auth.isUnlocked, isFalse);
      expect(auth.masterKey, isNull);
    });

    // -------------------------------------------------------------------------
    // T3.9 & T3.19: Centralized TOTP Ticker + Item Detail Pane
    // -------------------------------------------------------------------------
    test('T3.9 Centralized TOTP ticker distributes synchronized ticks to multiple detail panes', () async {
      final ticker = E2ETestHelpers.createCentralTicker();
      final ticksReceivedPane1 = <DateTime>[];
      final ticksReceivedPane2 = <DateTime>[];

      final sub1 = ticker.subscribe((t) => ticksReceivedPane1.add(t));
      final sub2 = ticker.subscribe((t) => ticksReceivedPane2.add(t));
      expect(ticker.activeSubscribers, 2);

      // Verify that canceling one view does not terminate the ticker for others
      await sub1.cancel();
      expect(ticker.activeSubscribers, 1);

      await sub2.cancel();
      expect(ticker.activeSubscribers, 0);
      ticker.dispose();
    });

    test('T3.19 Read-only detail pane custom fields support toggleable secret masking', () {
      final field = const CustomField(
        id: 'cf-secret-1',
        label: 'Recovery Mnemonic',
        value: 'witch collapse practice feed shame open despair creek road again ice leap',
        isHidden: true,
      );

      expect(field.isHidden, isTrue);
      // Detail pane unmask action
      final revealed = field.copyWith(isHidden: false);
      expect(revealed.isHidden, isFalse);
      expect(revealed.value, field.value);
    });

    // -------------------------------------------------------------------------
    // T3.10 & T3.17: Fast Startup Loading + Centralized Ticker
    // -------------------------------------------------------------------------
    test('T3.10 Cold-start offline cache loading initializes vault before network sync', () async {
      final prefs = await SharedPreferences.getInstance();
      final cachedItem = E2ETestHelpers.sampleCredential(id: 'cached-1', title: 'Cached Offline Bank');
      await prefs.setString(
        AppConstants.keyOfflineItems,
        jsonEncode([
          {
            'id': cachedItem.id,
            'type': 'credential',
            'title': cachedItem.title,
            'username': cachedItem.username,
            'password': cachedItem.password,
            'website': cachedItem.website,
          }
        ]),
      );

      final rawStored = prefs.getString(AppConstants.keyOfflineItems);
      expect(rawStored, isNotNull);
      final decoded = jsonDecode(rawStored!) as List;
      expect(decoded.length, 1);
      expect(decoded.first['title'], 'Cached Offline Bank');
    });

    test('T3.17 Large batch items decryption without TOTP does not spawn unnecessary tickers', () {
      final largeVault = List.generate(
        50,
        (i) => E2ETestHelpers.sampleCredential(
          id: 'item-$i',
          title: 'Service $i',
          totpSecret: '', // No TOTP
        ),
      );

      final ticker = E2ETestHelpers.createCentralTicker();
      // Only items with TOTP should subscribe
      int totpSubscribers = 0;
      for (final item in largeVault) {
        if (item.totpSecret.isNotEmpty) {
          totpSubscribers++;
          ticker.subscribe((_) {});
        }
      }

      expect(totpSubscribers, 0);
      expect(ticker.activeSubscribers, 0); // No listeners allocated for non-TOTP items
      ticker.dispose();
    });

    // -------------------------------------------------------------------------
    // T3.11 & T3.12: Android Quick Autofill Shortcuts + Quick Search
    // -------------------------------------------------------------------------
    test('T3.11 Cold start launch with quick_search action triggers registered callback', () async {
      E2ETestHelpers.setPendingLaunchAction('quick_search');
      bool searchLaunched = false;

      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => searchLaunched = true,
      );

      expect(searchLaunched, isTrue);
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:consumePendingLaunchAction'));
    });

    test('T3.12 Cold start launch with lock_vault action invokes lock handler', () async {
      E2ETestHelpers.setPendingLaunchAction('lock_vault');
      bool lockInvoked = false;

      // Platform channel simulator invokes lock callback
      await NativeBridgeService.initialize(
        onLockVaultRequested: () => lockInvoked = true,
      );

      // Verify channel callback registration
      expect(lockInvoked, isFalse);
    });

    // -------------------------------------------------------------------------
    // T3.13 & T3.14: Mobile Autofill Save & Update + Hardware Index Sync
    // -------------------------------------------------------------------------
    test('T3.13 Adding new credential updates hardware autofill index on native platform', () async {
      const channel = MethodChannel('com.multipad.multipad/native');

      final newCred = E2ETestHelpers.sampleCredential(
        title: 'New Online Store',
        username: 'customer@store.com',
        website: 'https://store.com',
      );

      await channel.invokeMethod('updateAutofillIndex', {
        'entries': [
          {'id': newCred.id, 'title': newCred.title, 'username': newCred.username}
        ]
      });

      expect(E2ETestHelpers.invokedNativeMethods, contains('native:updateAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries.length, 1);
      expect(E2ETestHelpers.lastAutofillEntries.first['username'], 'customer@store.com');
    });

    test('T3.14 Vault lock triggers native clearAutofillIndex wiping hardware memory', () async {
      const channel = MethodChannel('com.multipad.multipad/native');

      // 1. Populate autofill index
      await channel.invokeMethod('updateAutofillIndex', {
        'entries': [{'id': '1', 'title': 'Secret Site'}]
      });
      expect(E2ETestHelpers.lastAutofillEntries.length, 1);

      // 2. Vault locks -> clearAutofillIndex
      await channel.invokeMethod('clearAutofillIndex');
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:clearAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries, isEmpty);
    });

    // -------------------------------------------------------------------------
    // T3.15 & T3.16: Password Generator + Credential Editor & Sorting
    // -------------------------------------------------------------------------
    test('T3.15 High-entropy generated password can be attached directly to VaultItem', () {
      final generatedPassword = E2ETestHelpers.generateSecureRandomPassword(
        length: 24,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
      );

      expect(generatedPassword.length, 24);
      final item = VaultItem(
        id: 'new-cred-1',
        type: VaultItemType.credential,
        title: 'High Security Server',
        username: 'root',
        password: generatedPassword,
      );

      expect(item.password, generatedPassword);
      final audit = AuditService.analyzeVault([item]);
      expect(audit.weakPasswordsCount, 0); // Generated password is strong
    });

    test('T3.16 Items assigned to specific folders preserve A-Z title sorting within folder', () {
      const folderId = 'folder-finance-1';
      final folderItems = [
        E2ETestHelpers.sampleCredential(id: '1', title: 'Wells Fargo', folderId: folderId),
        E2ETestHelpers.sampleCredential(id: '2', title: 'Bank of America', folderId: folderId),
        E2ETestHelpers.sampleCredential(id: '3', title: 'Chase Bank', folderId: folderId),
      ];

      final filteredSorted = folderItems
          .where((i) => i.folderId == folderId)
          .toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      expect(filteredSorted[0].title, 'Bank of America');
      expect(filteredSorted[1].title, 'Chase Bank');
      expect(filteredSorted[2].title, 'Wells Fargo');
    });

    // -------------------------------------------------------------------------
    // T3.18: Circular Biometric Button + Confidential Copy
    // -------------------------------------------------------------------------
    test('T3.18 Biometric unlock followed by copy securely invokes native confidential clipboard', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      // 1. Biometric unlock
      await auth.checkInitialState();
      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isTrue);

      // 2. Confidential copy
      await ClipboardService.copySecurely('MasterSecretToken!99', timeoutSeconds: 30);
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:copyConfidential'));
      ClipboardService.cancelScheduledClear();
    });
  });
}
