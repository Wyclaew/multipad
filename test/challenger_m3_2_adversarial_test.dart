import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('BrowserBridgeService Adversarial & Edge Case Probes', () {
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
        ),
        VaultItem(
          id: 'punycode-1',
          type: VaultItemType.credential,
          title: 'Russian IDN',
          username: 'ivan',
          password: 'PasswordPunycode1!',
          website: 'https://xn--e1afmkfd.xn--p1ai', // пример.рф
        ),
        VaultItem(
          id: 'munchen-1',
          type: VaultItemType.credential,
          title: 'München City',
          username: 'hans',
          password: 'PasswordMunchen1!',
          website: 'https://xn--mnchen-3ya.de', // münchen.de
        ),
        VaultItem(
          id: 'ipv4-port8080',
          type: VaultItemType.credential,
          title: 'Internal Router Port 8080',
          username: 'admin',
          password: 'RouterPassword8080!',
          website: 'http://192.168.1.1:8080',
        ),
        VaultItem(
          id: 'ipv6-portal',
          type: VaultItemType.credential,
          title: 'IPv6 Portal',
          username: 'ipv6user',
          password: 'IPv6Password!',
          website: 'http://[2001:db8::1]:9000',
        ),
        VaultItem(
          id: 'deep-subdomain',
          type: VaultItemType.credential,
          title: 'Deep Subdomain Service',
          username: 'deepuser',
          password: 'DeepPassword!',
          website: 'https://a.b.c.internal.bank.com',
        ),
        VaultItem(
          id: 'generic-domain',
          type: VaultItemType.credential,
          title: 'Generic Domain Item',
          username: 'genericuser',
          password: 'GenericPassword!',
          website: 'com', // Broad string entered by user
        ),
      ];

      bridge = BrowserBridgeService(
        isUnlocked: () => isVaultUnlocked,
        getItems: () => testItems,
        initialToken: 'adv-token-999',
      );
    });

    tearDown(() async {
      if (bridge.isRunning) {
        await bridge.stop();
      }
    });

    test('PROBE 1: Phishing query substring leak (CRITICAL)', () async {
      await bridge.start(port: 0);

      // Scenario: Victim visits an attacker/phishing website that puts the victim domain in the URL path or query
      final attackerUrls = [
        'https://attacker-phishing.com/login?redirect=https://paypal.com',
        'https://paypal.com.attacker-phishing.com/login',
        'https://evil.org/https://paypal.com',
      ];

      for (final attackerUrl in attackerUrls) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer adv-token-999',
            'Origin': 'chrome-extension://legit-extension',
          },
          body: jsonEncode({'url': attackerUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;

        // If the query returns PayPal credentials to the attacker URL, this is an empirical match leak!
        print('Attacker URL: $attackerUrl -> matches count: ${matches.length}');
        for (final m in matches) {
          print('   LEAKED ITEM: ${m['title']} (${m['username']})');
        }
      }
    });

    test('PROBE 2: Trailing slashes and query strings on legit domain', () async {
      await bridge.start(port: 0);

      // Query with trailing slash
      final res1 = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'https://paypal.com/'}),
      );
      expect(res1.statusCode, HttpStatus.ok);
      final json1 = jsonDecode(res1.body) as Map<String, dynamic>;
      final matches1 = json1['matches'] as List<dynamic>;
      expect(matches1.any((m) => m['id'] == 'paypal-1'), isTrue,
          reason: 'Should match with trailing slash');

      // Query with query string and hash
      final res2 = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'https://paypal.com/signin?country.x=US&locale.x=en_US#auth'}),
      );
      expect(res2.statusCode, HttpStatus.ok);
      final json2 = jsonDecode(res2.body) as Map<String, dynamic>;
      final matches2 = json2['matches'] as List<dynamic>;
      expect(matches2.any((m) => m['id'] == 'paypal-1'), isTrue,
          reason: 'Should match with complex query and hash');
    });

    test('PROBE 3: Punycode & IDN domain matching', () async {
      await bridge.start(port: 0);

      // Query using encoded punycode
      final res1 = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'https://xn--e1afmkfd.xn--p1ai/auth'}),
      );
      expect(res1.statusCode, HttpStatus.ok);
      final json1 = jsonDecode(res1.body) as Map<String, dynamic>;
      final matches1 = json1['matches'] as List<dynamic>;
      expect(matches1.any((m) => m['id'] == 'punycode-1'), isTrue,
          reason: 'Punycode encoded URL should match punycode website');

      // Query using Unicode IDN (browser address bar sometimes passes decoded unicode)
      final res2 = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'https://münchen.de/portal'}),
      );
      expect(res2.statusCode, HttpStatus.ok);
      final json2 = jsonDecode(res2.body) as Map<String, dynamic>;
      final matches2 = json2['matches'] as List<dynamic>;
      print('Unicode München query matches: ${matches2.length}');
      // Does 'https://münchen.de' match stored 'https://xn--mnchen-3ya.de'?
      final munchenMatched = matches2.any((m) => m['id'] == 'munchen-1');
      print('Munchen matched: $munchenMatched');
    });

    test('PROBE 4: IPv4 & IPv6 with port isolation', () async {
      await bridge.start(port: 0);

      // Query same IP but DIFFERENT port: 192.168.1.1:9090 vs stored 192.168.1.1:8080
      final resPortDiff = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'http://192.168.1.1:9090/status'}),
      );
      expect(resPortDiff.statusCode, HttpStatus.ok);
      final jsonDiff = jsonDecode(resPortDiff.body) as Map<String, dynamic>;
      final matchesDiff = jsonDiff['matches'] as List<dynamic>;
      print('Port 9090 query against port 8080 item matches count: ${matchesDiff.length}');
      // Domain matching strips port, so it matches on host 192.168.1.1!
      if (matchesDiff.any((m) => m['id'] == 'ipv4-port8080')) {
        print('OBSERVATION: Port numbers are stripped during host comparison, cross-matching different ports on same IP/host.');
      }

      // IPv6 query
      final resIpv6 = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'http://[2001:db8::1]:9000/login'}),
      );
      expect(resIpv6.statusCode, HttpStatus.ok);
      final jsonIpv6 = jsonDecode(resIpv6.body) as Map<String, dynamic>;
      final matchesIpv6 = jsonIpv6['matches'] as List<dynamic>;
      print('IPv6 exact query matches count: ${matchesIpv6.length}');
      expect(matchesIpv6.any((m) => m['id'] == 'ipv6-portal'), isTrue);
    });

    test('PROBE 5: Broad/generic domain item blast radius', () async {
      await bridge.start(port: 0);

      // User saved "com" as website
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer adv-token-999'},
        body: jsonEncode({'url': 'https://bankofamerica.com/login'}),
      );
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      print('bankofamerica.com query matches count: ${matches.length}');
      final genericMatched = matches.any((m) => m['id'] == 'generic-domain');
      print('Generic "com" matched bankofamerica.com: $genericMatched');
    });

    test('PROBE 6: POST /pair unauthenticated token disclosure', () async {
      await bridge.start(port: 0);

      // Any caller without auth header or user confirmation gets the active token
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {
          'Origin': 'chrome-extension://unauthorized-attacker-extension-id',
        },
      );
      expect(res.statusCode, HttpStatus.ok);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['token'], 'adv-token-999');
      print('CONFIRMED: /pair returns active pairing token without user interaction or approval!');
    });

    test('PROBE 7: Edge extension origin support vs rejection', () async {
      await bridge.start(port: 0);

      // Microsoft Edge extensions have origin starting with 'extension://'
      final resEdge = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'extension://abcdefghijklmnopabcdefghijklmnop'},
      );
      print('Edge extension origin status code: ${resEdge.statusCode}');
      // Edge extensions have origin starting with 'extension://' and are accepted
      expect(resEdge.statusCode, HttpStatus.ok,
          reason: 'Bridge accepts Edge extension:// origin');
    });

    test('PROBE 8: WebSocket upgrade attempt', () async {
      await bridge.start(port: 0);

      try {
        final socket = await WebSocket.connect('ws://127.0.0.1:${bridge.port}/ws');
        print('WebSocket connected successfully: $socket');
        await socket.close();
      } catch (e) {
        print('WebSocket connection failed as expected: $e');
        expect(e, isNotNull);
      }
    });
  });
}
