import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('BrowserBridgeService Lifecycle & Security', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> testItems;
    bool unlocked = true;

    setUp(() {
      unlocked = true;
      testItems = [];
      bridge = BrowserBridgeService(
        isUnlocked: () => unlocked,
        getItems: () => testItems,
        initialToken: 'test-token-xyz-123',
      );
    });

    tearDown(() async {
      if (bridge.isRunning) {
        await bridge.stop();
      }
    });

    test('binds to ephemeral port on loopback and reports running state', () async {
      expect(bridge.isRunning, isFalse);
      await bridge.start(port: 0);
      expect(bridge.isRunning, isTrue);
      expect(bridge.port, greaterThan(0));
      expect(bridge.baseUrl, startsWith('http://127.0.0.1:'));
      await bridge.stop();
      expect(bridge.isRunning, isFalse);
    });

    test('rejects binding to non-loopback address', () async {
      expect(
        () => bridge.start(port: 0, address: InternetAddress('192.168.1.100')),
        throwsArgumentError,
      );
    });

    test('GET /status and /api/v1/status return correct unlock state and version', () async {
      await bridge.start(port: 0);

      // Unlocked
      final res1 = await http.get(Uri.parse('${bridge.baseUrl}/status'));
      expect(res1.statusCode, 200);
      final json1 = jsonDecode(res1.body) as Map<String, dynamic>;
      expect(json1['status'], 'unlocked');
      expect(json1['version'], '1.2.0');

      // Locked
      unlocked = false;
      final res2 = await http.get(Uri.parse('${bridge.baseUrl}/api/v1/status'));
      expect(res2.statusCode, 200);
      final json2 = jsonDecode(res2.body) as Map<String, dynamic>;
      expect(json2['status'], 'locked');
    });

    test('POST /pair and /api/v1/pair return active pairing token', () async {
      await bridge.start(port: 0);

      final res = await http.post(Uri.parse('${bridge.baseUrl}/pair'));
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['token'], 'test-token-xyz-123');

      bridge.rotatePairingToken();
      final res2 = await http.post(Uri.parse('${bridge.baseUrl}/api/v1/pair'));
      final json2 = jsonDecode(res2.body) as Map<String, dynamic>;
      expect(json2['token'], isNot('test-token-xyz-123'));
    });

    test('token rotation immediately invalidates old token and authorizes new token', () async {
      await bridge.start(port: 0);

      final oldToken = bridge.pairingToken;
      final newToken = bridge.rotatePairingToken();
      expect(newToken, isNot(oldToken));

      // Old token should now be rejected
      final resOld = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer $oldToken'},
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(resOld.statusCode, HttpStatus.unauthorized);

      // New token should be accepted
      final resNew = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer $newToken'},
        body: jsonEncode({'url': 'https://example.com'}),
      );
      expect(resNew.statusCode, HttpStatus.ok);
    });

    test('enforces Origin header security: allows extensions, rejects web origins with HTTP 403', () async {
      await bridge.start(port: 0);

      // Rejects standard web origin
      final resBad = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'https://malicious-website.com'},
      );
      expect(resBad.statusCode, HttpStatus.forbidden);
      expect(jsonDecode(resBad.body)['error'], 'Forbidden origin');

      // Rejects localhost origin
      final resLocal = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'http://localhost:3000'},
      );
      expect(resLocal.statusCode, HttpStatus.forbidden);

      // Allows chrome-extension origin
      final resChrome = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'chrome-extension://abcdefghijklmnopqrstuvwxyz'},
      );
      expect(resChrome.statusCode, HttpStatus.ok);

      // Allows moz-extension origin
      final resMoz = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'moz-extension://abcdefghijklmnopqrstuvwxyz'},
      );
      expect(resMoz.statusCode, HttpStatus.ok);

      // Allows Microsoft Edge extension origin (extension://)
      final resEdge = await http.get(
        Uri.parse('${bridge.baseUrl}/status'),
        headers: {'Origin': 'extension://abcdefghijklmnopqrstuvwxyz'},
      );
      expect(resEdge.statusCode, HttpStatus.ok);
    });

    test('OPTIONS preflight responds with 200 and CORS headers', () async {
      await bridge.start(port: 0);

      final request = http.Request('OPTIONS', Uri.parse('${bridge.baseUrl}/query'));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(response.headers['access-control-allow-methods'], contains('POST'));
    });
  });

  group('BrowserBridgeService Authentication & Vault Locking', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> testItems;
    bool unlocked = true;

    setUp(() {
      unlocked = true;
      testItems = [
        VaultItem(
          id: 'gh-1',
          type: VaultItemType.credential,
          title: 'GitHub Work',
          username: 'alice_gh',
          password: 'PassWord123!',
          website: 'https://github.com/login',
          totpSecret: 'JBSWY3DPEHPK3PXP', // Base32 test secret
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => unlocked,
        getItems: () => testItems,
        initialToken: 'auth-token-456',
      );
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('rejects POST /query and /capture without Bearer token (HTTP 401)', () async {
      await bridge.start(port: 0);

      final resQuery = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(resQuery.statusCode, HttpStatus.unauthorized);
      expect(jsonDecode(resQuery.body)['error'], 'Unauthorized');

      final resCapture = await http.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        body: jsonEncode({
          'url': 'https://github.com',
          'username': 'bob',
          'password': 'pwd',
        }),
      );
      expect(resCapture.statusCode, HttpStatus.unauthorized);
      expect(jsonDecode(resCapture.body)['error'], 'Unauthorized');
    });

    test('rejects POST /query with invalid Bearer token (HTTP 401)', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer wrong-token'},
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(res.statusCode, HttpStatus.unauthorized);
      expect(jsonDecode(res.body)['error'], 'Unauthorized');
    });

    test('returns HTTP 423 Locked when vault is locked for /query and /capture', () async {
      await bridge.start(port: 0);
      unlocked = false; // Lock the vault

      final resQuery = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer auth-token-456',
          'Origin': 'chrome-extension://test',
        },
        body: jsonEncode({'url': 'https://github.com'}),
      );
      expect(resQuery.statusCode, HttpStatus.locked); // 423
      expect(jsonDecode(resQuery.body)['error'], 'Vault is locked');

      final resCapture = await http.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {
          'Authorization': 'Bearer auth-token-456',
          'Origin': 'chrome-extension://test',
        },
        body: jsonEncode({
          'url': 'https://github.com',
          'username': 'bob',
          'password': 'pwd',
        }),
      );
      expect(resCapture.statusCode, HttpStatus.locked); // 423
      expect(jsonDecode(resCapture.body)['error'], 'Vault is locked');
    });
  });

  group('BrowserBridgeService Credential Queries & Live TOTP', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> testItems;

    setUp(() {
      testItems = [
        VaultItem(
          id: 'gh-1',
          type: VaultItemType.credential,
          title: 'GitHub Work',
          username: 'alice_gh',
          password: 'PassWord123!',
          website: 'https://github.com/login',
          totpSecret: 'JBSWY3DPEHPK3PXP', // Base32 test secret
        ),
        VaultItem(
          id: 'note-1',
          type: VaultItemType.note,
          title: 'GitHub Notes',
          content: 'https://github.com notes',
        ),
        VaultItem(
          id: 'trash-1',
          type: VaultItemType.credential,
          title: 'Old GitHub',
          username: 'old_user',
          website: 'https://github.com',
          isTrash: true,
        ),
        VaultItem(
          id: 'aws-1',
          type: VaultItemType.credential,
          title: 'AWS Console',
          username: 'alice_aws',
          password: 'AwsPassword99!',
          website: 'https://signin.aws.amazon.com',
        ),
      ];
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => testItems,
        initialToken: 'token-query',
      );
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('matches credentials by URL and excludes non-credentials & trash', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/api/v1/query'),
        headers: {
          'Authorization': 'Bearer token-query',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': 'https://github.com'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matchList = json['matches'] as List<dynamic>;

      expect(matchList.length, 1);
      final first = matchList.first as Map<String, dynamic>;
      expect(first['id'], 'gh-1');
      expect(first['username'], 'alice_gh');
      expect(first['password'], 'PassWord123!');
      // Live TOTP code should be a 6-digit numeric string
      expect(first['totp'], matches(RegExp(r'^\d{6}$')));
    });

    test('matches credentials case-insensitively with domain substrings', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer token-query',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': 'HTTPS://GITHUB.COM/ORGANIZATIONS/MULTI'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      expect(matches.first['username'], 'alice_gh');
    });

    test('returns empty matches array when no credentials match URL', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer token-query',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': 'https://gitlab.com'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['matches'], isEmpty);
    });

    test('handles 4000+ character query URL gracefully', () async {
      await bridge.start(port: 0);

      final hugeUrl = 'https://github.com/login?${'param=longvalue&' * 300}';
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer token-query',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': hugeUrl}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
    });

    test('strictly rejects phishing URLs containing victim domain in query, path, or suffix', () async {
      await bridge.start(port: 0);

      final phishingUrls = [
        'https://attacker-phishing.com/login?redirect=https://github.com',
        'https://github.com.attacker-phishing.com/login',
        'https://evil.org/https://github.com',
        'https://fake-github.com',
      ];

      for (final badUrl in phishingUrls) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer token-query',
            'Origin': 'chrome-extension://myextension',
          },
          body: jsonEncode({'url': badUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;
        expect(matches, isEmpty, reason: 'URL $badUrl must NOT leak credentials');
      }
    });

    test('rejects generic queries like https:// or empty strings and returns zero matches', () async {
      await bridge.start(port: 0);

      for (final emptyUrl in ['', '   ', 'https://', 'http://', 'http:']) {
        final res = await http.post(
          Uri.parse('${bridge.baseUrl}/query'),
          headers: {
            'Authorization': 'Bearer token-query',
            'Origin': 'chrome-extension://myextension',
          },
          body: jsonEncode({'url': emptyUrl}),
        );

        expect(res.statusCode, HttpStatus.ok);
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final matches = json['matches'] as List<dynamic>;
        expect(matches, isEmpty, reason: 'Generic query "$emptyUrl" must return 0 matches');
      }
    });

    test('matches subdomains of stored website host', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer token-query',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': 'https://api.github.com/v3/auth'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      expect(matches.first['id'], 'gh-1');
    });
  });

  group('BrowserBridgeService Capture & Error Handling', () {
    late BrowserBridgeService bridge;
    Map<String, dynamic>? capturedPayload;
    VaultItem? savedVaultItem;

    setUp(() {
      capturedPayload = null;
      savedVaultItem = null;
      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialToken: 'token-capture',
        onCredentialCaptured: (data) => capturedPayload = data,
        onSaveItem: (item) async => savedVaultItem = item,
      );
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('POST /capture records credential and returns 201 Created', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/capture'),
        headers: {
          'Authorization': 'Bearer token-capture',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({
          'url': 'https://newsite.org/register',
          'username': 'charlie',
          'password': 'CharlieStrongPassword!2026',
        }),
      );

      expect(res.statusCode, HttpStatus.created);
      expect(jsonDecode(res.body)['success'], isTrue);

      expect(capturedPayload, isNotNull);
      expect(capturedPayload!['username'], 'charlie');
      expect(capturedPayload!['password'], 'CharlieStrongPassword!2026');

      expect(savedVaultItem, isNotNull);
      expect(savedVaultItem!.type, VaultItemType.credential);
      expect(savedVaultItem!.username, 'charlie');
      expect(savedVaultItem!.website, 'https://newsite.org/register');
    });

    test('POST /capture succeeds even when onSaveItem is null', () async {
      Map<String, dynamic>? callbackData;
      final bridgeNoSave = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [],
        initialToken: 'token-nosave',
        onCredentialCaptured: (data) => callbackData = data,
      );
      await bridgeNoSave.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridgeNoSave.baseUrl}/capture'),
        headers: {
          'Authorization': 'Bearer token-nosave',
        },
        body: jsonEncode({
          'url': 'https://api.test',
          'username': 'admin',
          'password': 'secretPassword',
        }),
      );

      expect(res.statusCode, HttpStatus.created);
      expect(callbackData, isNotNull);
      expect(callbackData!['username'], 'admin');

      await bridgeNoSave.stop();
    });

    test('rejects malformed JSON payload with HTTP 400 Bad Request', () async {
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer token-capture',
          'Origin': 'chrome-extension://myextension',
        },
        body: '{not a valid json string',
      );

      expect(res.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(res.body)['error'], 'Malformed JSON payload');
    });

    test('returns HTTP 404 for unknown endpoints', () async {
      await bridge.start(port: 0);

      final res = await http.get(Uri.parse('${bridge.baseUrl}/unsupported_route'));
      expect(res.statusCode, HttpStatus.notFound);
    });
  });
}
