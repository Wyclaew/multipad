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
      expect(json1['version'], '1.4.0');

      // Locked
      unlocked = false;
      final res2 = await http.get(Uri.parse('${bridge.baseUrl}/api/v1/status'));
      expect(res2.statusCode, 200);
      final json2 = jsonDecode(res2.body) as Map<String, dynamic>;
      expect(json2['status'], 'locked');
    });

    test('POST /pair and /api/v1/pair require valid pairing PIN and extension origin', () async {
      await bridge.start(port: 0);

      // Rejects without pairing code with HTTP 401
      final resNoCode = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {'Origin': 'chrome-extension://myextension'},
      );
      expect(resNoCode.statusCode, HttpStatus.unauthorized);

      // Rejects without extension origin with HTTP 403
      final resNoOrigin = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        body: jsonEncode({'code': bridge.pairingCode}),
      );
      expect(resNoOrigin.statusCode, HttpStatus.forbidden);

      // Succeeds with valid code and extension origin
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/pair'),
        headers: {'Origin': 'chrome-extension://myextension'},
        body: jsonEncode({'code': bridge.pairingCode}),
      );
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['token'], 'test-token-xyz-123');

      bridge.rotatePairingToken();
      final res2 = await http.post(
        Uri.parse('${bridge.baseUrl}/api/v1/pair'),
        headers: {'Origin': 'chrome-extension://myextension'},
        body: jsonEncode({'code': bridge.pairingCode}),
      );
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

    test('POST /capture deduplicates credential for same domain and username', () async {
      final existing = VaultItem(
        id: 'existing-id-1',
        type: VaultItemType.credential,
        title: 'example.com',
        website: 'https://example.com/login',
        username: 'alice',
        password: 'OldPassword123!',
      );
      final activeList = [existing];
      VaultItem? saved;

      final dedupBridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => activeList,
        initialToken: 'token-dedup',
        onSaveItem: (item) async => saved = item,
      );
      await dedupBridge.start(port: 0);

      // Same password -> no duplicate item added
      final resSame = await http.post(
        Uri.parse('${dedupBridge.baseUrl}/capture'),
        headers: {'Authorization': 'Bearer token-dedup'},
        body: jsonEncode({
          'url': 'https://example.com/login',
          'username': 'alice',
          'password': 'OldPassword123!',
        }),
      );
      expect(resSame.statusCode, HttpStatus.created);
      expect(saved, isNull);

      // Changed password -> updates existing item preserving id
      final resUpdated = await http.post(
        Uri.parse('${dedupBridge.baseUrl}/capture'),
        headers: {'Authorization': 'Bearer token-dedup'},
        body: jsonEncode({
          'url': 'https://example.com/login',
          'username': 'alice',
          'password': 'NewPassword456!',
        }),
      );
      expect(resUpdated.statusCode, HttpStatus.created);
      expect(saved, isNotNull);
      expect(saved!.id, 'existing-id-1');
      expect(saved!.password, 'NewPassword456!');

      await dedupBridge.stop();
    });

    test('query returns empty string for totp if code generation fails, never leaking raw secret', () async {
      final badTotpItem = VaultItem(
        id: 'bad-totp-1',
        type: VaultItemType.credential,
        title: 'Bad TOTP',
        website: 'https://badseed.com',
        username: 'user',
        password: 'pass',
        totpSecret: 'INVALID_BASE32_!@#\$%^&*()',
      );
      final totpBridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => [badTotpItem],
        initialToken: 'token-bad-totp',
      );
      await totpBridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${totpBridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer token-bad-totp'},
        body: jsonEncode({'url': 'https://badseed.com'}),
      );
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;
      expect(matches.length, 1);
      expect(matches.first['totp'], '');
      expect(matches.first['totp'], isNot(badTotpItem.totpSecret));

      await totpBridge.stop();
    });

    test('enforces 256 KB maximum request body size limit (DoS protection)', () async {
      await bridge.start(port: 0);

      // Payload > 256 KB
      final hugeData = 'a' * (257 * 1024);
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {'Authorization': 'Bearer test-token-xyz-123'},
        body: jsonEncode({'url': 'https://example.com', 'padding': hugeData}),
      );
      expect(res.statusCode, HttpStatus.requestEntityTooLarge); // 413
    });

    test('rejects DNS rebinding / unauthorized Host header with HTTP 403', () async {
      await bridge.start(port: 0);

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('${bridge.baseUrl}/status'));
      request.headers.set('Host', 'evil.attacker.com:48292');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.forbidden);
      client.close();
    });

    test('returns HTTP 404 for unknown endpoints', () async {
      await bridge.start(port: 0);

      final res = await http.get(Uri.parse('${bridge.baseUrl}/unsupported_route'));
      expect(res.statusCode, HttpStatus.notFound);
    });
  });

  group('BrowserBridgeService eTLD+1 Domain Matching (Feature 12)', () {
    test('extractETldPlusOne correctly resolves root domains for standard and ccTLD hosts', () {
      // Standard gTLDs
      expect(BrowserBridgeService.extractETldPlusOne('github.com'), 'github.com');
      expect(BrowserBridgeService.extractETldPlusOne('auth.github.com'), 'github.com');
      expect(BrowserBridgeService.extractETldPlusOne('deep.sub.github.com'), 'github.com');
      expect(BrowserBridgeService.extractETldPlusOne('https://login.uber.com/path?foo=1'), 'uber.com');

      // Multi-part ccTLDs (.co.uk, .com.tr, .com.au, .co.jp)
      expect(BrowserBridgeService.extractETldPlusOne('amazon.co.uk'), 'amazon.co.uk');
      expect(BrowserBridgeService.extractETldPlusOne('login.amazon.co.uk'), 'amazon.co.uk');
      expect(BrowserBridgeService.extractETldPlusOne('google.com.tr'), 'google.com.tr');
      expect(BrowserBridgeService.extractETldPlusOne('auth.google.com.tr'), 'google.com.tr');
      expect(BrowserBridgeService.extractETldPlusOne('maps.google.co.jp'), 'google.co.jp');

      // Multi-tenant developer hosting platforms (PSL Private)
      expect(BrowserBridgeService.extractETldPlusOne('user1.github.io'), 'user1.github.io');
      expect(BrowserBridgeService.extractETldPlusOne('api.user1.github.io'), 'user1.github.io');
      expect(BrowserBridgeService.extractETldPlusOne('my-site.pages.dev'), 'my-site.pages.dev');
      expect(BrowserBridgeService.extractETldPlusOne('frontend.vercel.app'), 'frontend.vercel.app');

      // Public suffixes themselves return empty string (not an eTLD+1)
      expect(BrowserBridgeService.extractETldPlusOne('co.uk'), '');
      expect(BrowserBridgeService.extractETldPlusOne('github.io'), '');
      expect(BrowserBridgeService.extractETldPlusOne('com'), '');

      // IP addresses & Localhost
      expect(BrowserBridgeService.extractETldPlusOne('127.0.0.1'), '127.0.0.1');
      expect(BrowserBridgeService.extractETldPlusOne('192.168.1.1'), '192.168.1.1');
      expect(BrowserBridgeService.extractETldPlusOne('localhost'), 'localhost');
    });

    test('isDomainMatch accurately verifies root domains across subdomains', () {
      // Direct matches and subdomains
      expect(BrowserBridgeService.isDomainMatch('uber.com', 'uber.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('login.uber.com', 'uber.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('uber.com', 'login.uber.com'), isTrue);

      // Sister subdomains under the same eTLD+1
      expect(BrowserBridgeService.isDomainMatch('login.uber.com', 'riders.uber.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('auth.github.com', 'api.github.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('accounts.google.com', 'mail.google.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('login.amazon.co.uk', 'pay.amazon.co.uk'), isTrue);

      // Distinct root domains
      expect(BrowserBridgeService.isDomainMatch('uber.com', 'lyft.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('github.com', 'gitlab.com'), isFalse);

      // Multi-tenant platform isolation (must NEVER match different users)
      expect(BrowserBridgeService.isDomainMatch('user1.github.io', 'attacker.github.io'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('site-a.pages.dev', 'site-b.pages.dev'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('evil.co.uk', 'amazon.co.uk'), isFalse);

      // Phishing domain rejection
      expect(BrowserBridgeService.isDomainMatch('github.com.attacker.com', 'github.com'), isFalse);
    });

    test('POST /query matches credentials when visiting sister subdomains and ranks exact matches first', () async {
      final items = [
        VaultItem(
          id: 'sister-sub',
          type: VaultItemType.credential,
          title: 'Uber Riders',
          username: 'rider_alice',
          password: 'RiderPassword123!',
          website: 'https://riders.uber.com',
        ),
        VaultItem(
          id: 'exact-sub',
          type: VaultItemType.credential,
          title: 'Uber Driver Login',
          username: 'driver_alice',
          password: 'DriverPassword123!',
          website: 'https://login.uber.com',
        ),
        VaultItem(
          id: 'root-sub',
          type: VaultItemType.credential,
          title: 'Uber General',
          username: 'general_alice',
          password: 'GeneralPassword123!',
          website: 'https://uber.com',
        ),
      ];

      final testBridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => items,
        initialToken: 'etld-token',
      );
      await testBridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${testBridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer etld-token',
          'Origin': 'chrome-extension://myextension',
        },
        body: jsonEncode({'url': 'https://login.uber.com/app'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = json['matches'] as List<dynamic>;

      // All 3 items should match because they share the 'uber.com' eTLD+1
      expect(matches.length, 3);
      // Exact match (login.uber.com) must be ranked first
      expect(matches[0]['id'], 'exact-sub');
      // Root domain match (uber.com) ranked second
      expect(matches[1]['id'], 'root-sub');
      // Sister subdomain match (riders.uber.com) ranked third
      expect(matches[2]['id'], 'sister-sub');

      await testBridge.stop();
    });
  });
}
