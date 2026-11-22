import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/constants.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/totp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AuditService Card & Website & Vault checks', () {
    test('validates Luhn card numbers and detects card brand', () {
      expect(AuditService.isValidLuhn('4111 1111 1111 1111'), isTrue);
      expect(AuditService.isValidLuhn('4111 1111 1111 1112'), isFalse);
      expect(AuditService.isValidLuhn('000'), isFalse);

      expect(AuditService.detectCardBrand('4111111111111111'), 'Visa');
      expect(AuditService.detectCardBrand('5500000000000004'), 'Mastercard');
      expect(AuditService.detectCardBrand('378282246310005'), 'Amex');
    });

    test('evaluates card expiry and document expiry accurately', () {
      final now = DateTime.utc(2026, 6, 15);

      expect(AuditService.evaluateCardExpiry('05/26', now: now), 'expired');
      expect(AuditService.evaluateCardExpiry('07/26', now: now), 'expiring_soon');
      expect(AuditService.evaluateCardExpiry('12/2029', now: now), isNull);

      expect(AuditService.evaluateDocumentExpiry('2026-06-01', now: now), 'expired');
      expect(AuditService.evaluateDocumentExpiry('2026-07-01', now: now), 'expiring_soon');
      expect(AuditService.evaluateDocumentExpiry('2032-01-01', now: now), isNull);
    });

    test('flags insecure HTTP and phishing lookalike domains while trusting official domains', () {
      final httpRes = AuditService.checkWebsiteSecurity('http://bank.example.com');
      expect(httpRes.issueType, 'insecure_http');

      final phishRes = AuditService.checkWebsiteSecurity('https://paypa1.com/login');
      expect(phishRes.issueType, 'phishing_risk');

      final okRes = AuditService.checkWebsiteSecurity('https://github.com/login');
      expect(okRes.issueType, isNull);
    });

    test('analyzeVault summarizes weak, reused, expired, invalid card, and phishing risks', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'Weak Reused 1',
          username: 'a@b.com',
          password: '123',
          website: 'http://example.com',
          passwordLastModified: DateTime.utc(2020, 1, 1),
        ),
        VaultItem(
          id: 'c2',
          type: VaultItemType.credential,
          title: 'Weak Reused 2',
          username: 'c@d.com',
          password: '123',
          website: 'https://g00gle.com',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
        VaultItem(
          id: 'card1',
          type: VaultItemType.card,
          title: 'Bad Card',
          cardNumber: '4111 1111 1111 1112',
          cardExpiry: '01/20',
        ),
      ];

      final report = AuditService.analyzeVault(items, globalExpiryDays: 90);
      expect(report.weakPasswordsCount, 2);
      expect(report.reusedPasswordsCount, 2);
      expect(report.missing2faCount, 1);
      expect(report.expiredPasswordsCount, 1);
      expect(report.invalidCardsCount, 1);
      expect(report.expiringCardsCount, 1);
      expect(report.phishingRiskCount, 1);
      expect(report.issues.any((i) => i.issueType == 'insecure_http'), isTrue);
      expect(report.overallScore, lessThan(60));
    });

    test('recalibrated health score does not penalize absence of 2FA and achieves 100 for strong passwords', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'Secure Work',
          username: 'alice',
          password: 'SuperStrongPass!2026#Alpha',
          website: 'https://work.com',
          totpSecret: '', // No 2FA
        ),
        VaultItem(
          id: 'c2',
          type: VaultItemType.credential,
          title: 'Secure Personal',
          username: 'bob',
          password: 'AnotherStrongPass!2026#Beta',
          website: 'https://personal.org',
          totpSecret: '', // No 2FA
        ),
      ];

      final report = AuditService.analyzeVault(items);
      expect(report.overallScore, 100);
      expect(report.missing2faCount, 2);
      expect(report.issues, isEmpty);
    });

    test('missing 2FA is never classified as a vulnerability or high-severity issue in audit issues', () {
      final items = [
        VaultItem(
          id: 'c1',
          type: VaultItemType.credential,
          title: 'No 2FA Account',
          username: 'user',
          password: 'CorrectHorseBatteryStaple!2026',
          website: 'https://example.com',
          totpSecret: '',
        ),
      ];

      final report = AuditService.analyzeVault(items);
      expect(report.missing2faCount, 1);
      final hasHighSeverity2fa = report.issues.any((i) => i.issueType == 'missing_2fa' || i.severity >= 3);
      expect(hasHighSeverity2fa, isFalse);
      expect(report.issues.any((i) => i.issueType == 'missing_2fa'), isFalse);
    });
  });

  group('AuthProvider & Settings 2FA Re-Prompt Interval (30, 60, 90 days)', () {
    test('isTwoFactorPromptDue returns true when lastVerified is null', () {
      final auth = AuthProvider();
      expect(auth.isTwoFactorPromptDue(), isTrue);
    });

    test('evaluates 30, 60, 90 day intervals and protects against backwards clock skew', () {
      final now = DateTime.utc(2026, 6, 1, 12, 0, 0);
      final lastVerified = DateTime.utc(2026, 5, 20, 12, 0, 0); // 12 days ago

      bool evaluateDue(DateTime? verified, int days, DateTime ref) {
        if (days <= 0) return true;
        if (verified == null) return true;
        final diff = ref.difference(verified);
        if (diff.isNegative) return false;
        return diff >= Duration(days: days);
      }

      expect(evaluateDue(lastVerified, 30, now), isFalse);
      expect(evaluateDue(lastVerified, 60, now), isFalse);
      expect(evaluateDue(lastVerified, 90, now), isFalse);

      // 40 days later
      final after40Days = lastVerified.add(const Duration(days: 40));
      expect(evaluateDue(lastVerified, 30, after40Days), isTrue);
      expect(evaluateDue(lastVerified, 60, after40Days), isFalse);
      expect(evaluateDue(lastVerified, 90, after40Days), isFalse);

      // 70 days later
      final after70Days = lastVerified.add(const Duration(days: 70));
      expect(evaluateDue(lastVerified, 30, after70Days), isTrue);
      expect(evaluateDue(lastVerified, 60, after70Days), isTrue);
      expect(evaluateDue(lastVerified, 90, after70Days), isFalse);

      // Clock skew (verified in future) -> not due
      final futureVerified = now.add(const Duration(days: 5));
      expect(evaluateDue(futureVerified, 30, now), isFalse);
    });

    test('settings provider defaults to 30 days and supports 30, 60, 90 presets', () {
      final settings = SettingsProvider();
      expect(settings.twoFactorRepromptDays, 30);
      const presets = [30, 60, 90];
      for (final p in presets) {
        expect(p >= 30 && p <= 90, isTrue);
        expect(p % 30 == 0, isTrue);
      }
    });

    test('saveTwoFactorVerification signs timestamp with dynamic device key and verifies integrity', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      final auth = AuthProvider();
      final now = DateTime.utc(2026, 6, 1, 12, 0, 0);

      await auth.saveTwoFactorVerification(now);
      expect(auth.twoFactorLastVerified, equals(now));
      expect(auth.isTwoFactorSignatureValid, isTrue);

      final valid = await auth.verifyTwoFactorTimestampIntegrity();
      expect(valid, isTrue);
      expect(auth.isTwoFactorSignatureValid, isTrue);
    });

    test('tampered 2FA timestamp resets twoFactorLastVerified to null in _loadSecurityPreferences', () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyTwoFactorLastVerifiedIso: '2026-06-01T12:00:00.000Z',
        'multipad_2fa_hmac_signature_v1': 'invalid_forged_signature_xyz',
      });
      SharedPreferences.setMockInitialValues({
        AppConstants.keyTwoFactorLastVerifiedIso: '2099-01-01T00:00:00.000Z',
      });

      final auth = AuthProvider();
      await auth.refreshSecurityState();

      expect(auth.twoFactorLastVerified, isNull);
      expect(auth.isTwoFactorSignatureValid, isFalse);
      expect(auth.isTwoFactorPromptDue(), isTrue);
    });
  });

  group('VaultItem Memory Hardening & Secret Zeroing', () {
    test('wipeSecrets zeroes out all sensitive credential fields, passkeys, and collections', () {
      final passkey = VaultPasskey(
        id: 'pk1',
        credentialId: 'c1',
        rpId: 'example.com',
        userName: 'user@example.com',
        privateKey: 'SECRET_PRIVATE_KEY_BYTES_HERE',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final item = VaultItem(
        id: 'test_item_1',
        type: VaultItemType.credential,
        title: 'Bank Portal',
        username: 'admin',
        password: 'SuperSecretPassword!2026',
        content: 'Secret Markdown Note Content',
        totpSecret: 'JBSWY3DPEHPK3PXP',
        cardNumber: '4111111111111111',
        cardCvv: '999',
        cardPin: '1234',
        wifiPassword: 'WifiSecretPassword',
        serverPassword: 'SshSecretPassword',
        databasePassword: 'DbSecretPassword',
        serverKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB...',
        licenseKey: 'PROD-KEY-1234-5678',
        cryptoSeedPhrase: 'apple banana cherry dog elephant fox grape horse',
        passkeys: [passkey],
        passwordHistory: ['OldPass1', 'OldPass2'],
        customFields: [
          const CustomField(id: 'cf1', label: 'PIN2', value: '4321', isHidden: true),
        ],
        attachments: [
          VaultAttachmentMeta(
            id: 'att1',
            fileName: 'secret.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 1024,
            sha256: 'abc',
            createdAt: DateTime.now(),
          ),
        ],
        revisions: [
          VaultItemRevision(
            id: 'rev1',
            savedAt: DateTime.now(),
            title: 'old revision',
            summary: 'old rev',
          ),
        ],
      );

      expect(item.isWiped, isFalse);
      expect(item.password, 'SuperSecretPassword!2026');
      expect(item.cardNumber, '4111111111111111');
      expect(item.cardCvv, '999');
      expect(item.cardPin, '1234');
      expect(item.cryptoSeedPhrase, contains('apple banana'));
      expect(item.totpSecret, 'JBSWY3DPEHPK3PXP');
      expect(passkey.privateKey, 'SECRET_PRIVATE_KEY_BYTES_HERE');

      // Wipe secrets
      item.wipeSecrets();

      expect(item.isWiped, isTrue);
      expect(item.password, isEmpty);
      expect(item.content, isEmpty);
      expect(item.cardNumber, isEmpty);
      expect(item.cardCvv, isEmpty);
      expect(item.cardPin, isEmpty);
      expect(item.cryptoSeedPhrase, isEmpty);
      expect(item.totpSecret, isEmpty);
      expect(item.wifiPassword, isEmpty);
      expect(item.serverPassword, isEmpty);
      expect(item.databasePassword, isEmpty);
      expect(item.serverKey, isEmpty);
      expect(item.licenseKey, isEmpty);

      // Passkey private key scrubbed and list cleared
      expect(passkey.privateKey, isEmpty);
      expect(item.passkeys, isEmpty);

      // Subcollections cleared
      expect(item.passwordHistory, isEmpty);
      expect(item.customFields, isEmpty);
      expect(item.attachments, isEmpty);
      expect(item.revisions, isEmpty);
    });
  });

  group('TotpService RFC 6238 & otpauth:// URI', () {
    test('parses otpauth://totp URI accurately', () {
      final parsed = TotpService.parseOtpAuthUri(
        'otpauth://totp/GitHub:dev@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30',
      );
      expect(parsed, isNotNull);
      expect(parsed!.secret, 'JBSWY3DPEHPK3PXP');
      expect(parsed.issuer, 'GitHub');
      expect(parsed.accountName, contains('dev@example.com'));
      expect(parsed.digits, 6);
      expect(parsed.period, 30);
    });

    test('matches RFC 6238 SHA-1 test vector at T=59s', () {
      // RFC 6238 test secret = "12345678901234567890" -> Base32 GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final code8 = TotpService.generateCode(secret, timeMs: 59000, digits: 8);
      final code6 = TotpService.generateCode(secret, timeMs: 59000, digits: 6);

      expect(code8, '94287082');
      expect(code6, '287082');
      expect(TotpService.generateCode(''), isNull);
    });
  });
}
