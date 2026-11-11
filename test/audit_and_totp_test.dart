import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/totp_service.dart';

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
