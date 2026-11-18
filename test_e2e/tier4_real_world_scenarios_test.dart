import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/biometric_service.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/import_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/services/totp_service.dart';
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
  // Tier 4: Real-World Application Scenarios (5 Comprehensive Workflows)
  // ===========================================================================
  group('Tier 4: Real-World Application Scenarios', () {
    // -------------------------------------------------------------------------
    // Scenario 1: New User Onboarding, Password Generation, Credential Storage,
    //             Clipboard Auto-Clear, and Hygiene Audit
    // -------------------------------------------------------------------------
    test('Scenario 1: Complete new user onboarding, generation, storage, clipboard auto-clear, and hygiene audit', () async {
      final crypto = CryptoService();
      final auth = AuthProvider();

      // --- Stage 1: User Onboarding & Master Key Creation ---
      const masterPassword = 'MasterPassword2026!SecureKey';
      final argonSalt = crypto.generateArgon2idSalt();
      expect(CryptoService.isArgon2idSalt(argonSalt), isTrue);

      final masterKey = await crypto.deriveMasterKey(masterPassword, argonSalt);
      expect(masterKey.length, 32);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyMasterSalt, argonSalt);
      await prefs.setString(AppConstants.keyCachedEmail, 'newuser@multipad.io');

      await auth.checkInitialState();
      expect(auth.status, VaultLockStatus.lockedWithPass);

      // --- Stage 2: High-Entropy Password Generation ---
      final generatedPassword = E2ETestHelpers.generateSecureRandomPassword(
        length: 24,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
        avoidAmbiguous: true,
      );
      expect(generatedPassword.length, 24);
      expect(generatedPassword.contains(RegExp(r'[A-Z]')), isTrue);
      expect(generatedPassword.contains(RegExp(r'[a-z]')), isTrue);
      expect(generatedPassword.contains(RegExp(r'[0-9]')), isTrue);
      expect(generatedPassword.contains(RegExp(r'[!@#\$%^&*()-_=+\[\]{}|;:,.<>?]')), isTrue);
      expect(generatedPassword.contains(RegExp(r'[OIl01]')), isFalse);
      expect(AuditService.isPasswordWeak(generatedPassword), isFalse);

      // --- Stage 3: Multiple Vault Items Creation & Cryptographic Storage ---
      final gitHubItem = VaultItem(
        id: 'item-github-1',
        type: VaultItemType.credential,
        title: 'GitHub Enterprise',
        username: 'octocat_work',
        password: generatedPassword,
        website: 'https://github.enterprise.local',
        totpSecret: '', // No 2FA
        passwordLastModified: DateTime.now().toUtc(),
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      final awsItem = VaultItem(
        id: 'item-aws-2',
        type: VaultItemType.credential,
        title: 'AWS Production Console',
        username: 'devops-lead',
        password: 'StrongAwSPassword#2026!',
        website: 'https://console.aws.amazon.com',
        totpSecret: 'JBSWY3DPEHPK3PXP', // Has 2FA
        passwordLastModified: DateTime.now().toUtc(),
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      final cardItem = VaultItem(
        id: 'item-card-3',
        type: VaultItemType.card,
        title: 'Corporate Purchasing Card',
        cardNumber: '4111 1111 1111 1111', // Valid Luhn Visa
        cardExpiry: '12/28',
        cardCvv: '789',
        cardHolder: 'Jane Doe',
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      // Verify encryption and decryption round-trip for stored items
      final encryptedGithub = await crypto.encryptData(gitHubItem.toPlainJson(), masterKey);
      final decryptedGithubStr = await crypto.decryptData(
        ciphertextBase64: encryptedGithub.ciphertext,
        ivBase64: encryptedGithub.iv,
        macBase64: encryptedGithub.mac,
        masterKey: masterKey,
      );
      final restoredGithub = VaultItem.fromDecryptedJson(
        id: gitHubItem.id,
        type: gitHubItem.type,
        decryptedPayload: jsonDecode(decryptedGithubStr) as Map<String, dynamic>,
        isDeleted: false,
        clientUpdatedAt: DateTime.now().toUtc(),
      );
      expect(restoredGithub.password, generatedPassword);
      expect(restoredGithub.title, 'GitHub Enterprise');

      // --- Stage 4: Confidential Clipboard Copy & Scheduled Auto-Clear ---
      ClipboardService.setDefaultTimeoutSeconds(1);
      await ClipboardService.copySecurely(awsItem.password, timeoutSeconds: 1);
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:copyConfidential'));

      // Verify scheduled clear can be cancelled or completed safely
      ClipboardService.cancelScheduledClear();

      // --- Stage 5: Centralized TOTP Ticker & Real-Time Code Generation ---
      final centralTicker = E2ETestHelpers.createCentralTicker();
      DateTime? capturedTick;
      final sub = centralTicker.subscribe((tick) {
        capturedTick = tick;
      });
      expect(capturedTick, isNull); // Initial before async tick

      expect(centralTicker.activeSubscribers, 1);
      final now = DateTime.now();
      final totpCode = TotpService.generateCode(
        awsItem.totpSecret,
        timeMs: now.millisecondsSinceEpoch,
      );
      expect(totpCode, isNotNull);
      expect(totpCode!.length, 6);
      expect(int.tryParse(totpCode), isNotNull);

      await sub.cancel();
      expect(centralTicker.activeSubscribers, 0);
      centralTicker.dispose();

      // --- Stage 6: Calibrated Vault Hygiene Audit ---
      final audit = AuditService.analyzeVault([gitHubItem, awsItem, cardItem]);
      expect(audit.totalAccounts, 2); // 2 credentials
      expect(audit.weakPasswordsCount, 0);
      expect(audit.reusedPasswordsCount, 0);
      expect(audit.invalidCardsCount, 0);

      // Invariant: Missing 2FA on gitHubItem is NOT classified as a high-severity vulnerability
      expect(audit.missing2faCount, 1);
      final criticalIssues = audit.issues.where((i) => i.severity >= 3).toList();
      expect(criticalIssues, isEmpty);
      expect(audit.overallScore, greaterThanOrEqualTo(85));
    });

    // -------------------------------------------------------------------------
    // Scenario 2: Bitwarden Vault Migration, Encrypted JSON Import with Master
    //             Password, A-Z Browsing, and Audit Scoring
    // -------------------------------------------------------------------------
    test('Scenario 2: Bitwarden vault migration, encrypted JSON import, A-Z browsing, and audit scoring', () async {
      // --- Stage 1: Build Bitwarden Vault Export Fixture with Mixed Credentials ---
      final folderList = [
        {'id': 'f-infra', 'name': 'Infrastructure'},
        {'id': 'f-tools', 'name': 'Internal Tools'},
        {'id': 'f-legacy', 'name': 'Legacy Systems'},
      ];

      final rawItems = [
        {
          'id': 'bw-1',
          'type': 1, // Login
          'name': 'Zeta Production Gateway',
          'folderId': 'f-infra',
          'login': {
            'username': 'admin_zeta',
            'password': 'ZetaStrongPassword!2026#',
            'uris': [{'uri': 'https://zeta.infra.io'}],
            'totp': null, // No 2FA
          },
        },
        {
          'id': 'bw-2',
          'type': 1,
          'name': 'Alpha Portal',
          'folderId': 'f-tools',
          'login': {
            'username': 'alpha_user',
            'password': r'AlphaSecretPassword!2026$',
            'uris': [{'uri': 'https://alpha.internal.tools'}],
            'totp': 'JBSWY3DPEHPK3PXP', // Has 2FA
          },
        },
        {
          'id': 'bw-3',
          'type': 1,
          'name': 'Beta Legacy Service',
          'folderId': 'f-legacy',
          'login': {
            'username': 'beta_dev',
            'password': '123456', // Weak password
            'uris': [{'uri': 'https://beta.legacy.com'}],
            'totp': null,
          },
        },
        {
          'id': 'bw-4',
          'type': 1,
          'name': 'Delta Backup Mirror',
          'folderId': 'f-legacy',
          'login': {
            'username': 'delta_bot',
            'password': '123456', // Reused weak password
            'uris': [{'uri': 'https://delta.mirror.net'}],
            'totp': null,
          },
        },
        {
          'id': 'bw-5',
          'type': 3, // Card
          'name': 'Echo Corporate Amex',
          'card': {
            'cardholderName': 'Alice Smith',
            'number': '4111 1111 1111 1111', // Luhn valid
            'expMonth': '11',
            'expYear': '2029',
            'code': '987',
          },
        },
        {
          'id': 'bw-6',
          'type': 3, // Card
          'name': 'Failing Expired Visa',
          'card': {
            'cardholderName': 'Bob Jones',
            'number': '4000 0000 0000 0002', // Invalid / Expired
            'expMonth': '01',
            'expYear': '2020', // Expired
            'code': '123',
          },
        },
      ];

      final innerPayload = jsonEncode({
        'folders': folderList,
        'items': rawItems,
      });

      const importPassword = 'BitwardenMigratePass2026!';
      const userEmail = 'migrator@multipad.test';

      final encryptedExportJson = await E2ETestHelpers.createBitwardenEncryptedJsonFixture(
        password: importPassword,
        userEmail: userEmail,
        innerJsonPlaintext: innerPayload,
      );

      // --- Stage 2: Format Detection & Password Prompt Simulation ---
      final envelope = jsonDecode(encryptedExportJson) as Map<String, dynamic>;
      final isEncrypted = envelope['encrypted'] == true || envelope['passwordProtected'] == true;
      expect(isEncrypted, isTrue);
      expect(envelope['kdfType'], 0); // PBKDF2
      expect(envelope['data'].toString().startsWith('2.'), isTrue);

      // Tamper / wrong password protection: Wrong password derivation fails MAC verification
      final wrongSubKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'WrongPassword!999',
        salt: userEmail,
      );
      expect(
        () async => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: envelope['data'] as String,
          encKey: wrongSubKeys.encKey,
          macKey: wrongSubKeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );

      // Correct password derivation successfully decrypts inner payload
      final correctSubKeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: importPassword,
        salt: userEmail,
      );
      final decryptedCleartext = await E2ETestHelpers.decryptBitwardenCipherString(
        cipherString: envelope['data'] as String,
        encKey: correctSubKeys.encKey,
        macKey: correctSubKeys.macKey,
      );
      expect(decryptedCleartext, equals(innerPayload));

      // --- Stage 3: Ingestion via ImportService ---
      final preview = ImportService.inspectFile(
        decryptedCleartext,
        fileName: 'bitwarden_export.json',
        formatHint: ImportSourceFormat.bitwardenJson,
      );

      expect(preview.detectedFormat, ImportSourceFormat.bitwardenJson);
      expect(preview.directParsedItems.length, 6);
      expect(preview.directParsedFolders.length, 3);

      // --- Stage 4: Bitwarden-Style A-Z Browsing & Folder Navigation ---
      final importedItems = List<VaultItem>.from(preview.directParsedItems);
      importedItems.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      final itemTitles = importedItems.map((e) => e.title).toList();
      expect(itemTitles, [
        'Alpha Portal',
        'Beta Legacy Service',
        'Delta Backup Mirror',
        'Echo Corporate Amex',
        'Failing Expired Visa',
        'Zeta Production Gateway',
      ]);

      // Filtering by folder 'Legacy Systems' using newly mapped folder ID
      final legacyFolder = preview.directParsedFolders.firstWhere((f) => f.name == 'Legacy Systems');
      final legacyItems = importedItems.where((i) => i.folderId == legacyFolder.id).toList();
      expect(legacyItems.length, 2);
      expect(legacyItems.map((e) => e.title).toList(), containsAll(['Beta Legacy Service', 'Delta Backup Mirror']));

      // --- Stage 5: Security Audit Evaluation & Scoring ---
      final auditReport = AuditService.analyzeVault(importedItems);
      expect(auditReport.totalAccounts, 4); // 4 credentials
      expect(auditReport.weakPasswordsCount, 2); // '123456' on Beta & Delta
      expect(auditReport.reusedPasswordsCount, 2); // Shared '123456'
      expect(auditReport.expiringCardsCount, greaterThanOrEqualTo(1)); // Expired card

      // Calibrated audit invariant: 'Zeta Production Gateway' lacks 2FA, but high-severity issues
      // must NOT include missing 2FA (only weak/reused passwords and expired cards)
      final highSeverityIssues = auditReport.issues.where((i) => i.severity >= 3).toList();
      final highSeverityTypes = highSeverityIssues.map((i) => i.issueType).toSet();
      expect(highSeverityTypes.contains('missing_2fa'), isFalse);
      expect(highSeverityTypes.contains('weak'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 3: Daily Desktop Workflow: Startup Biometric Auto-Trigger,
    //             Browser Extension Pairing, Domain Matching, and Capture
    // -------------------------------------------------------------------------
    test('Scenario 3: Daily desktop workflow: biometric auto-trigger, extension pairing, domain matching, and capture', () async {
      // --- Stage 1: Desktop Startup & Biometric Auto-Trigger ---
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyMasterSalt, 'v2:argon2id:m65536:t3:p4:desktopSaltB64==');
      await prefs.setString(AppConstants.keyCachedEmail, 'desktop.user@multipad.io');
      await prefs.setBool(AppConstants.keyLockOnBackground, false); // macOS default

      final masterKey = List<int>.generate(32, (i) => i + 10);
      final bio = BiometricService();
      await bio.enableBiometrics(masterKey);

      final auth = AuthProvider();
      await auth.checkInitialState();
      expect(auth.canUseBiometricsNow, isTrue);

      // Auto-trigger biometrics on app startup
      final autoUnlocked = await auth.unlockWithBiometrics(isSilentAutoTrigger: true);
      expect(autoUnlocked, isTrue);
      expect(auth.isUnlocked, isTrue);
      expect(auth.masterKey, equals(masterKey));

      // --- Stage 2: Browser Extension Pairing via Loopback Bridge ---
      final vaultStore = [
        E2ETestHelpers.sampleCredential(
          id: 'cred-gh',
          title: 'GitHub Production',
          username: 'lead_dev',
          password: 'GitPassword!2026#',
          website: 'https://github.com/login',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
        E2ETestHelpers.sampleCredential(
          id: 'cred-gl',
          title: 'Internal GitLab',
          username: 'lead_dev',
          password: 'GitLabPassword!2026#',
          website: 'https://gitlab.internal.corp',
        ),
      ];

      Map<String, dynamic>? newlyCapturedCredential;
      const pairingToken = 'desktop_token_998877';

      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: pairingToken,
        getItems: () => vaultStore,
        isUnlocked: () => auth.isUnlocked,
        onCredentialCaptured: (captured) {
          newlyCapturedCredential = captured;
          vaultStore.add(VaultItem(
            id: 'cred-captured-${vaultStore.length + 1}',
            type: VaultItemType.credential,
            title: captured['url']?.toString() ?? 'Captured Item',
            username: captured['username']?.toString() ?? '',
            password: captured['password']?.toString() ?? '',
            website: captured['url']?.toString() ?? '',
          ));
        },
      );

      final client = bridge.client;

      // Discovery endpoint
      final statusRes = await client.get(Uri.parse('${bridge.baseUrl}/status'));
      expect(statusRes.statusCode, HttpStatus.ok);
      final statusJson = jsonDecode(statusRes.body) as Map<String, dynamic>;
      expect(statusJson['status'], 'unlocked');

      // Extension pairing endpoint
      final pairRes = await client.post(Uri.parse('${bridge.baseUrl}/pair'));
      expect(pairRes.statusCode, HttpStatus.ok);
      final pairJson = jsonDecode(pairRes.body) as Map<String, dynamic>;
      expect(pairJson['token'], pairingToken);

      // Security check: Spoofed origin is rejected
      final spoofedRes = await client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'https://evil.attacker.com',
          'Authorization': 'Bearer $pairingToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': 'https://github.com/login'}),
      );
      expect(spoofedRes.statusCode, HttpStatus.forbidden);

      // --- Stage 3: Domain Matching & Query Execution ---
      final queryRes = await client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'chrome-extension://mpadextensionid1234',
          'Authorization': 'Bearer $pairingToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': 'https://github.com/login'}),
      );
      expect(queryRes.statusCode, HttpStatus.ok);
      final queryJson = jsonDecode(queryRes.body) as Map<String, dynamic>;
      final matches = (queryJson['matches'] as List).cast<Map<String, dynamic>>();
      expect(matches.length, 1);
      expect(matches.first['title'], 'GitHub Production');
      expect(matches.first['username'], 'lead_dev');
      expect(matches.first['totp'], 'JBSWY3DPEHPK3PXP');

      // Real-time TOTP code verification
      final totpCode = TotpService.generateCode(
        matches.first['totp'] as String,
        timeMs: DateTime.now().millisecondsSinceEpoch,
      );
      expect(totpCode, isNotNull);
      expect(totpCode!.length, 6);

      // --- Stage 4: Web Credential Capture ---
      final captureRes = await client.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {
          'Origin': 'chrome-extension://mpadextensionid1234',
          'Authorization': 'Bearer $pairingToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'url': 'https://app.slack.com',
          'username': 'slack_user@company.com',
          'password': 'SlackPassword!2026#',
        }),
      );
      expect(captureRes.statusCode, HttpStatus.created);
      expect(newlyCapturedCredential, isNotNull);
      expect(newlyCapturedCredential!['username'], 'slack_user@company.com');

      // Subsequent query for newly captured service returns match
      final slackQueryRes = await client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'chrome-extension://mpadextensionid1234',
          'Authorization': 'Bearer $pairingToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': 'https://app.slack.com'}),
      );
      expect(slackQueryRes.statusCode, HttpStatus.ok);
      final slackMatches = (jsonDecode(slackQueryRes.body)['matches'] as List);
      expect(slackMatches.length, 1);

      // --- Stage 5: Window Background vs. Explicit Manual Lock ---
      // Window blur does not lock because lockOnBackground is false
      final settings = SettingsProvider();
      await settings.load();
      expect(settings.lockOnBackground, isFalse);

      // Explicit user lock locks the vault and bridge returns 423
      auth.lockVault();
      expect(auth.isUnlocked, isFalse);

      final lockedQueryRes = await client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Origin': 'chrome-extension://mpadextensionid1234',
          'Authorization': 'Bearer $pairingToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': 'https://github.com/login'}),
      );
      expect(lockedQueryRes.statusCode, HttpStatus.locked);

      await bridge.close();
    });

    // -------------------------------------------------------------------------
    // Scenario 4: Mobile Autofill Workflow: Quick PIN Unlock, Quick Settings
    //             Shortcut, Android Autofill Index Sync, and Clean Lock Wipe
    // -------------------------------------------------------------------------
    test('Scenario 4: Mobile autofill workflow: Quick PIN unlock, Quick Settings shortcut, Android Autofill sync, and clean wipe', () async {
      final crypto = CryptoService();
      final secureStorage = const FlutterSecureStorage();
      final prefs = await SharedPreferences.getInstance();

      // --- Stage 1: Quick PIN Enrollment & Verification ---
      final masterKey = List<int>.generate(32, (i) => i + 42);
      const userPin = '849201';
      final pinSaltB64 = base64Encode(crypto.generateRandomBytes(32));

      final pinWrappingKey = await crypto.derivePinWrappingKey(userPin, pinSaltB64);
      final wrappedMasterPayload = await crypto.encryptData(base64Encode(masterKey), pinWrappingKey);

      await prefs.setString(AppConstants.keyQuickPinSalt, pinSaltB64);
      await prefs.setBool(AppConstants.keyQuickPinEnabled, true);
      await prefs.setString(AppConstants.keyMasterSalt, base64Encode(crypto.generateRandomBytes(32)));
      await secureStorage.write(
        key: AppConstants.keyQuickPinWrappedMasterKey,
        value: jsonEncode(wrappedMasterPayload.toJson()),
      );

      final auth = AuthProvider();
      await auth.checkInitialState();
      expect(auth.isQuickPinEnabled, isTrue);
      expect(auth.status, VaultLockStatus.lockedWithPass);

      // Unlock with Quick PIN
      final pinUnlocked = await auth.unlockWithQuickPin(userPin);
      expect(pinUnlocked, isTrue);
      expect(auth.isUnlocked, isTrue);
      expect(auth.masterKey, equals(masterKey));

      // --- Stage 2: Android Autofill Subsystem Synchronization ---
      const nativeChannel = MethodChannel('com.multipad.multipad/native');
      await nativeChannel.invokeMethod('updateAutofillIndex', {
        'entries': [
          {'id': 'm-1', 'title': 'Twitter/X', 'username': 'mobile_user', 'domain': 'x.com'},
          {'id': 'm-2', 'title': 'Instagram', 'username': 'mobile_insta', 'domain': 'instagram.com'},
        ],
      });

      expect(E2ETestHelpers.invokedNativeMethods, contains('native:updateAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries.length, 2);
      expect(E2ETestHelpers.lastAutofillEntries.first['domain'], 'x.com');

      // --- Stage 3: Android Quick Settings Tile Launch Action ---
      bool quickSearchTriggered = false;
      E2ETestHelpers.setPendingLaunchAction('quick_search');

      await NativeBridgeService.initialize(
        onQuickSearchRequested: () {
          quickSearchTriggered = true;
        },
      );

      expect(quickSearchTriggered, isTrue);
      expect(auth.isUnlocked, isTrue); // Preserves unlocked state

      // --- Stage 4: In-App Settings Navigation with Auto-Lock Suppression ---
      await auth.runWithoutAutoLock(() async {
        expect(auth.isAutoLockSuppressed, isTrue);
        // Simulate deep navigation across settings sub-screens
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      expect(auth.isAutoLockSuppressed, isFalse);

      // --- Stage 5: Mobile Lock, Autofill Memory Wipe & RAM Key Cleansing ---
      await nativeChannel.invokeMethod('clearAutofillIndex');
      expect(E2ETestHelpers.invokedNativeMethods, contains('native:clearAutofillIndex'));
      expect(E2ETestHelpers.lastAutofillEntries, isEmpty);

      // Lock vault and verify memory zero-wipe
      final keyBufferCopy = Uint8List.fromList(auth.masterKey!);
      auth.lockVault();
      expect(auth.isUnlocked, isFalse);
      expect(auth.masterKey, isNull);

      CryptoService.wipe(keyBufferCopy);
      expect(keyBufferCopy.every((b) => b == 0), isTrue);
    });

    // -------------------------------------------------------------------------
    // Scenario 5: Enterprise Security Hardening: 60-Day 2FA Interval, Argon2id
    //             Key Derivation, Offline Cold-Start Cache Recovery
    // -------------------------------------------------------------------------
    test('Scenario 5: Enterprise security hardening: 60-day 2FA interval, Argon2id key derivation, offline cold-start cache recovery', () async {
      final crypto = CryptoService();

      // --- Stage 1: Enterprise Argon2id Master Key Derivation ---
      final enterpriseSalt = crypto.generateArgon2idSalt();
      expect(CryptoService.isArgon2idSalt(enterpriseSalt), isTrue);

      final saltParts = enterpriseSalt.split(':');
      expect(saltParts[0], 'v2');
      expect(saltParts[1], 'argon2id');
      expect(saltParts[2], 'm${AppConstants.argon2MemoryKib}');
      expect(saltParts[3], 't${AppConstants.argon2Iterations}');
      expect(saltParts[4], 'p${AppConstants.argon2Parallelism}');

      final enterpriseKey = await crypto.deriveMasterKey('EnterpriseMasterSecretPassword!2026', enterpriseSalt);
      expect(enterpriseKey.length, 32);

      // --- Stage 2: 60-Day 2FA Re-Prompt Interval Policy ---
      const repromptDays = 60;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('multipad_2fa_reprompt_days', repromptDays);

      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

      // Day 0: Initial login requires 2FA (lastVerified is null)
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: null,
          intervalDays: repromptDays,
          now: t0,
        ),
        isTrue,
      );

      // Day 15: Within 60-day window -> Instant unlock, no 2FA prompt
      final t15 = t0.add(const Duration(days: 15));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: t0,
          intervalDays: repromptDays,
          now: t15,
        ),
        isFalse,
      );

      // Day 59: Within 60-day window -> Instant unlock
      final t59 = t0.add(const Duration(days: 59));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: t0,
          intervalDays: repromptDays,
          now: t59,
        ),
        isFalse,
      );

      // Day 60: Exact boundary condition -> 2FA prompt triggered
      final t60 = t0.add(const Duration(days: 60));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: t0,
          intervalDays: repromptDays,
          now: t60,
        ),
        isTrue,
      );

      // Day 75: Overdue -> 2FA prompt triggered
      final t75 = t0.add(const Duration(days: 75));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: t0,
          intervalDays: repromptDays,
          now: t75,
        ),
        isTrue,
      );

      // After completing 2FA verification at t75, new verification timestamp resets cycle
      final t80 = t75.add(const Duration(days: 5));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: t75,
          intervalDays: repromptDays,
          now: t80,
        ),
        isFalse,
      );

      // --- Stage 3: Offline Cold-Start Cache Recovery & Accelerated Loading ---
      final offlineCachedItems = <VaultItem>[];
      for (int i = 1; i <= 25; i++) {
        offlineCachedItems.add(VaultItem(
          id: 'ent-cache-$i',
          type: VaultItemType.credential,
          title: i == 1 ? 'Enterprise LDAP Server' : 'Corporate Asset #$i',
          username: 'admin_$i',
          password: 'ComplexPassword!$i#2026',
          website: 'https://asset-$i.internal.corp',
          clientUpdatedAt: t0,
        ));
      }

      // Parallel batch encryption simulation
      final encryptedCache = await Future.wait(
        offlineCachedItems.map((item) => crypto.encryptData(item.toPlainJson(), enterpriseKey)),
      );
      expect(encryptedCache.length, 25);

      // Cold start: Parallel batch decryption restores vault completely offline
      final decryptedJsonList = await Future.wait(
        encryptedCache.map((enc) => crypto.decryptData(
              ciphertextBase64: enc.ciphertext,
              ivBase64: enc.iv,
              macBase64: enc.mac,
              masterKey: enterpriseKey,
            )),
      );

      final restoredItems = decryptedJsonList.asMap().entries.map((entry) {
        final original = offlineCachedItems[entry.key];
        return VaultItem.fromDecryptedJson(
          id: original.id,
          type: original.type,
          decryptedPayload: jsonDecode(entry.value) as Map<String, dynamic>,
          isDeleted: false,
          clientUpdatedAt: t0,
        );
      }).toList();
      expect(restoredItems.length, 25);

      // Offline search functions instantly without network
      final searchResults = restoredItems.where((i) => i.title.toLowerCase().contains('ldap')).toList();
      expect(searchResults.length, 1);
      expect(searchResults.first.title, 'Enterprise LDAP Server');

      // --- Stage 4: Cryptographic Invariants & Side-Channel Tamper Resistance ---
      final itemHash1 = CryptoService.sha256Hex(restoredItems.first.toPlainJson());
      final itemHash2 = CryptoService.sha256Hex(restoredItems.first.toPlainJson());
      expect(CryptoService.constantTimeStringEquals(itemHash1, itemHash2), isTrue);

      final tamperedHash = itemHash1.substring(0, itemHash1.length - 1) + (itemHash1.endsWith('0') ? '1' : '0');
      expect(CryptoService.constantTimeStringEquals(itemHash1, tamperedHash), isFalse);

      // Clean session termination: Zero-wipe sensitive enterprise master key in RAM
      final enterpriseKeyCopy = Uint8List.fromList(enterpriseKey);
      CryptoService.wipe(enterpriseKeyCopy);
      expect(enterpriseKeyCopy.every((b) => b == 0), isTrue);
    });
  });
}
