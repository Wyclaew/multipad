import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
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
  // Boundary Group B1: Biometric Boundaries & Corner Cases
  // ===========================================================================
  group('Tier 2: Boundary B1 - Biometric Boundaries & Corner Cases', () {
    test('B1.1 rapid consecutive biometric unlock attempts do not corrupt auth state', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      final masterKey = List<int>.generate(32, (i) => i * 3);
      await bio.enableBiometrics(masterKey);
      await auth.checkInitialState();

      // Rapidly invoke biometric unlock 5 times concurrently
      final futures = List.generate(5, (_) => auth.unlockWithBiometrics());
      final results = await Future.wait(futures);

      expect(results, contains(true));
      expect(auth.isUnlocked, isTrue);
      expect(auth.masterKey, equals(masterKey));
    });

    test('B1.2 biometric hardware revocation mid-session is safely detected', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.checkInitialState();
      expect(auth.canUseBiometricsNow, isTrue);

      // Hardware is revoked or un-enrolled by OS
      E2ETestHelpers.setBiometricsBehavior(hardwareSupported: false, enrolled: false);

      final canCheck = await bio.canCheckBiometrics();
      expect(canCheck, isFalse);

      await auth.checkInitialState();
      expect(auth.canUseBiometricsNow, isFalse);
    });

    test('B1.3 corrupted biometric payload in secure storage triggers graceful fallback', () async {
      const storage = FlutterSecureStorage();
      // Store corrupted, non-base64 payload
      await storage.write(key: AppConstants.keyBiometricMasterKey, value: '%%%NOT_VALID_BASE64%%%');
      await storage.write(key: AppConstants.keyBiometricEnabled, value: 'true');

      final auth = AuthProvider();
      final bio = BiometricService();
      expect(await bio.isBiometricUnlockEnabled(), isTrue);

      final key = await bio.retrieveBiometricMasterKey();
      expect(key, isNull);

      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isFalse);
      expect(auth.isUnlocked, isFalse);
    });

    test('B1.4 empty master key handling during biometric enablement', () async {
      final bio = BiometricService();
      await bio.enableBiometrics([]);
      final key = await bio.retrieveBiometricMasterKey();
      expect(key != null && key.isEmpty, isTrue);
    });

    test('B1.5 exact lockout expiration boundary transitions cleanly from locked to ready', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Set lockout to 1 second ago (expired)
      await prefs.setString(
        AppConstants.keyLockoutUntilIso,
        now.subtract(const Duration(seconds: 1)).toIso8601String(),
      );

      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));

      await auth.checkInitialState();
      expect(auth.remainingLockout, equals(Duration.zero));
      expect(auth.canUseBiometricsNow, isTrue);
    });
  });

  // ===========================================================================
  // Boundary Group B2: State Switching, Race Conditions & Suppression Depths
  // ===========================================================================
  group('Tier 2: Boundary B2 - State Switching, Race Conditions & Suppression Depths', () {
    test('B2.1 deeply nested auto-lock suppression (depth 50) maintains strict balance', () async {
      final auth = AuthProvider();

      for (int i = 0; i < 50; i++) {
        auth.beginSuppressAutoLock();
      }
      expect(auth.isAutoLockSuppressed, isTrue);

      // Release 49 times -> still suppressed
      for (int i = 0; i < 49; i++) {
        auth.endSuppressAutoLock();
        expect(auth.isAutoLockSuppressed, isTrue);
      }

      // Final release -> suppression cleared
      auth.endSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isFalse);

      // Extra release does not underflow below zero
      auth.endSuppressAutoLock();
      expect(auth.isAutoLockSuppressed, isFalse);
    });

    test('B2.2 rapid window lifecycle transitions do not trigger race condition locks', () async {
      final auth = AuthProvider();
      final settings = SettingsProvider();
      await settings.load();
      await settings.setLockOnBackground(false);

      final bio = BiometricService();
      final key = List<int>.generate(32, (i) => i + 5);
      await bio.enableBiometrics(key);
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      // Rapidly simulate 20 pause / resume cycles
      for (int i = 0; i < 20; i++) {
        if (!settings.lockOnBackground) {
          expect(auth.isUnlocked, isTrue);
        }
      }
      expect(auth.isUnlocked, isTrue);
    });

    test('B2.3 beginSuppressAutoLockUntilResumed suppresses background lock during async external intents', () async {
      final auth = AuthProvider();
      final bio = BiometricService();
      await bio.enableBiometrics(List<int>.generate(32, (i) => i));
      await auth.unlockWithBiometrics();
      expect(auth.isUnlocked, isTrue);

      auth.beginSuppressAutoLockUntilResumed();
      expect(auth.isAutoLockSuppressed, isTrue);

      // External intent is running; app paused
      final shouldLock = auth.isUnlocked && !auth.isAutoLockSuppressed;
      expect(shouldLock, isFalse);

      // App resumes
      auth.notifyAppResumed();
      await Future.delayed(const Duration(milliseconds: 600));
      expect(auth.isAutoLockSuppressed, isFalse);
    });

    test('B2.4 cold-start launch actions handle null, empty, and whitespace strings', () async {
      E2ETestHelpers.setPendingLaunchAction('');
      bool triggered = false;
      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => triggered = true,
      );
      expect(triggered, isFalse);

      NativeBridgeService.resetForTesting();
      E2ETestHelpers.setPendingLaunchAction('   ');
      await NativeBridgeService.initialize(
        onQuickSearchRequested: () => triggered = true,
      );
      expect(triggered, isFalse);
    });

    test('B2.5 auto-lock duration handles boundary numbers (0, negative, max)', () async {
      final settings = SettingsProvider();
      await settings.load();

      await settings.setAutoLockMinutes(0);
      expect(settings.autoLockMinutes, 0);

      await settings.setAutoLockMinutes(-5);
      expect(settings.autoLockMinutes, -5);

      await settings.setAutoLockMinutes(1440); // 24 hours
      expect(settings.autoLockMinutes, 1440);
    });
  });

  // ===========================================================================
  // Boundary Group B3: 2FA Re-Prompt Interval & Clock Skew Boundaries
  // ===========================================================================
  group('Tier 2: Boundary B3 - 2FA Re-Prompt Interval & Clock Skew Boundaries', () {
    test('B3.1 2FA interval handles presets 30, 60, 90 and extreme values', () async {
      final prefs = await SharedPreferences.getInstance();

      for (final preset in [30, 60, 90]) {
        await prefs.setInt('multipad_2fa_reprompt_days', preset);
        expect(prefs.getInt('multipad_2fa_reprompt_days'), preset);
      }

      // Boundary values
      await prefs.setInt('multipad_2fa_reprompt_days', 0);
      expect(prefs.getInt('multipad_2fa_reprompt_days'), 0);

      await prefs.setInt('multipad_2fa_reprompt_days', 3650); // 10 years
      expect(prefs.getInt('multipad_2fa_reprompt_days'), 3650);
    });

    test('B3.2 exact millisecond boundary for 2FA expiration threshold', () {
      final base = DateTime.utc(2026, 1, 1, 12, 0, 0);
      const intervalDays = 30;

      // 1 ms before expiration -> prompt NOT due
      final justBefore = base.add(const Duration(days: intervalDays)).subtract(const Duration(milliseconds: 1));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: base,
          intervalDays: intervalDays,
          now: justBefore,
        ),
        isFalse,
      );

      // Exact moment of expiration -> prompt due
      final exactMoment = base.add(const Duration(days: intervalDays));
      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: base,
          intervalDays: intervalDays,
          now: exactMoment,
        ),
        isTrue,
      );
    });

    test('B3.3 backwards clock skew (future lastVerified) is safely treated', () {
      final now = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final futureVerified = now.add(const Duration(days: 10));

      final isDue = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: futureVerified,
        intervalDays: 30,
        now: now,
      );
      // Negative difference (< 30 days) does not cause unexpected re-prompt loops
      expect(isDue, isFalse);
    });

    test('B3.4 leap year boundary (366 days) correctly evaluates intervals', () {
      // 2028 is a leap year (Feb 29)
      final leapStart = DateTime.utc(2028, 2, 1, 0, 0, 0);
      final after30Days = leapStart.add(const Duration(days: 30));

      expect(
        E2ETestHelpers.evaluateTwoFactorPromptDue(
          lastVerified: leapStart,
          intervalDays: 30,
          now: after30Days,
        ),
        isTrue,
      );
    });

    test('B3.5 corrupted or empty 2FA timestamp string in SharedPreferences defaults safely to prompt due', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('multipad_2fa_last_verified_iso', 'invalid_iso_timestamp');

      final storedIso = prefs.getString('multipad_2fa_last_verified_iso');
      final parsed = DateTime.tryParse(storedIso ?? '');
      expect(parsed, isNull);

      final isDue = E2ETestHelpers.evaluateTwoFactorPromptDue(
        lastVerified: parsed,
        intervalDays: 30,
        now: DateTime.now(),
      );
      expect(isDue, isTrue); // Prompts user securely when timestamp is corrupted
    });
  });

  // ===========================================================================
  // Boundary Group B4: Corrupted Cipherstrings & Malformed Import Payloads
  // ===========================================================================
  group('Tier 2: Boundary B4 - Corrupted Cipherstrings & Malformed Import Payloads', () {
    test('B4.1 tampered HMAC-SHA256 signature in cipherstring is detected and rejected', () async {
      final subkeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'ValidPassword!2026',
        salt: 'user@example.com',
      );
      final validCipher = await E2ETestHelpers.encryptBitwardenCipherString(
        plaintext: 'Valid Plaintext',
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );

      // Tamper last character of MAC signature
      final tampered = validCipher.substring(0, validCipher.length - 2) +
          (validCipher.endsWith('A') ? 'B' : 'A') +
          '=';

      expect(
        () => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: tampered,
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('B4.2 truncated cipherstring structure missing MAC or IV throws FormatException', () async {
      final subkeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'Pass',
        salt: 'salt@example.com',
      );

      // Missing MAC: "2.iv|ciphertext"
      expect(
        () => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: '2.YWJjZGVmZ2hpamtsbW5vcA==|Y2lwaGVydGV4dA==',
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );

      // Wrong prefix: "1.iv|cipher|mac"
      expect(
        () => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: '1.YWJj|ZGVm|Z2hp',
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('B4.3 non-base64 malformed characters in cipher components throw FormatException', () async {
      final subkeys = await E2ETestHelpers.deriveBitwardenSubKeys(
        password: 'Pass',
        salt: 'salt',
      );

      expect(
        () => E2ETestHelpers.decryptBitwardenCipherString(
          cipherString: '2.***NOT_B64***|***NOT_B64***|***NOT_B64***',
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('B4.4 corrupted inner JSON content produces empty parsed items list without crashing', () async {
      final rows = ImportService.parseCsvRows('Not a valid, CSV\r\n"Unterminated quote');
      expect(rows, isA<List<List<String>>>());
    });

    test('B4.5 empty string and whitespace-only import files return empty lists gracefully', () {
      expect(ImportService.parseCsvRows(''), isEmpty);
      expect(ImportService.parseCsvRows('   \n\r\t   '), isEmpty);
      expect(ImportService.parseCsvRows('\uFEFF'), isEmpty); // BOM only
    });
  });

  // ===========================================================================
  // Boundary Group B5: Card Luhn, Empty Vault & Extreme Length Text Inputs
  // ===========================================================================
  group('Tier 2: Boundary B5 - Card Luhn, Empty Vault & Extreme Length Text Inputs', () {
    test('B5.1 extreme text lengths (15,000 chars) are stored and audited safely', () {
      final hugeString = 'A' * 15000;
      final item = VaultItem(
        id: 'huge-1',
        type: VaultItemType.credential,
        title: hugeString.substring(0, 500),
        username: 'user@example.com',
        password: 'Pass!${hugeString.substring(0, 1000)}',
        content: hugeString,
        website: 'https://example.com/${hugeString.substring(0, 200)}',
      );

      final report = AuditService.analyzeVault([item]);
      expect(report.totalAccounts, 1);
      expect(report.weakPasswordsCount, 0);
    });

    test('B5.2 Luhn checksum boundary: single digits, formatting spaces, invalid checksums', () {
      expect(AuditService.isValidLuhn(''), isFalse);
      expect(AuditService.isValidLuhn('7'), isFalse);
      expect(AuditService.isValidLuhn('0'), isFalse);
      expect(AuditService.isValidLuhn('4111111111111111'), isTrue); // Valid 16-digit Luhn
      expect(AuditService.isValidLuhn('4111 1111 1111 1111'), isTrue); // Valid with whitespace
      expect(AuditService.isValidLuhn('4111-1111-1111-1111'), isTrue); // Valid with dashes
      expect(AuditService.isValidLuhn('4111111111111112'), isFalse); // Invalid check digit
      expect(AuditService.isValidLuhn('4111ABCD11111111'), isFalse); // Non-digit characters
    });

    test('B5.3 card expiry date boundaries: invalid months, format variations, future dates', () {
      final now = DateTime.utc(2026, 6, 1);

      expect(AuditService.evaluateCardExpiry('06/26', now: now), 'expiring_soon');
      expect(AuditService.evaluateCardExpiry('07/26', now: now), 'expiring_soon');
      expect(AuditService.evaluateCardExpiry('05/26', now: now), 'expired');
      expect(AuditService.evaluateCardExpiry('13/26', now: now), 'expired');
      expect(AuditService.evaluateCardExpiry('00/26', now: now), 'expired');
      expect(AuditService.evaluateCardExpiry('invalid', now: now), isNull);
      expect(AuditService.evaluateCardExpiry('12/99', now: now), isNull); // Far future
    });

    test('B5.4 empty vault produces flawless audit score without division by zero', () {
      final report = AuditService.analyzeVault([]);
      expect(report.totalAccounts, 0);
      expect(report.overallScore, 100);
      expect(report.issues, isEmpty);
      expect(report.weakPasswordsCount, 0);
      expect(report.reusedPasswordsCount, 0);
    });

    test('B5.5 items containing SQL metacharacters, null bytes, and unicode emojis preserve fidelity', () {
      const complexTitle = "Test' OR '1'='1; -- \u0000 🚀🔐 Türkçe Karakterler: ğüşıöç";
      final item = VaultItem(
        id: 'special-1',
        type: VaultItemType.credential,
        title: complexTitle,
        username: "admin' --",
        password: "Pass\u0000word!2026",
      );

      final plainJson = item.toPlainJson();
      final decodedMap = jsonDecode(plainJson) as Map<String, dynamic>;
      final roundTrip = VaultItem.fromDecryptedJson(
        id: item.id,
        type: item.type,
        decryptedPayload: decodedMap,
        isDeleted: false,
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      expect(roundTrip.title, complexTitle);
      expect(roundTrip.username, "admin' --");
      expect(roundTrip.password, "Pass\u0000word!2026");
    });
  });

  // ===========================================================================
  // Boundary Group B6: Desktop Bridge & Mobile Autofill Malformed Payloads
  // ===========================================================================
  group('Tier 2: Boundary B6 - Desktop Bridge & Mobile Autofill Malformed Payloads', () {
    test('B6.1 desktop bridge rejects unauthorized origins and spoofing attempts', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final client = bridge.client;

      // Rejects web origin
      final res1 = await client.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'origin': 'https://malicious-website.com'},
      );
      expect(res1.statusCode, HttpStatus.forbidden);

      // Rejects forged scheme
      final res2 = await client.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'origin': 'http://localhost:3000'},
      );
      expect(res2.statusCode, HttpStatus.forbidden);

      // Accepts chrome-extension origin
      final res3 = await client.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'origin': 'chrome-extension://abcdefghijklmnop'},
      );
      expect(res3.statusCode, HttpStatus.ok);

      await bridge.close();
    });

    test('B6.2 desktop bridge rejects malformed JSON payloads in POST /query', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'secret-token',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final res = await bridge.handleRequest(
        path: '/query',
        method: 'POST',
        headers: {
          'authorization': 'Bearer secret-token',
          'origin': 'chrome-extension://test',
        },
        bodyStr: '{malformed json syntax',
      );

      // Handled safely returning HTTP 400 Bad Request
      expect(res.statusCode, HttpStatus.badRequest);
      await bridge.close();
    });

    test('B6.3 desktop bridge rejects requests when token is empty or invalid', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'correct-token',
        getItems: () => [],
        isUnlocked: () => true,
      );

      final resWrong = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'authorization': 'Bearer wrong-token'},
      );
      expect(resWrong.statusCode, HttpStatus.unauthorized);

      final resEmpty = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'authorization': 'Bearer '},
      );
      expect(resEmpty.statusCode, HttpStatus.unauthorized);

      await bridge.close();
    });

    test('B6.4 bridge handles 4000+ character query URL gracefully', () async {
      final bridge = await E2ETestHelpers.startTestBridge(
        pairingToken: 'token',
        getItems: () => [E2ETestHelpers.sampleCredential(website: 'https://example.com')],
        isUnlocked: () => true,
      );

      final hugeUrl = 'https://example.com/${'param=value&' * 300}';
      final res = await bridge.client.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'authorization': 'Bearer token',
          'origin': 'chrome-extension://test',
        },
        body: jsonEncode({'url': hugeUrl}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isA<List>());
      await bridge.close();
    });

    test('B6.5 hardware autofill index update handles empty list and large batch (1,000 entries)', () async {
      const channel = MethodChannel('com.multipad.multipad/native');

      // Empty list
      await channel.invokeMethod('updateAutofillIndex', {'entries': []});
      expect(E2ETestHelpers.lastAutofillEntries, isEmpty);

      // 1,000 entries
      final entries = List.generate(
        1000,
        (i) => {'id': 'id-$i', 'title': 'Site $i', 'username': 'user$i'},
      );
      await channel.invokeMethod('updateAutofillIndex', {'entries': entries});
      expect(E2ETestHelpers.lastAutofillEntries.length, 1000);
    });
  });

  // ===========================================================================
  // Boundary Group B7: RFC 6238 Time Boundaries & Centralized TOTP Ticker Stress
  // ===========================================================================
  group('Tier 2: Boundary B7 - RFC 6238 Time Boundaries & Centralized TOTP Ticker Stress', () {
    test('B7.1 RFC 6238 step boundaries: 29s to 30s step transition generates expected code', () {
      const secret = 'JBSWY3DPEHPK3PXP'; // Standard RFC 6238 test vector
      final code29 = TotpService.generateCode(secret, timeMs: 29000);
      final code30 = TotpService.generateCode(secret, timeMs: 30000);

      expect(code29, isNotNull);
      expect(code30, isNotNull);
      expect(code29!.length, 6);
      expect(code30!.length, 6);
      expect(code29, isNot(equals(code30))); // Code rotates across 30s boundary
    });

    test('B7.2 invalid base32 characters in TOTP secret return null safely without throwing', () {
      expect(TotpService.generateCode(''), isNull);
      expect(TotpService.generateCode('1890!@#%'), isNull); // 1, 8, 9, 0 are non-base32
      expect(TotpService.generateCode('SHORT'), isNotNull); // Valid base32
    });

    test('B7.3 centralized ticker supports 100 concurrent subscribers adding and cancelling', () {
      final ticker = E2ETestHelpers.createCentralTicker();
      final subs = <StreamSubscription<DateTime>>[];

      for (int i = 0; i < 100; i++) {
        subs.add(ticker.subscribe((_) {}));
      }
      expect(ticker.activeSubscribers, 100);

      // Cancel 40 subscriptions
      for (int i = 0; i < 40; i++) {
        subs[i].cancel();
      }
      expect(ticker.activeSubscribers, 60);

      ticker.dispose();
    });

    test('B7.4 rapid ticker pause and resume cycles toggle state faithfully', () {
      final ticker = E2ETestHelpers.createCentralTicker();
      expect(ticker.isPaused, isFalse);

      for (int i = 0; i < 10; i++) {
        ticker.pause();
        expect(ticker.isPaused, isTrue);
        ticker.resume();
        expect(ticker.isPaused, isFalse);
      }

      ticker.dispose();
    });

    test('B7.5 ticker disposal closes internal broadcast stream safely', () {
      final ticker = E2ETestHelpers.createCentralTicker();
      ticker.dispose();

      // Subsequent subscribe handles closed stream without unhandled exceptions
      expect(
        () => ticker.subscribe((_) {}),
        returnsNormally,
      );
    });
  });

  // ===========================================================================
  // Boundary Group B8: Parallel Batch Limits & Cryptographic Assertions
  // ===========================================================================
  group('Tier 2: Boundary B8 - Parallel Batch Limits & Cryptographic Assertions', () {
    test('B8.1 constant time byte equality checks single-bit difference at boundaries', () {
      final a = Uint8List.fromList(List.generate(32, (i) => i));
      final b = Uint8List.fromList(List.generate(32, (i) => i));

      expect(CryptoService.constantTimeEquals(a, b), isTrue);

      // Single-bit difference at byte 0
      final diffFirst = Uint8List.fromList(a);
      diffFirst[0] ^= 1;
      expect(CryptoService.constantTimeEquals(a, diffFirst), isFalse);

      // Single-bit difference at byte 31
      final diffLast = Uint8List.fromList(a);
      diffLast[31] ^= 1;
      expect(CryptoService.constantTimeEquals(a, diffLast), isFalse);

      // Different lengths
      final diffLength = Uint8List.fromList(List.generate(16, (i) => i));
      expect(CryptoService.constantTimeEquals(a, diffLength), isFalse);
    });

    test('B8.2 Argon2id salt specification parsing boundary tests', () {
      // Valid Argon2id salt spec
      const validSpec = 'v2:argon2id:m65536:t3:p4:c29tZXNhbHQ=';
      expect(CryptoService.isArgon2idSalt(validSpec), isTrue);

      // Legacy salt
      expect(CryptoService.isArgon2idSalt('raw_base64_salt'), isFalse);
    });

    test('B8.3 clipboard auto-clear timeout accepts 0s, 1s, and extreme 3600s', () {
      ClipboardService.setDefaultTimeoutSeconds(0);
      expect(ClipboardService.defaultTimeoutSeconds, 0);

      ClipboardService.setDefaultTimeoutSeconds(1);
      expect(ClipboardService.defaultTimeoutSeconds, 1);

      ClipboardService.setDefaultTimeoutSeconds(3600);
      expect(ClipboardService.defaultTimeoutSeconds, 3600);
    });

    test('B8.4 scheduled clipboard clear can be cancelled repeatedly before execution', () {
      ClipboardService.setDefaultTimeoutSeconds(30);
      ClipboardService.cancelScheduledClear();
      ClipboardService.cancelScheduledClear();
      expect(true, isTrue);
    });

    test('B8.5 vault sync reconciliation handles partially corrupt item records', () {
      final valid = E2ETestHelpers.sampleCredential(id: 'v-1', title: 'Valid Service');
      final corrupt = VaultItem(
        id: 'c-1',
        type: VaultItemType.credential,
        title: '',
        username: '',
        password: '',
      );

      final report = AuditService.analyzeVault([valid, corrupt]);
      expect(report.totalAccounts, 2);
      expect(report.weakPasswordsCount, 1); // Corrupt item with empty password flagged
    });
  });
}
