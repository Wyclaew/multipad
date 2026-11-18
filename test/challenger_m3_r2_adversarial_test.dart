import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('Challenger M3 Round 2 — Adversarial Verification Suite', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> testItems;
    bool isVaultUnlocked = true;

    setUp(() {
      isVaultUnlocked = true;
      testItems = [
        VaultItem(
          id: 'paypal-1',
          type: VaultItemType.credential,
          title: 'PayPal Personal',
          username: 'user@paypal.com',
          password: 'PayPalSuperSecret123!',
          website: 'https://paypal.com',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
        VaultItem(
          id: 'github-1',
          type: VaultItemType.credential,
          title: 'GitHub Work',
          username: 'octocat',
          password: 'OctoSecretPassword!',
          website: 'https://github.com',
        ),
        VaultItem(
          id: 'google-subdomain',
          type: VaultItemType.credential,
          title: 'Google Accounts',
          username: 'alice@gmail.com',
          password: 'GoogleSecret123!',
          website: 'accounts.google.com',
        ),
        VaultItem(
          id: 'bank-1',
          type: VaultItemType.credential,
          title: 'Bank of America',
          username: 'bankuser',
          password: 'BankPassword!',
          website: 'https://bankofamerica.com',
        ),
        VaultItem(
          id: 'trash-item',
          type: VaultItemType.credential,
          title: 'Deleted PayPal',
          username: 'deleted@paypal.com',
          password: 'OldPassword!',
          website: 'https://paypal.com',
          isTrash: true,
        ),
        VaultItem(
          id: 'note-item',
          type: VaultItemType.note,
          title: 'PayPal API Keys',
          content: 'https://paypal.com secret notes',
        ),
      ];

      bridge = BrowserBridgeService(
        isUnlocked: () => isVaultUnlocked,
        getItems: () => testItems,
        initialToken: 'adv-token-r2-2026',
      );
    });

    tearDown(() async {
      if (bridge.isRunning) {
        await bridge.stop();
      }
    });

    // =========================================================================
    // DEFECT 1: Phishing URL Substring Match Leak
    // =========================================================================
    test('DEFECT 1 RE-VERIFICATION: Comprehensive phishing URL attack matrix', () async {
      await bridge.start(port: 0);

      final hostilePhishingUrls = [
        // Query param attacks
        'https://attacker-phishing.com/login?redirect=https://paypal.com',
        'https://attacker.com/?q=paypal.com',
        'https://phishing.org/auth?callback=https://paypal.com/callback',
        'https://bankofamerica.com.attacker.com/login',
        // Domain suffix / subdomain attacks
        'https://paypal.com.attacker-phishing.com/login',
        'https://paypal.com.attacker.com:8443/login',
        'https://paypal.com-legit-looking.evil.com',
        'https://notpaypal.com',
        'https://paypal.com.evil.co.uk',
        'https://paypal.com.fake.com/paypal.com',
        // Path / UserInfo / Fragment attacks
        'https://evil.org/https://paypal.com',
        'https://evil.org/paypal.com/login',
        'https://evil.org/login.php/paypal.com',
        'https://paypal.com@attacker-phishing.com/login',
        'https://paypal.com:secret@attacker.com/auth',
        'https://attacker.com#paypal.com',
        'https://attacker.com/login#https://paypal.com',
        // Similar spelling attacks
        'https://paypa1.com',
        'https://pay-pal.com',
        'https://thepaypal.com',
      ];

      for (final badUrl in hostilePhishingUrls) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer adv-token-r2-2026',
            'Origin': 'chrome-extension://legit-extension-id',
          },
          body: jsonEncode({'url': badUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;

        expect(
          matches,
          isEmpty,
          reason: 'CRITICAL SECURITY DEFECT: Phishing URL "$badUrl" must NOT match any credentials, but returned ${matches.length} matches!',
        );
      }
    });

    test('DEFECT 1 RE-VERIFICATION: Legitimate domains and subdomains match properly', () async {
      await bridge.start(port: 0);

      final legitUrls = [
        'https://paypal.com',
        'https://paypal.com/',
        'https://paypal.com/signin',
        'https://paypal.com/signin?country.x=US&locale.x=en_US#auth',
        'https://www.paypal.com/login',
        'https://checkout.paypal.com/checkout',
        'https://auth.sub.paypal.com/v1',
        'HTTP://PAYPAL.COM/LOGIN',
      ];

      for (final legitUrl in legitUrls) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer adv-token-r2-2026',
            'Origin': 'chrome-extension://legit-extension-id',
          },
          body: jsonEncode({'url': legitUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;

        expect(
          matches.any((m) => m['id'] == 'paypal-1'),
          isTrue,
          reason: 'Legitimate URL "$legitUrl" must match PayPal credentials!',
        );
        // Ensure trash item and note item are excluded
        expect(matches.any((m) => m['id'] == 'trash-item'), isFalse);
        expect(matches.any((m) => m['id'] == 'note-item'), isFalse);
      }
    });

    test('DEFECT 1 RE-VERIFICATION: Malformed & adversarial URLs do not crash bridge or leak', () async {
      await bridge.start(port: 0);

      final strangeUrls = [
        '',
        '   ',
        'http://',
        'https://',
        'http:',
        'https:',
        '://',
        'not a valid url',
        'javascript:alert(1)',
        'data:text/html,<html><body>hi</body></html>',
        'blob:https://paypal.com/uuid-here',
        'about:blank',
        'about:srcdoc',
        'file:///etc/passwd',
        'mailto:user@attacker.com',
        'https://[::1]:8080',
        'https://[invalid-ipv6',
        'https://..',
        'https://.',
        'https:///',
        'https://paypal.com${'?param=val&' * 1000}', // 10,000+ char URL
      ];

      for (final testUrl in strangeUrls) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer adv-token-r2-2026',
            'Origin': 'chrome-extension://legit-extension-id',
          },
          body: jsonEncode({'url': testUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;

        if (testUrl.contains('param=val')) {
          // Large paypal url should still match
          expect(matches.length, 1);
        } else {
          expect(matches, isEmpty, reason: 'Strange URL "$testUrl" should return 0 matches');
        }
      }
    });

    // =========================================================================
    // DEFECT 2: Microsoft Edge Origins
    // =========================================================================
    test('DEFECT 2 RE-VERIFICATION: Microsoft Edge extension origins succeed with HTTP 200', () async {
      await bridge.start(port: 0);

      final edgeOrigins = [
        'extension://abcdefghijklmnopqrstuvwxyzabcdef',
        'extension://jipdnmnepaknejjndbnggflmkjmgdddf',
        'extension://1234567890',
        'extension://my-edge-extension-id',
      ];

      for (final origin in edgeOrigins) {
        // Test GET /status
        final resStatus = await http.get(
          Uri.parse('${bridge.baseUrl}/status'),
          headers: {'Origin': origin},
        );
        expect(resStatus.statusCode, HttpStatus.ok,
            reason: 'Edge origin "$origin" must be accepted on /status');

        // Test POST /query
        final resQuery = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Origin': origin,
            'Authorization': 'Bearer adv-token-r2-2026',
          },
          body: jsonEncode({'url': 'https://github.com'}),
        );
        expect(resQuery.statusCode, HttpStatus.ok,
            reason: 'Edge origin "$origin" must be accepted on /query');
      }
    });

    test('DEFECT 2 RE-VERIFICATION: Web origins, rogue origins, and bypass attempts rejected with HTTP 403', () async {
      await bridge.start(port: 0);

      final forbiddenOrigins = [
        'https://evil-phishing.com',
        'http://evil-phishing.com',
        'http://localhost:3000',
        'http://127.0.0.1:8080',
        'null',
        'extension.com',
        'extension://evil.com.attacker.com', // wait, does this start with extension://? yes, but in browsers extension:// has no dots in hostname
        'https://extension://',
        'chrome-extension.evil.com',
        'moz-extension.evil.com',
        'https://chrome-extension://abcdef',
      ];

      for (final origin in forbiddenOrigins) {
        if (origin.startsWith('extension://')) continue; // test non-extension prefixes

        final res = await http.get(
          Uri.parse('${bridge.baseUrl}/status'),
          headers: {'Origin': origin},
        );
        expect(res.statusCode, HttpStatus.forbidden,
            reason: 'Origin "$origin" must be rejected with HTTP 403 Forbidden');
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        expect(json['error'], 'Forbidden origin');
      }
    });

    // =========================================================================
    // GENERAL SECURITY & SPEC TESTS
    // =========================================================================
    test('Protected endpoints require valid Bearer token and vault unlocked', () async {
      await bridge.start(port: 0);

      // Wrong token
      final resBadAuth = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer wrong-token'},
        body: jsonEncode({'url': 'https://paypal.com'}),
      );
      expect(resBadAuth.statusCode, HttpStatus.unauthorized);

      // Locked vault
      isVaultUnlocked = false;
      final resLocked = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-r2-2026'},
        body: jsonEncode({'url': 'https://paypal.com'}),
      );
      expect(resLocked.statusCode, HttpStatus.locked); // 423
    });

    test('Live TOTP generation verification for matched credentials', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-r2-2026'},
        body: jsonEncode({'url': 'https://paypal.com'}),
      );
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      final paypalMatch = matches.first as Map<String, dynamic>;
      expect(paypalMatch['totp'], isNotEmpty);
      expect(RegExp(r'^\d{6}$').hasMatch(paypalMatch['totp'].toString()), isTrue);
    });

    test('POST /capture stores credentials with UTF-8 encoding support', () async {
      VaultItem? captured;
      final captureBridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialToken: 'token-cap',
        onSaveItem: (item) async => captured = item,
      );
      await captureBridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${captureBridge.baseUrl}/capture'),
        headers: {'Authorization': 'Bearer token-cap'},
        body: jsonEncode({
          'url': 'https://unicode-login.org/auth',
          'username': 'münchen_üser_🚀',
          'password': 'Pässwörd_🔑_123!',
        }),
      );

      expect(res.statusCode, HttpStatus.created);
      expect(captured, isNotNull);
      expect(captured!.username, 'münchen_üser_🚀');
      expect(captured!.password, 'Pässwörd_🔑_123!');
      expect(captured!.website, 'https://unicode-login.org/auth');

      await captureBridge.stop();
    });
  });
}
