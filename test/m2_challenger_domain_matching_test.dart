import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/browser_bridge_service.dart';

void main() {
  group('Challenger 2 — Feature 12: Multi-Part ccTLDs Stress-Testing', () {
    test('extractETldPlusOne handles multi-part ccTLDs correctly across depths', () {
      final ccTldCases = <String, String>{
        // United Kingdom (.uk)
        'bbc.co.uk': 'bbc.co.uk',
        'login.bbc.co.uk': 'bbc.co.uk',
        'a.b.c.bbc.co.uk': 'bbc.co.uk',
        'oxford.ac.uk': 'oxford.ac.uk',
        'portal.oxford.ac.uk': 'oxford.ac.uk',
        'hmrc.gov.uk': 'hmrc.gov.uk',
        'online.hmrc.gov.uk': 'hmrc.gov.uk',
        'nhs.uk': '', // suffix itself
        'service.nhs.uk': 'service.nhs.uk',
        'met.police.uk': 'met.police.uk',

        // Turkey (.tr)
        'trendyol.com.tr': 'trendyol.com.tr',
        'auth.trendyol.com.tr': 'trendyol.com.tr',
        'metu.edu.tr': 'metu.edu.tr',
        'sis.metu.edu.tr': 'metu.edu.tr',
        'turkiye.gov.tr': 'turkiye.gov.tr',
        'giris.turkiye.gov.tr': 'turkiye.gov.tr',
        'ankara.bel.tr': 'ankara.bel.tr',
        'baro.av.tr': 'baro.av.tr',
        'egm.pol.tr': 'egm.pol.tr',

        // Australia (.au)
        'commbank.com.au': 'commbank.com.au',
        'netbank.commbank.com.au': 'commbank.com.au',
        'sydney.edu.au': 'sydney.edu.au',
        'ato.gov.au': 'ato.gov.au',
        'my.ato.gov.au': 'ato.gov.au',

        // Japan (.jp)
        'yahoo.co.jp': 'yahoo.co.jp',
        'mail.yahoo.co.jp': 'yahoo.co.jp',
        'u-tokyo.ac.jp': 'u-tokyo.ac.jp',
        'soumu.go.jp': 'soumu.go.jp',
        'tokyo.lg.jp': 'tokyo.lg.jp',

        // Brazil (.br)
        'globo.com.br': 'globo.com.br',
        'login.globo.com.br': 'globo.com.br',
        'usp.edu.br': 'usp.edu.br',
        'receita.gov.br': 'receita.gov.br',

        // New Zealand (.nz)
        'stuff.co.nz': 'stuff.co.nz',
        'ird.govt.nz': 'ird.govt.nz',

        // India (.in)
        'flipkart.co.in': 'flipkart.co.in',
        'iitd.ac.in': 'iitd.ac.in',
        'nic.gov.in': 'nic.gov.in',

        // Canada (.ca)
        'service.gc.ca': 'service.gc.ca',
        'alberta.ab.ca': 'alberta.ab.ca',
        'ontario.on.ca': 'ontario.on.ca',

        // Israel (.il)
        'bank.co.il': 'bank.co.il',
        'mfa.gov.il': 'mfa.gov.il',

        // South Korea (.kr)
        'naver.co.kr': 'naver.co.kr',
        'snu.ac.kr': 'snu.ac.kr',

        // Singapore (.sg)
        'dbs.com.sg': 'dbs.com.sg',
        'gov.sg': '', // suffix itself
        'singpass.gov.sg': 'singpass.gov.sg',

        // Public suffix bare hosts return empty string
        'co.uk': '',
        'com.tr': '',
        'edu.tr': '',
        'gov.uk': '',
        'com.au': '',
        'co.jp': '',
      };

      for (final entry in ccTldCases.entries) {
        expect(
          BrowserBridgeService.extractETldPlusOne(entry.key),
          entry.value,
          reason: 'Failed to extract eTLD+1 for ${entry.key}',
        );
      }
    });

    test('isDomainMatch matches sister subdomains on multi-part ccTLDs correctly', () {
      // Sister subdomains on .co.uk
      expect(
        BrowserBridgeService.isDomainMatch('login.bbc.co.uk', 'news.bbc.co.uk'),
        isTrue,
      );
      // Sister subdomains on .com.tr
      expect(
        BrowserBridgeService.isDomainMatch('auth.trendyol.com.tr', 'pay.trendyol.com.tr'),
        isTrue,
      );
      // Sister subdomains on .edu.tr
      expect(
        BrowserBridgeService.isDomainMatch('sis.metu.edu.tr', 'login.metu.edu.tr'),
        isTrue,
      );
      // Sister subdomains on .gov.uk
      expect(
        BrowserBridgeService.isDomainMatch('tax.service.gov.uk', 'login.service.gov.uk'),
        isTrue,
      );
      // Distinct root domains on same ccTLD do NOT match
      expect(
        BrowserBridgeService.isDomainMatch('bbc.co.uk', 'amazon.co.uk'),
        isFalse,
      );
      expect(
        BrowserBridgeService.isDomainMatch('trendyol.com.tr', 'hepsiburada.com.tr'),
        isFalse,
      );
      expect(
        BrowserBridgeService.isDomainMatch('metu.edu.tr', 'boun.edu.tr'),
        isFalse,
      );
      expect(
        BrowserBridgeService.isDomainMatch('hmrc.gov.uk', 'dvla.gov.uk'),
        isFalse,
      );
    });
  });

  group('Challenger 2 — Feature 12: Cloud Multi-Tenant Hosting Isolation Stress-Testing', () {
    test('extractETldPlusOne treats multi-tenant platforms as PSL private suffixes', () {
      final platforms = <String, String>{
        // GitHub Pages
        'alice.github.io': 'alice.github.io',
        'bob.github.io': 'bob.github.io',
        'api.alice.github.io': 'alice.github.io',
        'sub.deep.alice.github.io': 'alice.github.io',
        'github.io': '', // platform root suffix

        // Cloudflare Pages
        'alice.pages.dev': 'alice.pages.dev',
        'bob.pages.dev': 'bob.pages.dev',
        'pages.dev': '',

        // Cloudflare Workers
        'api.workers.dev': 'api.workers.dev',
        'workers.dev': '',

        // Vercel
        'app.vercel.app': 'app.vercel.app',
        'evil.vercel.app': 'evil.vercel.app',
        'vercel.app': '',

        // Netlify
        'site1.netlify.app': 'site1.netlify.app',
        'site2.netlify.app': 'site2.netlify.app',
        'netlify.app': '',

        // Firebase
        'proj-a.firebaseapp.com': 'proj-a.firebaseapp.com',
        'proj-b.firebaseapp.com': 'proj-b.firebaseapp.com',
        'firebaseapp.com': '',
        'proj-a.web.app': 'proj-a.web.app',
        'web.app': '',

        // AWS CloudFront & S3
        'd123.cloudfront.net': 'd123.cloudfront.net',
        'd456.cloudfront.net': 'd456.cloudfront.net',
        'cloudfront.net': '',
        'mybucket.s3.amazonaws.com': 'mybucket.s3.amazonaws.com',
        's3.amazonaws.com': '',

        // Render, Fly, Glitch, Supabase
        'myapi.onrender.com': 'myapi.onrender.com',
        'myapi.fly.dev': 'myapi.fly.dev',
        'myproject.supabase.co': 'myproject.supabase.co',
      };

      for (final entry in platforms.entries) {
        expect(
          BrowserBridgeService.extractETldPlusOne(entry.key),
          entry.value,
          reason: 'Failed for platform host ${entry.key}',
        );
      }
    });

    test('STRICT SECURITY ISOLATION: Cross-tenant credentials NEVER match on multi-tenant platforms', () {
      // Different tenants on github.io
      expect(
        BrowserBridgeService.isDomainMatch('alice.github.io', 'bob.github.io'),
        isFalse,
        reason: 'CRITICAL SECURITY LEAK: alice.github.io matched bob.github.io!',
      );
      expect(
        BrowserBridgeService.isDomainMatch('attacker.github.io', 'victim.github.io'),
        isFalse,
      );

      // Different tenants on pages.dev
      expect(
        BrowserBridgeService.isDomainMatch('alice.pages.dev', 'bob.pages.dev'),
        isFalse,
      );

      // Different tenants on vercel.app
      expect(
        BrowserBridgeService.isDomainMatch('alice.vercel.app', 'bob.vercel.app'),
        isFalse,
      );

      // Different tenants on netlify.app
      expect(
        BrowserBridgeService.isDomainMatch('alice.netlify.app', 'bob.netlify.app'),
        isFalse,
      );

      // Different tenants on firebaseapp.com
      expect(
        BrowserBridgeService.isDomainMatch('corp-a.firebaseapp.com', 'corp-b.firebaseapp.com'),
        isFalse,
      );

      // Different tenants on cloudfront.net
      expect(
        BrowserBridgeService.isDomainMatch('d111.cloudfront.net', 'd222.cloudfront.net'),
        isFalse,
      );

      // Subdomains belonging to SAME tenant DO match
      expect(
        BrowserBridgeService.isDomainMatch('api.alice.github.io', 'alice.github.io'),
        isTrue,
      );
      expect(
        BrowserBridgeService.isDomainMatch('staging.alice.vercel.app', 'prod.alice.vercel.app'),
        isTrue,
      );
    });

    test('Bare platform suffixes do not leak credentials to tenant sites', () {
      // Querying bare platform suffix should not match tenant
      expect(
        BrowserBridgeService.isDomainMatch('github.io', 'alice.github.io'),
        isFalse,
      );
      expect(
        BrowserBridgeService.isDomainMatch('pages.dev', 'alice.pages.dev'),
        isFalse,
      );
      expect(
        BrowserBridgeService.isDomainMatch('vercel.app', 'alice.vercel.app'),
        isFalse,
      );
    });
  });

  group('Challenger 2 — Feature 12: Bidirectional Matching Stress-Testing', () {
    test('subdomain query matches root credential, and root query matches subdomain credential', () {
      // 1. Query: auth.github.com -> Credential: github.com
      expect(
        BrowserBridgeService.isDomainMatch('https://auth.github.com/login', 'https://github.com'),
        isTrue,
      );

      // 2. Query: github.com -> Credential: login.github.com
      expect(
        BrowserBridgeService.isDomainMatch('https://github.com', 'https://login.github.com'),
        isTrue,
      );

      // 3. Query: riders.uber.com -> Credential: login.uber.com (sister subdomains)
      expect(
        BrowserBridgeService.isDomainMatch('https://riders.uber.com/profile', 'https://login.uber.com'),
        isTrue,
      );

      // 4. Query: dev.api.service.example.com -> Credential: portal.example.com
      expect(
        BrowserBridgeService.isDomainMatch('https://dev.api.service.example.com', 'https://portal.example.com'),
        isTrue,
      );

      // 5. Query: example.com -> Credential: deep.sub.example.com
      expect(
        BrowserBridgeService.isDomainMatch('https://example.com', 'https://deep.sub.example.com'),
        isTrue,
      );
    });
  });

  group('Challenger 2 — Feature 12: Edge Cases & Malformed Inputs', () {
    test('IP addresses (IPv4 & IPv6) and localhost handling', () {
      // IPv4
      expect(BrowserBridgeService.extractETldPlusOne('127.0.0.1'), '127.0.0.1');
      expect(BrowserBridgeService.extractETldPlusOne('192.168.1.1'), '192.168.1.1');
      expect(BrowserBridgeService.extractETldPlusOne('10.0.0.5:8080'), '10.0.0.5');

      expect(BrowserBridgeService.isDomainMatch('127.0.0.1', '127.0.0.1'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('http://192.168.1.1:8080', 'http://192.168.1.1:3000'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('127.0.0.1', '127.0.0.2'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('192.168.1.1', '192.168.1.2'), isFalse);

      // Localhost
      expect(BrowserBridgeService.extractETldPlusOne('localhost'), 'localhost');
      expect(BrowserBridgeService.extractETldPlusOne('localhost:3000'), 'localhost');
      expect(BrowserBridgeService.isDomainMatch('http://localhost:3000', 'http://localhost:8080'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('localhost', '127.0.0.1'), isFalse);
      expect(BrowserBridgeService.isDomainMatch('localhost', 'localhost.com'), isFalse);

      // IPv6
      expect(BrowserBridgeService.extractDomain('http://[::1]:8080'), '::1');
      expect(BrowserBridgeService.extractDomain('http://[2001:db8::1]'), '2001:db8::1');
      expect(BrowserBridgeService.extractETldPlusOne('http://[::1]:8080'), '::1');
      expect(BrowserBridgeService.isDomainMatch('http://[::1]:8080', 'http://[::1]:3000'), isTrue);
      expect(BrowserBridgeService.isDomainMatch('http://[::1]', 'http://[::2]'), isFalse);
    });

    test('Malformed URIs, trailing dots, empty strings, and case variations', () {
      final invalidCases = ['', ' ', '   ', 'http://', 'https://', 'http:', 'https:', '://invalid', 'http:///'];
      for (final bad in invalidCases) {
        expect(BrowserBridgeService.extractDomain(bad), '');
        expect(BrowserBridgeService.extractETldPlusOne(bad), '');
        expect(BrowserBridgeService.isDomainMatch(bad, 'https://github.com'), isFalse);
        expect(BrowserBridgeService.isDomainMatch('https://github.com', bad), isFalse);
      }

      // Case insensitivity
      expect(
        BrowserBridgeService.isDomainMatch('HTTPS://LOGIN.UBER.COM', 'https://uber.com'),
        isTrue,
      );
      expect(
        BrowserBridgeService.isDomainMatch('https://uber.com', 'HTTPS://LOGIN.UBER.COM'),
        isTrue,
      );

      // Trailing dots (FQDN canonicalization)
      expect(
        BrowserBridgeService.isDomainMatch('login.uber.com.', 'uber.com'),
        isTrue,
      );
      expect(
        BrowserBridgeService.isDomainMatch('uber.com.', 'login.uber.com.'),
        isTrue,
      );
    });
  });

  group('Challenger 2 — Feature 12: Match Priority Sorting Stress-Testing', () {
    test('matchPriority scores exact host (0) > subdomain (1) > site subdomain (2) > sister eTLD+1 (3)', () {
      final query = 'https://login.uber.com/app';

      // 0: Exact host match
      expect(BrowserBridgeService.matchPriority(query, 'https://login.uber.com'), 0);

      // 1: Query is subdomain of siteHost (e.g. login.uber.com is subdomain of uber.com)
      expect(BrowserBridgeService.matchPriority(query, 'https://uber.com'), 1);

      // 2: Site is subdomain of query (e.g. deep.login.uber.com is subdomain of login.uber.com)
      expect(BrowserBridgeService.matchPriority(query, 'https://deep.login.uber.com'), 2);

      // 3: Same eTLD+1 root domain (sister subdomain)
      expect(BrowserBridgeService.matchPriority(query, 'https://riders.uber.com'), 3);
      expect(BrowserBridgeService.matchPriority(query, 'https://drivers.uber.com'), 3);
    });

    test('HTTP /query endpoint returns credentials strictly ordered by priority score', () async {
      final vaultItems = [
        VaultItem(
          id: 'sister-item',
          type: VaultItemType.credential,
          title: 'Uber Riders',
          username: 'sister_user',
          password: 'pass',
          website: 'https://riders.uber.com',
        ),
        VaultItem(
          id: 'exact-item',
          type: VaultItemType.credential,
          title: 'Uber Driver Login',
          username: 'exact_user',
          password: 'pass',
          website: 'https://login.uber.com',
        ),
        VaultItem(
          id: 'site-sub-item',
          type: VaultItemType.credential,
          title: 'Uber Deep Login',
          username: 'deep_user',
          password: 'pass',
          website: 'https://auth.login.uber.com',
        ),
        VaultItem(
          id: 'root-item',
          type: VaultItemType.credential,
          title: 'Uber Root',
          username: 'root_user',
          password: 'pass',
          website: 'https://uber.com',
        ),
      ];

      final bridge = BrowserBridgeService(
        isUnlocked: () => true,
        getItems: () => vaultItems,
        initialToken: 'priority-token',
      );
      await bridge.start(port: 0);

      final res = await http.post(
        Uri.parse('${bridge.baseUrl}/query'),
        headers: {
          'Authorization': 'Bearer priority-token',
          'Origin': 'chrome-extension://my-test-extension',
        },
        body: jsonEncode({'url': 'https://login.uber.com'}),
      );

      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final matches = (json['matches'] as List<dynamic>).cast<Map<String, dynamic>>();

      expect(matches.length, 4);
      // Priority 0: Exact match
      expect(matches[0]['id'], 'exact-item');
      // Priority 1: Query is subdomain of siteHost (uber.com)
      expect(matches[1]['id'], 'root-item');
      // Priority 2: SiteHost is subdomain of query (auth.login.uber.com)
      expect(matches[2]['id'], 'site-sub-item');
      // Priority 3: Sister subdomain (riders.uber.com)
      expect(matches[3]['id'], 'sister-item');

      await bridge.stop();
    });
  });
}
