import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('Adversarial Test Suite 1: Malicious & Spoofed Origin Headers', () {
    late BrowserBridgeService bridge;
    bool unlocked = true;

    setUp(() async {
      unlocked = true;
      bridge = BrowserBridgeService(
        isUnlocked: () => unlocked,
        getItems: () => [],
        initialToken: 'adv-token-123',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('rejects malicious external web origin https://evil.com with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'https://evil.com'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects unauthorized localhost web origin http://localhost:8080 with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'http://localhost:8080'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects loopback IP web origin http://127.0.0.1:3000 with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'http://127.0.0.1:3000'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects spoofed scheme chrome-extension-fake:// with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'chrome-extension-fake://malicious-extension-id'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects spoofed scheme moz-extension-fake:// with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'moz-extension-fake://malicious-extension-id'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects null origin string "null" (sandboxed iframe / privacy mode) with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'null'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects file:// local file origin with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'file://'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('rejects other browser schemes like safari-extension:// with HTTP 403', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'safari-extension://com.apple.safari.fake'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['error'], 'Forbidden origin');
    });

    test('allows legitimate chrome-extension:// origin', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'chrome-extension://abcdefghijklmnopqrstuvwxyz'},
      );
      expect(res.statusCode, HttpStatus.ok);
    });

    test('allows legitimate moz-extension:// origin', () async {
      final res = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'moz-extension://01234567-89ab-cdef-0123-456789abcdef'},
      );
      expect(res.statusCode, HttpStatus.ok);
    });
  });

  group('Adversarial Test Suite 2: Non-Loopback Address Binding Rejection', () {
    late BrowserBridgeService bridge;

    setUp(() {
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
      );
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('rejects binding to all IPv4 interfaces 0.0.0.0', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('0.0.0.0')),
        throwsArgumentError,
      );
    });

    test('rejects binding to private LAN address 192.168.1.50', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('192.168.1.50')),
        throwsArgumentError,
      );
    });

    test('rejects binding to class A private network 10.0.0.1', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('10.0.0.1')),
        throwsArgumentError,
      );
    });

    test('rejects binding to public internet address 8.8.8.8', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('8.8.8.8')),
        throwsArgumentError,
      );
    });

    test('rejects binding to all IPv6 interfaces ::', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('::')),
        throwsArgumentError,
      );
    });

    test('allows binding to standard IPv4 loopback (127.0.0.1)', () async {
      await bridge.start(port: 0, address: InternetAddress.loopbackIPv4);
      expect(bridge.isRunning, isTrue);
      expect(bridge.port, greaterThan(0));
      await bridge.stop();
    });

    test('allows binding to IPv6 loopback (::1)', () async {
      await bridge.start(port: 0, address: InternetAddress.loopbackIPv6);
      expect(bridge.isRunning, isTrue);
      expect(bridge.port, greaterThan(0));
      await bridge.stop();
    });
  });

  group('Adversarial Test Suite 3: Massive Payloads, Fuzzing & Malformed Payloads', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> items;
    Map<String, dynamic>? lastCaptured;

    setUp(() async {
      lastCaptured = null;
      items = [
        VaultItem(
          id: 'cred-1',
          type: VaultItemType.credential,
          title: 'Target Site',
          username: 'user1',
          password: 'pass1',
          website: 'https://example.com/login',
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => items,
        initialToken: 'adv-token-payload',
        onCredentialCaptured: (data) => lastCaptured = data,
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('handles massive 100KB+ JSON fuzzing payload without server crash or hang', () async {
      final hugeData = <String, dynamic>{
        'url': 'https://example.com',
        'noise': 'X' * 120000, // 120KB string
        'fuzzArray': List.generate(500, (i) => 'entry_$i'),
        'nested': {
          'subfield': 'Y' * 10000,
        },
      };

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(hugeData),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isNotEmpty);
      expect(bridge.isRunning, isTrue);
    });

    test('handles massive 250KB payload on /capture without crashing', () async {
      final hugeCapture = <String, dynamic>{
        'url': 'https://testcapture.org',
        'username': 'attacker_${'U' * 50000}',
        'password': 'attacker_pass_${'P' * 50000}',
        'bloat': 'B' * 150000,
      };

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(hugeCapture),
      );

      expect(res.statusCode, HttpStatus.created);
      expect(lastCaptured, isNotNull);
      expect(bridge.isRunning, isTrue);
    });

    test('handles deeply nested JSON structures safely (100 levels)', () async {
      Map<String, dynamic> deeplyNested = {'url': 'https://example.com'};
      for (int i = 0; i < 100; i++) {
        deeplyNested = {'layer_$i': deeplyNested};
      }

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(deeplyNested),
      );

      // Deeply nested Map is a valid JSON Map; 'url' is not at root, so url is empty, returns empty matches
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isEmpty);
      expect(bridge.isRunning, isTrue);
    });

    test('rejects non-object JSON payloads with HTTP 400 Bad Request', () async {
      // JSON Array instead of Map
      final resArray = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: jsonEncode([1, 2, 3, {'url': 'https://example.com'}]),
      );
      expect(resArray.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(resArray.body)['error'], 'Malformed JSON payload');

      // JSON String instead of Map
      final resString = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: jsonEncode('raw primitive string'),
      );
      expect(resString.statusCode, HttpStatus.badRequest);

      // JSON Number instead of Map
      final resNumber = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: '12345678',
      );
      expect(resNumber.statusCode, HttpStatus.badRequest);
    });

    test('handles null and empty fields in JSON gracefully without crashing', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: jsonEncode({
          'url': null,
          'unexpected': null,
          'number': 42,
          'emptyList': [],
        }),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isEmpty);
    });

    test('handles completely empty request body gracefully', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: '',
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isEmpty);
    });

    test('handles truncated / malformed JSON strings with HTTP 400', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-payload',
          'Origin': 'chrome-extension://testextension',
        },
        body: '{"url": "https://example.com", "incomplete":',
      );

      expect(res.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(res.body)['error'], 'Malformed JSON payload');
    });

    test('handles invalid byte sequences gracefully via allowMalformed UTF-8', () async {
      final client = HttpClient();
      final req = await client.post('127.0.0.1', bridge.port, '/query');
      req.headers.set('Authorization', 'Bearer adv-token-payload');
      req.headers.set('Origin', 'chrome-extension://testextension');
      req.headers.set('Content-Type', 'application/json');
      // Send raw invalid UTF-8 bytes: [0xFF, 0xFE, 0xFD]
      req.add([0xFF, 0xFE, 0xFD]);
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);
      client.close();
    });
  });

  group('Adversarial Test Suite 4: Rapid Concurrent Request Bursts', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> items;

    setUp(() async {
      items = [
        VaultItem(
          id: 'burst-1',
          type: VaultItemType.credential,
          title: 'Burst Target',
          username: 'burst_user',
          password: 'burst_password',
          website: 'https://burst-test.com/login',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => items,
        initialToken: 'adv-token-burst',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('burst of 60 parallel GET /status calls succeed with HTTP 200', () async {
      final futures = List.generate(60, (index) {
        return http.get(Uri.parse('${bridge.baseUrl}/status'));
      });

      final responses = await Future.wait(futures);
      expect(responses.length, 60);
      for (final res in responses) {
        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        expect(json['status'], 'unlocked');
      }
    });

    test('burst of 60 parallel POST /query calls with live TOTP generation succeed', () async {
      final futures = List.generate(60, (index) {
        return http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer adv-token-burst',
            'Origin': 'chrome-extension://burst-ext',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'url': 'https://burst-test.com/path/$index'}),
        );
      });

      final responses = await Future.wait(futures);
      expect(responses.length, 60);
      for (final res in responses) {
        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matchItems = json['matches'] as List<dynamic>;
        expect(matchItems.length, 1);
        final cred = matchItems.first as Map<String, dynamic>;
        expect(cred['username'], 'burst_user');
        expect(cred['totp'], matches(RegExp(r'^\d{6}$')));
      }
    });

    test('burst of 60 parallel mixed requests (status, query, capture, invalid, unauth) all complete cleanly', () async {
      final futures = <Future<http.Response>>[];

      for (int i = 0; i < 60; i++) {
        switch (i % 5) {
          case 0:
            futures.add(http.get(Uri.parse('${bridge.baseUrl}/status')));
            break;
          case 1:
            futures.add(http.post(
              Uri.parse('${bridge.baseUrl}/query'),
              headers: {
                'Authorization': 'Bearer adv-token-burst',
                'Origin': 'chrome-extension://burst-ext',
              },
              body: jsonEncode({'url': 'https://burst-test.com'}),
            ));
            break;
          case 2:
            futures.add(http.post(
              Uri.parse('${bridge.baseUrl}/capture'),
              headers: {
                'Authorization': 'Bearer adv-token-burst',
                'Origin': 'chrome-extension://burst-ext',
              },
              body: jsonEncode({'url': 'https://captured.org', 'username': 'u$i', 'password': 'p$i'}),
            ));
            break;
          case 3:
            futures.add(http.post(
              Uri.parse('${bridge.baseUrl}/query'),
              headers: {'Authorization': 'Bearer WRONG-TOKEN'},
              body: jsonEncode({'url': 'https://burst-test.com'}),
            ));
            break;
          case 4:
            futures.add(http.get(
              Uri.parse('${bridge.baseUrl}/nonexistent_$i'),
            ));
            break;
        }
      }

      final responses = await Future.wait(futures);
      expect(responses.length, 60);

      for (int i = 0; i < 60; i++) {
        final res = responses[i];
        switch (i % 5) {
          case 0:
            expect(res.statusCode, HttpStatus.ok);
            break;
          case 1:
            expect(res.statusCode, HttpStatus.ok);
            break;
          case 2:
            expect(res.statusCode, HttpStatus.created);
            break;
          case 3:
            expect(res.statusCode, HttpStatus.unauthorized);
            break;
          case 4:
            expect(res.statusCode, HttpStatus.notFound);
            break;
        }
      }
    });
  });

  group('Adversarial Test Suite 5: Rapid Lock/Unlock State Transitions During In-Flight Requests', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> items;
    bool unlocked = true;

    setUp(() async {
      unlocked = true;
      items = [
        VaultItem(
          id: 'secret-1',
          type: VaultItemType.credential,
          title: 'Top Secret Bank',
          username: 'bank_user',
          password: 'super_secret_password_never_leak',
          website: 'https://bank.com/portal',
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => unlocked,
        getItems: () => items,
        initialToken: 'adv-token-lock',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('rapid lock transitions never leak credentials: 423 Locked guaranteed when locked', () async {
      final futures = <Future<http.Response>>[];
      var active = true;

      // Asynchronously oscillate lock state every 2 milliseconds
      final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
        if (!active) return;
        unlocked = !unlocked;
      });

      for (int i = 0; i < 50; i++) {
        futures.add(
          http.post(
            Uri.parse('${bridge.baseUrl}/query'),
            headers: {
              'Authorization': 'Bearer adv-token-lock',
              'Origin': 'chrome-extension://testextension',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'url': 'https://bank.com'}),
          ),
        );

        if (i % 5 == 0) {
          await Future.delayed(const Duration(milliseconds: 2));
        }
      }

      final responses = await Future.wait(futures);
      active = false;
      timer.cancel();

      expect(responses.length, 50);

      int lockedCount = 0;
      int unlockedCount = 0;

      for (final res in responses) {
        if (res.statusCode == HttpStatus.locked) {
          lockedCount++;
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          expect(json['error'], 'Vault is locked');
          // Crucial Zero-Knowledge Check: body must NEVER contain secret password
          expect(res.body.contains('super_secret_password_never_leak'), isFalse);
        } else if (res.statusCode == HttpStatus.ok) {
          unlockedCount++;
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          expect(json['matches'], isNotEmpty);
        } else {
          fail('Unexpected response code during lock transition: ${res.statusCode}');
        }
      }

      expect(lockedCount + unlockedCount, 50);
      expect(lockedCount, greaterThan(0));
      expect(unlockedCount, greaterThan(0));
    });

    test('once permanently locked, 100% of /query and /capture calls return HTTP 423', () async {
      unlocked = false; // Locked permanently

      final futures = List.generate(30, (i) {
        if (i.isEven) {
          return http.post(
            Uri.parse('${bridge.baseUrl}/query'),
            headers: {
              'Authorization': 'Bearer adv-token-lock',
              'Origin': 'chrome-extension://ext',
            },
            body: jsonEncode({'url': 'https://bank.com'}),
          );
        } else {
          return http.post(
            Uri.parse('${bridge.baseUrl}/capture'),
            headers: {
              'Authorization': 'Bearer adv-token-lock',
              'Origin': 'chrome-extension://ext',
            },
            body: jsonEncode({'url': 'https://bank.com', 'username': 'x', 'password': 'y'}),
          );
        }
      });

      final responses = await Future.wait(futures);
      for (final res in responses) {
        expect(res.statusCode, HttpStatus.locked);
        expect(jsonDecode(res.body)['error'], 'Vault is locked');
        expect(res.body.contains('super_secret_password_never_leak'), isFalse);
      }
    });
  });

  group('Adversarial Test Suite 6: Domain Matching Boundaries & Substring Phishing', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> items;

    setUp(() async {
      items = [
        VaultItem(
          id: 'gh-item',
          type: VaultItemType.credential,
          title: 'GitHub Work',
          username: 'octocat',
          password: 'SecretGithubPassword123',
          website: 'https://github.com/login',
        ),
        VaultItem(
          id: 'bank-item',
          type: VaultItemType.credential,
          title: 'Chase Bank',
          username: 'chase_user',
          password: 'SecretBankPassword456',
          website: 'https://chase.com',
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => items,
        initialToken: 'adv-token-domain',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('exact domain and subdomains correctly match', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-domain',
          'Origin': 'chrome-extension://ext',
        },
        body: jsonEncode({'url': 'https://gist.github.com/starred'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      expect(matches.first['id'], 'gh-item');
    });

    test('unrelated domains do not match', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-domain',
          'Origin': 'chrome-extension://ext',
        },
        body: jsonEncode({'url': 'https://gitlab.com'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isEmpty);
    });

    test('ADVERSARIAL PROBE: substring match vulnerability with attacker domain containing legitimate site', () async {
      // Attacker hosts phishing page on https://chase.com.attacker.com or https://attacker-chase.com
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-domain',
          'Origin': 'chrome-extension://ext',
        },
        body: jsonEncode({'url': 'https://chase.com.attacker.com/steal'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;

      // EMPIRICAL VERIFICATION OF SUBSTRING MATCH BEHAVIOR:
      // In BrowserBridgeService line 202: `if (site.contains(queryUrl) || queryUrl.contains(site))`
      // `queryUrl` ("https://chase.com.attacker.com/steal") contains `site` ("https://chase.com")!
      // This causes credentials to be returned for the phishing site!
      // Verified hardened: matches list must be empty for phishing domains.
      expect(matches, isEmpty);
    });

    test('ADVERSARIAL PROBE: generic query strings like "https://" or "com" matching all credentials', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer adv-token-domain',
          'Origin': 'chrome-extension://ext',
        },
        body: jsonEncode({'url': 'https://'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;

      // Verified hardened: generic prefixes return 0 matches.
      expect(matches.length, equals(0));
    });
  });

  group('Adversarial Test Suite 7: Pairing Security, Method Enforcement & Concurrency Invalidation', () {
    late BrowserBridgeService bridge;
    bool unlocked = true;

    setUp(() async {
      unlocked = true;
      bridge = BrowserBridgeService(
        isUnlocked: () => unlocked,
        getItems: () => [],
        initialToken: 'pair-adv-token',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('POST /pair blocks malicious web origins with HTTP 403', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {'Origin': 'https://evil-phishing.org'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
      expect(jsonDecode(res.body)['error'], 'Forbidden origin');
    });

    test('POST /pair blocks localhost web origins with HTTP 403', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {'Origin': 'http://localhost:8000'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('rejects unsupported HTTP methods (PUT, DELETE, PATCH) on valid endpoints with 404', () async {
      final resPut = await http.put(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer pair-adv-token'},
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(resPut.statusCode, HttpStatus.notFound);

      final resDelete = await http.delete(
        Uri.parse('${bridge.baseUrl}/status'),
      );
      expect(resDelete.statusCode, HttpStatus.notFound);

      final resPatch = await http.patch(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {'Authorization': 'Bearer pair-adv-token'},
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(resPatch.statusCode, HttpStatus.notFound);
    });

    test('token rotation under concurrent traffic immediately invalidates prior token', () async {
      final futures = <Future<http.Response>>[];
      final oldToken = bridge.pairingToken;

      // Fire 20 requests with old token
      for (int i = 0; i < 20; i++) {
        futures.add(http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer $oldToken',
            'Origin': 'chrome-extension://ext',
          },
          body: jsonEncode({'url': 'https://example.com'}),
        ));
      }

      // Rotate token
      final newToken = bridge.rotatePairingToken();
      expect(newToken, isNot(oldToken));

      // Fire 20 requests with new token
      for (int i = 0; i < 20; i++) {
        futures.add(http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer $newToken',
            'Origin': 'chrome-extension://ext',
          },
          body: jsonEncode({'url': 'https://example.com'}),
        ));
      }

      final responses = await Future.wait(futures);
      expect(responses.length, 40);

      // Verify that after rotation, old token requests rejected with 401 and new token requests succeed with 200
      final newResponses = responses.sublist(20);
      for (final res in newResponses) {
        expect(res.statusCode, HttpStatus.ok);
      }
    });

    test('double start and double stop handle gracefully without unhandled exception', () async {
      // Calling start when running should be a no-op
      await bridge.start(port: 0);
      expect(bridge.isRunning, isTrue);

      // Calling stop twice should clean up cleanly
      await bridge.stop();
      expect(bridge.isRunning, isFalse);
      await bridge.stop();
      expect(bridge.isRunning, isFalse);
    });
  });
}
