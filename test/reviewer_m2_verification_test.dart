import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('Reviewer M2 Independent Verification: eTLD+1 Extraction', () {
    test('standard gTLDs and deep subdomains', () {
      expect(BrowserBridgeService.extractETldPlusOne('example.com'), 'example.com');
      expect(BrowserBridgeService.extractETldPlusOne('http://sub.example.com'), 'example.com');
      expect(BrowserBridgeService.extractETldPlusOne('https://deep.sub.example.com/path?query=1'), 'example.com');
      expect(BrowserBridgeService.extractETldPlusOne('HTTPS://AUTH.GITHUB.COM:443'), 'github.com');
      expect(BrowserBridgeService.extractETldPlusOne('example.com.'), 'example.com');
    });

    test('multi-part ccTLDs across global jurisdictions', () {
      // UK
      expect(BrowserBridgeService.extractETldPlusOne('bbc.co.uk'), 'bbc.co.uk');
      expect(BrowserBridgeService.extractETldPlusOne('news.bbc.co.uk'), 'bbc.co.uk');
      expect(BrowserBridgeService.extractETldPlusOne('deep.sub.news.bbc.co.uk'), 'bbc.co.uk');
      expect(BrowserBridgeService.extractETldPlusOne('ox.ac.uk'), 'ox.ac.uk');
      expect(BrowserBridgeService.extractETldPlusOne('parliament.gov.uk'), 'parliament.gov.uk');

      // Turkey
      expect(BrowserBridgeService.extractETldPlusOne('ankara.bel.tr'), 'ankara.bel.tr');
      expect(BrowserBridgeService.extractETldPlusOne('portal.ankara.bel.tr'), 'ankara.bel.tr');
      expect(BrowserBridgeService.extractETldPlusOne('google.com.tr'), 'google.com.tr');
      expect(BrowserBridgeService.extractETldPlusOne('odtü.edu.tr'), 'odt%c3%bc.edu.tr');

      // Australia & New Zealand
      expect(BrowserBridgeService.extractETldPlusOne('csiro.gov.au'), 'csiro.gov.au');
      expect(BrowserBridgeService.extractETldPlusOne('portal.csiro.gov.au'), 'csiro.gov.au');
      expect(BrowserBridgeService.extractETldPlusOne('stuff.co.nz'), 'stuff.co.nz');

      // Japan
      expect(BrowserBridgeService.extractETldPlusOne('sony.co.jp'), 'sony.co.jp');
      expect(BrowserBridgeService.extractETldPlusOne('login.sony.co.jp'), 'sony.co.jp');
      expect(BrowserBridgeService.extractETldPlusOne('metro.tokyo.lg.jp'), 'tokyo.lg.jp');

      // South Africa & Canada
      expect(BrowserBridgeService.extractETldPlusOne('standardbank.co.za'), 'standardbank.co.za');
      expect(BrowserBridgeService.extractETldPlusOne('canada.gc.ca'), 'canada.gc.ca');
      expect(BrowserBridgeService.extractETldPlusOne('toronto.on.ca'), 'toronto.on.ca');
    });

    test('multi-tenant developer cloud platforms (PSL Private)', () {
      expect(BrowserBridgeService.extractETldPlusOne('alice.github.io'), 'alice.github.io');
      expect(BrowserBridgeService.extractETldPlusOne('docs.alice.github.io'), 'alice.github.io');
      expect(BrowserBridgeService.extractETldPlusOne('bob.gitlab.io'), 'bob.gitlab.io');
      expect(BrowserBridgeService.extractETldPlusOne('my-site.pages.dev'), 'my-site.pages.dev');
      expect(BrowserBridgeService.extractETldPlusOne('api.workers.dev'), 'api.workers.dev');
      expect(BrowserBridgeService.extractETldPlusOne('frontend.vercel.app'), 'frontend.vercel.app');
      expect(BrowserBridgeService.extractETldPlusOne('my-project.netlify.app'), 'my-project.netlify.app');
      expect(BrowserBridgeService.extractETldPlusOne('test.web.app'), 'test.web.app');
      expect(BrowserBridgeService.extractETldPlusOne('auth.firebaseapp.com'), 'auth.firebaseapp.com');
      expect(BrowserBridgeService.extractETldPlusOne('sub.auth.firebaseapp.com'), 'auth.firebaseapp.com');
      expect(BrowserBridgeService.extractETldPlusOne('app.herokuapp.com'), 'app.herokuapp.com');
      expect(BrowserBridgeService.extractETldPlusOne('site.azurewebsites.net'), 'site.azurewebsites.net');
      expect(BrowserBridgeService.extractETldPlusOne('app.azurestaticapps.net'), 'app.azurestaticapps.net');
      expect(BrowserBridgeService.extractETldPlusOne('dist.cloudfront.net'), 'dist.cloudfront.net');
      expect(BrowserBridgeService.extractETldPlusOne('mybucket.s3.amazonaws.com'), 'mybucket.s3.amazonaws.com');
      expect(BrowserBridgeService.extractETldPlusOne('sub.mybucket.s3.amazonaws.com'), 'mybucket.s3.amazonaws.com');
      expect(BrowserBridgeService.extractETldPlusOne('portal.appspot.com'), 'portal.appspot.com');
      expect(BrowserBridgeService.extractETldPlusOne('store.myshopify.com'), 'store.myshopify.com');
      expect(BrowserBridgeService.extractETldPlusOne('blog.wordpress.com'), 'blog.wordpress.com');
      expect(BrowserBridgeService.extractETldPlusOne('travel.blogspot.com'), 'travel.blogspot.com');
      expect(BrowserBridgeService.extractETldPlusOne('cdn.fastly.net'), 'cdn.fastly.net');
      expect(BrowserBridgeService.extractETldPlusOne('svc.fly.dev'), 'svc.fly.dev');
      expect(BrowserBridgeService.extractETldPlusOne('backend.onrender.com'), 'backend.onrender.com');
      expect(BrowserBridgeService.extractETldPlusOne('srv.render.com'), 'srv.render.com');
      expect(BrowserBridgeService.extractETldPlusOne('demo.glitch.me'), 'demo.glitch.me');
      expect(BrowserBridgeService.extractETldPlusOne('proj.supabase.co'), 'proj.supabase.co');
    });

    test('bare public suffixes themselves return empty string', () {
      expect(BrowserBridgeService.extractETldPlusOne('com'), '');
      expect(BrowserBridgeService.extractETldPlusOne('org'), '');
      expect(BrowserBridgeService.extractETldPlusOne('co.uk'), '');
      expect(BrowserBridgeService.extractETldPlusOne('com.tr'), '');
      expect(BrowserBridgeService.extractETldPlusOne('github.io'), '');
      expect(BrowserBridgeService.extractETldPlusOne('pages.dev'), '');
      expect(BrowserBridgeService.extractETldPlusOne('vercel.app'), '');
      expect(BrowserBridgeService.extractETldPlusOne('s3.amazonaws.com'), '');
    });

    test('IP addresses and localhost handling', () {
      expect(BrowserBridgeService.extractETldPlusOne('127.0.0.1'), '127.0.0.1');
      expect(BrowserBridgeService.extractETldPlusOne('http://127.0.0.1:48292'), '127.0.0.1');
      expect(BrowserBridgeService.extractETldPlusOne('192.168.1.100'), '192.168.1.100');
      expect(BrowserBridgeService.extractETldPlusOne('[::1]'), '::1');
      expect(BrowserBridgeService.extractETldPlusOne('http://[::1]:8080'), '::1');
      expect(BrowserBridgeService.extractETldPlusOne('localhost'), 'localhost');
      expect(BrowserBridgeService.extractETldPlusOne('http://localhost:3000'), 'localhost');
    });

    test('malformed, empty, and invalid inputs', () {
      expect(BrowserBridgeService.extractETldPlusOne(''), '');
      expect(BrowserBridgeService.extractETldPlusOne('   '), '');
      expect(BrowserBridgeService.extractETldPlusOne('http://'), '');
      expect(BrowserBridgeService.extractETldPlusOne('https://'), '');
      expect(BrowserBridgeService.extractETldPlusOne('http:'), '');
    });
  });

  group('Reviewer M2 Independent Verification: isDomainMatch', () {
    test('exact host matches and case-insensitivity', () {
      expect(BrowserBridgeService.isDomainMatch('example.com', 'example.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('EXAMPLE.COM', 'example.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('http://example.com:8080/path', 'https://example.com'), isTrue);
    });

    test('bidirectional subdomain and root matching', () {
      // Subdomain matches stored root
      expect(BrowserBridgeService.isDomainMatch('login.uber.com', 'uber.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('auth.deep.sub.uber.com', 'uber.com'), isTrue);

      // Stored subdomain matches root query
      expect(BrowserBridgeService.isDomainMatch('uber.com', 'login.uber.com'), isTrue);

      // Sister subdomains match
      expect(BrowserBridgeService.isDomainMatch('login.uber.com', 'riders.uber.com'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('auth.amazon.co.uk', 'pay.amazon.co.uk'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('news.google.com.tr', 'maps.google.com.tr'), isTrue);
    });

    test('multi-tenant platform cross-tenant strict isolation', () {
      // Different users on github.io MUST NEVER match
      expect(BrowserBridgeService.isDomainMatch('alice.github.io', 'bob.github.io'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('alice.github.io', 'attacker.github.io'), isFalse);

      // Different tenants on cloud providers MUST NEVER match
      expect(BrowserBridgeService.isDomainMatch('store-a.myshopify.com', 'store-b.myshopify.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('site-a.pages.dev', 'site-b.pages.dev'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('app-a.vercel.app', 'app-b.vercel.app'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('bucket1.s3.amazonaws.com', 'bucket2.s3.amazonaws.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('tenant1.firebaseapp.com', 'tenant2.firebaseapp.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('db1.supabase.co', 'db2.supabase.co'), isFalse);

      // But subdomains of the SAME tenant DO match
      expect(BrowserBridgeService.isDomainMatch('docs.alice.github.io', 'alice.github.io'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('api.app-a.vercel.app', 'app-a.vercel.app'), isTrue);
    });

    test('phishing domain rejection', () {
      expect(BrowserBridgeService.isDomainMatch('github.com.attacker.com', 'github.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('uber.com-phishing.org', 'uber.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('fake-uber.com', 'uber.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('https://attacker.com?redirect=github.com', 'github.com'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('https://github.com@attacker.com', 'github.com'), isFalse);
    });

    test('IP addresses and localhost matching', () {
      expect(BrowserBridgeService.isDomainMatch('http://127.0.0.1:8080', '127.0.0.1'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('127.0.0.1', '127.0.0.2'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('http://[::1]:8080', '[::1]'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('http://localhost:3000', 'localhost'), isTrue);
    });
  });

  group('Reviewer M2 Independent Verification: matchPriority Sorting', () {
    test('priority score assignment matches specification', () {
      // 0: Exact host match
      expect(BrowserBridgeService.matchPriority('login.uber.com', 'login.uber.com'), 0);
      expect(BrowserBridgeService.matchPriority('uber.com', 'uber.com'), 0);

      // 1: Query is subdomain of siteHost (user visits login.uber.com, vault has uber.com)
      expect(BrowserBridgeService.matchPriority('login.uber.com', 'uber.com'), 1);

      // 2: SiteHost is subdomain of queryHost (user visits uber.com, vault has login.uber.com)
      expect(BrowserBridgeService.matchPriority('uber.com', 'login.uber.com'), 2);

      // 3: Same eTLD+1 root domain / sister subdomains
      expect(BrowserBridgeService.matchPriority('login.uber.com', 'riders.uber.com'), 3);
      expect(BrowserBridgeService.matchPriority('auth.github.com', 'api.github.com'), 3);
    });
  });

  group('Reviewer M2 Independent Verification: End-to-End Query Integration', () {
    late BrowserBridgeService bridge;
    late List<VaultItem> vault;

    setUp(() async {
      vault = [
        VaultItem(
          id: 'item-sister-sub',
          type: VaultItemType.credential,
          title: 'Uber Driver',
          username: 'driver_user',
          password: 'DriverPassword1!',
          website: 'https://driver.uber.com/portal',
        ),
        VaultItem(
          id: 'item-exact',
          type: VaultItemType.credential,
          title: 'Uber Riders Login',
          username: 'rider_user',
          password: 'RiderPassword1!',
          website: 'https://riders.uber.com/login',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
        VaultItem(
          id: 'item-root',
          type: VaultItemType.credential,
          title: 'Uber General Account',
          username: 'uber_root_user',
          password: 'RootPassword1!',
          website: 'https://uber.com',
        ),
        VaultItem(
          id: 'item-deep-sub',
          type: VaultItemType.credential,
          title: 'Uber Riders Sub-Portal',
          username: 'rider_sub_user',
          password: 'SubPassword1!',
          website: 'https://app.riders.uber.com',
        ),
        VaultItem(
          id: 'item-unrelated',
          type: VaultItemType.credential,
          title: 'Lyft Account',
          username: 'lyft_user',
          password: 'LyftPassword1!',
          website: 'https://lyft.com',
        ),
        VaultItem(
          id: 'item-trash',
          type: VaultItemType.credential,
          title: 'Old Uber',
          username: 'old_user',
          password: 'OldPassword1!',
          website: 'https://riders.uber.com',
          isTrash: true,
        ),
      ];

      bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => vault,
        initialToken: 'rev-m2-token',
      );
      await bridge.start(port: 0);
    });

    tearDown(() async {
      if (bridge.isRunning) await bridge.stop();
    });

    test('ranks exact match (0) > parent root (1) > child sub (2) > sister sub (3) and excludes trash & unrelated', () async {
      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer rev-m2-token',
          'Origin': 'chrome-extension://legit-ext-id',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': 'https://riders.uber.com/auth'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matchList = json['matches'] as List<dynamic>;

      // Expected 4 matches: item-exact (0), item-root (1), item-deep-sub (2), item-sister-sub (3)
      // item-unrelated and item-trash must be excluded
      expect(matchList.length, 4);

      // Rank 0: Exact host (riders.uber.com)
      expect(matchList[0]['id'], 'item-exact');
      expect(matchList[0]['totp'], matches(RegExp(r'^\d{6}$')));

      // Rank 1: Query is subdomain of siteHost (uber.com)
      expect(matchList[1]['id'], 'item-root');

      // Rank 2: SiteHost is subdomain of queryHost (app.riders.uber.com)
      expect(matchList[2]['id'], 'item-deep-sub');

      // Rank 3: Sister subdomain under uber.com (driver.uber.com)
      expect(matchList[3]['id'], 'item-sister-sub');
    });
  });
}
