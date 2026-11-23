import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/totp_service.dart';

/// Local authenticated loopback HTTP bridge service connecting desktop browser
/// extensions (Chrome, Firefox, Edge) to the running MultiPad vault.
///
/// Binds strictly to 127.0.0.1 (default port: 48292).
class BrowserBridgeService with ChangeNotifier {
  static const int defaultPort = 48292;
  static const String currentVersion = '1.4.0';
  static const int maxBodyBytes = 256 * 1024; // 256 KB max payload

  // Singleton reference
  static BrowserBridgeService? instance;

  final bool Function() isUnlocked;
  final List<VaultItem> Function() getItems;
  final Future<void> Function(VaultItem item)? onSaveItem;
  final void Function(Map<String, dynamic> data)? onCredentialCaptured;
  final Future<bool> Function(String code)? onPairingApproval;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String _pairingToken;
  String _pairingCode;

  BrowserBridgeService({
    required this.isUnlocked,
    required this.getItems,
    this.onSaveItem,
    this.onCredentialCaptured,
    this.onPairingApproval,
    String? initialToken,
    String? initialPairingCode,
  })  : _pairingToken = initialToken ?? const Uuid().v4(),
        _pairingCode = initialPairingCode ?? _generatePairingCode() {
    instance ??= this;
  }

  static String _generatePairingCode() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  bool get isRunning => _server != null;
  bool get isPortBound => _server != null;
  int get port => _server?.port ?? 0;
  String get pairingToken => _pairingToken;
  String get pairingCode => _pairingCode;
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Generates a fresh pairing token and code and returns the token.
  String rotatePairingToken() {
    _pairingToken = const Uuid().v4();
    _pairingCode = _generatePairingCode();
    notifyListeners();
    return _pairingToken;
  }

  /// Generates a fresh pairing verification code and returns it.
  String rotatePairingCode() {
    _pairingCode = _generatePairingCode();
    notifyListeners();
    return _pairingCode;
  }

  /// Explicitly sets the pairing code (e.g. user-defined or for testing).
  void setPairingCode(String code) {
    _pairingCode = code;
    notifyListeners();
  }

  /// Extracts canonical hostname from a raw URL or hostname string,
  /// lowercased and stripped of port, query, path, and IPv6 brackets.
  static String _extractDomain(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    // Generic schemes with no host
    if (trimmed == 'http://' ||
        trimmed == 'https://' ||
        trimmed == 'http:' ||
        trimmed == 'https:') {
      return '';
    }

    var urlToParse = trimmed;
    if (!urlToParse.contains('://')) {
      var candidateIp = trimmed;
      if (candidateIp.startsWith('[') && candidateIp.endsWith(']')) {
        candidateIp = candidateIp.substring(1, candidateIp.length - 1);
      }
      if (InternetAddress.tryParse(candidateIp) != null) {
        return candidateIp.toLowerCase();
      }
      urlToParse = 'http://$urlToParse';
    }

    final parsed = Uri.tryParse(urlToParse);
    if (parsed == null || parsed.host.isEmpty) {
      return '';
    }

    var host = parsed.host.toLowerCase().trim();
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  /// Exposes canonical domain extraction for URL strings.
  static String extractDomain(String rawUrl) => _extractDomain(rawUrl);

  /// Comprehensive set of multi-part public suffixes (ccTLDs and multi-tenant hosting platforms).
  static const Set<String> _multiPartSuffixes = {
    // United Kingdom (.uk)
    'co.uk', 'org.uk', 'me.uk', 'net.uk', 'ltd.uk', 'plc.uk', 'ac.uk', 'sch.uk', 'gov.uk', 'nhs.uk', 'police.uk',
    // Australia (.au)
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au', 'asn.au', 'id.au',
    // New Zealand (.nz)
    'co.nz', 'net.nz', 'org.nz', 'govt.nz', 'ac.nz', 'school.nz', 'geek.nz',
    // Japan (.jp)
    'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'ed.jp', 'go.jp', 'gr.jp', 'lg.jp',
    // Brazil (.br)
    'com.br', 'net.br', 'org.br', 'gov.br', 'edu.br', 'mil.br', 'art.br',
    // Turkey (.tr)
    'com.tr', 'net.tr', 'org.tr', 'edu.tr', 'gov.tr', 'bel.tr', 'gen.tr', 'biz.tr', 'info.tr', 'av.tr', 'dr.tr', 'pol.tr',
    // India (.in)
    'co.in', 'net.in', 'org.in', 'gen.in', 'firm.in', 'ind.in', 'ac.in', 'edu.in', 'res.in', 'gov.in', 'mil.in',
    // South Africa (.za)
    'co.za', 'org.za', 'net.za', 'web.za', 'gov.za', 'ac.za', 'edu.za',
    // Canada (.ca)
    'gc.ca', 'ab.ca', 'bc.ca', 'mb.ca', 'nb.ca', 'nl.ca', 'ns.ca', 'nt.ca', 'nu.ca', 'on.ca', 'pe.ca', 'qc.ca', 'sk.ca', 'yk.ca',
    // United States (.us)
    'fed.us', 'dni.us',
    // Europe & Russia
    'com.es', 'nom.es', 'org.es', 'gob.es', 'edu.es',
    'com.pt', 'org.pt', 'gov.pt', 'edu.pt',
    'com.pl', 'net.pl', 'org.pl',
    'com.ru', 'net.ru', 'org.ru', 'pp.ru',
    // Israel (.il)
    'co.il', 'org.il', 'net.il', 'ac.il', 'gov.il', 'muni.il', 'idf.il',
    // South Korea (.kr)
    'co.kr', 'ne.kr', 'or.kr', 're.kr', 'pe.kr', 'go.kr', 'mil.kr', 'ac.kr',
    // Singapore (.sg)
    'com.sg', 'net.sg', 'org.sg', 'gov.sg', 'edu.sg', 'per.sg',
    // Hong Kong (.hk)
    'com.hk', 'net.hk', 'org.hk', 'gov.hk', 'edu.hk', 'idv.hk',
    // Taiwan (.tw)
    'com.tw', 'org.tw', 'net.tw', 'gov.tw', 'edu.tw', 'idv.tw',
    // Malaysia (.my)
    'com.my', 'net.my', 'org.my', 'gov.my', 'edu.my', 'mil.my',
    // Mexico (.mx)
    'com.mx', 'net.mx', 'org.mx', 'edu.mx', 'gob.mx',
    // Argentina (.ar)
    'com.ar', 'net.ar', 'org.ar', 'gob.ar', 'edu.ar',
    // Colombia (.co)
    'com.co', 'net.co', 'nom.co', 'org.co', 'gov.co', 'edu.co',
    // Philippines (.ph)
    'com.ph', 'net.ph', 'org.ph', 'gov.ph', 'edu.ph',
    // China (.cn)
    'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn',
    // Shared Developer & Multi-Tenant Platforms (PSL Private Domains)
    'github.io', 'gitlab.io', 'pages.dev', 'workers.dev', 'vercel.app', 'now.sh',
    'netlify.app', 'web.app', 'firebaseapp.com', 'herokuapp.com', 'azurewebsites.net',
    'azurestaticapps.net', 'cloudfront.net', 's3.amazonaws.com', 'appspot.com',
    'myshopify.com', 'wordpress.com', 'blogspot.com', 'fastly.net', 'fly.dev',
    'onrender.com', 'render.com', 'glitch.me', 'supabase.co',
  };

  /// Extracts the effective Top-Level Domain plus one label (eTLD+1 / root domain).
  ///
  /// Examples:
  /// - `login.uber.com` -> `uber.com`
  /// - `auth.github.com` -> `github.com`
  /// - `login.amazon.co.uk` -> `amazon.co.uk`
  /// - `myuser.github.io` -> `myuser.github.io`
  /// - `127.0.0.1` -> `127.0.0.1`
  /// - `localhost` -> `localhost`
  /// - `co.uk` -> `""` (public suffix itself cannot be an eTLD+1)
  static String extractETldPlusOne(String rawUrlOrHost) {
    final host = _extractDomain(rawUrlOrHost);
    if (host.isEmpty) return '';

    // 1. IP address check: IP addresses do not have TLDs
    if (InternetAddress.tryParse(host) != null) {
      return host;
    }

    // 2. Single label host (e.g. localhost)
    if (!host.contains('.')) {
      if (host == 'localhost') return host;
      return '';
    }

    final labels = host.split('.');
    if (labels.length <= 1) return host;

    int suffixLength = 1;

    // Check 3-part suffix candidate (if host has >= 3 labels)
    if (labels.length >= 3) {
      final candidate3 = labels.sublist(labels.length - 3).join('.');
      if (_multiPartSuffixes.contains(candidate3)) {
        suffixLength = 3;
      }
    }

    // Check 2-part suffix candidate (if host has >= 2 labels and not already matched)
    if (suffixLength == 1 && labels.length >= 2) {
      final candidate2 = labels.sublist(labels.length - 2).join('.');
      if (_multiPartSuffixes.contains(candidate2)) {
        suffixLength = 2;
      }
    }

    // If host is equal to or shorter than the public suffix itself, it is not an eTLD+1
    if (labels.length < suffixLength + 1) {
      return '';
    }

    return labels.sublist(labels.length - (suffixLength + 1)).join('.');
  }

  /// Determines whether [queryUrlOrHost] matches [siteUrlOrHost] using strict canonical
  /// host matching, subdomain inheritance, and eTLD+1 root domain equivalence.
  static bool isDomainMatch(String queryUrlOrHost, String siteUrlOrHost) {
    final queryHost = _extractDomain(queryUrlOrHost);
    final siteHost = _extractDomain(siteUrlOrHost);

    if (queryHost.isEmpty || siteHost.isEmpty) return false;

    // 1. Exact canonical host match
    if (queryHost == siteHost) return true;

    // 2. Query is direct or nested subdomain of site (e.g. auth.github.com on github.com)
    if (siteHost.contains('.') && queryHost.endsWith('.$siteHost')) {
      return true;
    }

    // 3. Site is direct or nested subdomain of query (e.g. user visits github.com, vault has auth.github.com)
    if (queryHost.contains('.') && siteHost.endsWith('.$queryHost')) {
      final queryRoot = extractETldPlusOne(queryHost);
      if (queryRoot.isNotEmpty && queryHost == queryRoot) {
        return true;
      }
    }

    // 4. eTLD+1 Root Domain Equivalence (e.g. login.uber.com and riders.uber.com)
    final queryRoot = extractETldPlusOne(queryHost);
    final siteRoot = extractETldPlusOne(siteHost);

    if (queryRoot.isNotEmpty && siteRoot.isNotEmpty && queryRoot == siteRoot) {
      return true;
    }

    return false;
  }

  /// Calculates match priority score for sorting:
  /// 0: Exact host match
  /// 1: Query is subdomain of siteHost
  /// 2: SiteHost is subdomain of queryHost
  /// 3: Same eTLD+1 root domain (sister subdomains)
  static int matchPriority(String queryHost, String siteHost) {
    final qHost = _extractDomain(queryHost);
    final sHost = _extractDomain(siteHost);
    if (qHost == sHost) return 0;
    if (sHost.contains('.') && qHost.endsWith('.$sHost')) return 1;
    if (qHost.contains('.') && sHost.endsWith('.$qHost')) return 2;
    return 3;
  }

  /// Starts the loopback bridge server on the specified port.
  /// Rejects non-loopback bindings for security.
  Future<void> start({
    int port = defaultPort,
    InternetAddress? address,
  }) async {
    if (_server != null) return;

    final targetAddress = address ?? InternetAddress.loopbackIPv4;
    if (!targetAddress.isLoopback) {
      throw ArgumentError('BrowserBridgeService must strictly bind to loopback address (127.0.0.1).');
    }

    instance = this;
    _server = await HttpServer.bind(targetAddress, port);
    _subscription = _server!.listen(_handleHttpRequest);
    notifyListeners();
  }

  /// Stops the bridge server and cleans up resources.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
    notifyListeners();
  }

  /// Internal HTTP request handler.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;

    try {
      // Apply CORS headers for extension compatibility
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      response.headers.set(
        'Access-Control-Allow-Headers',
        'Origin, Content-Type, Authorization, Accept',
      );

      // 1. Host header validation (DNS Rebinding protection)
      // Only accept 127.0.0.1:port or localhost:port matching the bound port
      final hostHeader = (request.headers.value('host') ?? '').toLowerCase().trim();
      final boundPort = _server?.port ?? defaultPort;
      final allowedHosts = <String>{
        '127.0.0.1:$boundPort',
        'localhost:$boundPort',
      };
      if (hostHeader.isEmpty || !allowedHosts.contains(hostHeader)) {
        response.statusCode = HttpStatus.forbidden;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Forbidden host'}));
        await response.close();
        return;
      }

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      // 2. Origin header security enforcement
      final origin = request.headers.value('origin') ?? request.headers.value('Origin') ?? '';
      final hasValidExtensionOrigin = origin.startsWith('chrome-extension://') ||
          origin.startsWith('moz-extension://') ||
          origin.startsWith('extension://');

      if (origin.isNotEmpty && !hasValidExtensionOrigin) {
        response.statusCode = HttpStatus.forbidden;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Forbidden origin'}));
        await response.close();
        return;
      }

      // 3. Read request body with size limit enforcement (DoS protection)
      final bodyBytes = <int>[];
      int totalBytes = 0;
      bool payloadTooLarge = false;

      await for (final chunk in request) {
        totalBytes += chunk.length;
        if (totalBytes > maxBodyBytes) {
          payloadTooLarge = true;
          break;
        }
        bodyBytes.addAll(chunk);
      }

      if (payloadTooLarge) {
        response.statusCode = HttpStatus.requestEntityTooLarge; // 413
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Payload too large (max 256KB)'}));
        await response.close();
        return;
      }

      final bodyStr = utf8.decode(bodyBytes, allowMalformed: true);

      // Normalize route path: support both /api/v1/path and /path
      var path = request.uri.path;
      if (path.startsWith('/api/v1/')) {
        path = path.substring(7); // strip '/api/v1'
      }

      // Status endpoint (public)
      if (path == '/status' && request.method == 'GET') {
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'status': isUnlocked() ? 'unlocked' : 'locked',
            'version': currentVersion,
          }),
        );
        await response.close();
        return;
      }

      // Pairing endpoint (SEC-CRIT-1 remediation: requires pairing code verification / desktop approval)
      if (path == '/pair' && request.method == 'POST') {
        final authHeader = request.headers.value('authorization') ?? request.headers.value('Authorization') ?? '';
        final hasValidBearer = CryptoService.constantTimeStringEquals(authHeader, 'Bearer $_pairingToken');

        // Require valid extension origin or valid Bearer token for pairing context
        if (!hasValidExtensionOrigin && !hasValidBearer) {
          response.statusCode = HttpStatus.forbidden;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'error': 'Extension origin required for pairing'}));
          await response.close();
          return;
        }

        final Map<String, dynamic> body;
        try {
          body = (bodyStr.isNotEmpty)
              ? jsonDecode(bodyStr) as Map<String, dynamic>
              : <String, dynamic>{};
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'error': 'Malformed JSON payload'}));
          await response.close();
          return;
        }

        final code = body['code']?.toString() ?? body['pin']?.toString() ?? '';

        bool isAuthorized = false;
        if (onPairingApproval != null) {
          isAuthorized = await onPairingApproval!(code);
        } else {
          isAuthorized = code.isNotEmpty &&
              CryptoService.constantTimeStringEquals(code, _pairingCode);
        }

        if (!isAuthorized && hasValidBearer) {
          isAuthorized = true;
        }

        if (!isAuthorized) {
          response.statusCode = HttpStatus.unauthorized;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({
            'error': 'Pairing authorization required. Invalid or missing pairing code.',
          }));
          await response.close();
          return;
        }

        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'token': _pairingToken}));
        await response.close();
        return;
      }

      // Route validation: non-matching routes return 404 Not Found
      if (path != '/query' && path != '/capture') {
        response.statusCode = HttpStatus.notFound;
        response.write('Not Found');
        await response.close();
        return;
      }

      // Authentication check for protected routes (/query, /capture) using constant-time comparison
      final authHeader = request.headers.value('authorization') ?? request.headers.value('Authorization') ?? '';
      final expectedAuth = 'Bearer $_pairingToken';
      if (!CryptoService.constantTimeStringEquals(authHeader, expectedAuth)) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Unauthorized'}));
        await response.close();
        return;
      }

      // Vault lock enforcement (returns HTTP 423 Locked)
      if (!isUnlocked()) {
        response.statusCode = HttpStatus.locked; // 423
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Vault is locked'}));
        await response.close();
        return;
      }

      // Query credentials endpoint
      if (path == '/query' && request.method == 'POST') {
        final Map<String, dynamic> body;
        try {
          body = (bodyStr.isNotEmpty)
              ? jsonDecode(bodyStr) as Map<String, dynamic>
              : <String, dynamic>{};
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'error': 'Malformed JSON payload'}));
          await response.close();
          return;
        }

        final queryUrl = (body['url']?.toString() ?? '').toLowerCase().trim();
        final queryHost = _extractDomain(queryUrl);

        // Require non-empty queryHost; generic queries like 'https://' or empty strings match nothing
        if (queryHost.isEmpty) {
          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'matches': []}));
          await response.close();
          return;
        }

        final activeItems = getItems();
        final matchedItems = activeItems.where((item) {
          if (item.type != VaultItemType.credential || item.isTrash || item.isDeleted) {
            return false;
          }
          final siteHost = _extractDomain(item.website);
          if (siteHost.isEmpty) return false;

          return isDomainMatch(queryHost, siteHost);
        }).toList();

        // Sort matches: exact host first, subdomain second, sister eTLD+1 third
        matchedItems.sort((a, b) {
          final hostA = _extractDomain(a.website);
          final hostB = _extractDomain(b.website);
          final scoreA = matchPriority(queryHost, hostA);
          final scoreB = matchPriority(queryHost, hostB);
          return scoreA.compareTo(scoreB);
        });

        final matches = matchedItems.map((item) {
          String liveTotp = '';
          if (item.totpSecret.isNotEmpty) {
            liveTotp = TotpService.generateCode(item.totpSecret) ?? '';
          }
          return {
            'id': item.id,
            'title': item.title,
            'username': item.username,
            'password': item.password,
            'totp': liveTotp,
          };
        }).toList();

        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'matches': matches}));
        await response.close();
        return;
      }

      // Capture credential endpoint
      if (path == '/capture' && request.method == 'POST') {
        final Map<String, dynamic> body;
        try {
          body = (bodyStr.isNotEmpty)
              ? jsonDecode(bodyStr) as Map<String, dynamic>
              : <String, dynamic>{};
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'error': 'Malformed JSON payload'}));
          await response.close();
          return;
        }

        final url = body['url']?.toString() ?? '';
        final username = body['username']?.toString() ?? '';
        final password = body['password']?.toString() ?? '';

        onCredentialCaptured?.call(body);

        final activeItems = getItems();
        final captureHost = _extractDomain(url);

        VaultItem? existingItem;
        if (captureHost.isNotEmpty && username.isNotEmpty) {
          for (final item in activeItems) {
            if (item.type != VaultItemType.credential || item.isTrash || item.isDeleted) {
              continue;
            }
            final itemHost = _extractDomain(item.website);
            if (itemHost == captureHost &&
                item.username.trim().toLowerCase() == username.trim().toLowerCase()) {
              existingItem = item;
              break;
            }
          }
        }

        if (onSaveItem != null && (username.isNotEmpty || password.isNotEmpty)) {
          if (existingItem != null) {
            if (existingItem.password != password) {
              final updatedItem = existingItem.copyWith(
                password: password,
                passwordLastModified: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              await onSaveItem!(updatedItem);
            }
          } else {
            final parsedUri = Uri.tryParse(url);
            final defaultTitle = (parsedUri != null && parsedUri.host.isNotEmpty) ? parsedUri.host : 'Captured Login';
            final newItem = VaultItem(
              id: const Uuid().v4(),
              type: VaultItemType.credential,
              title: defaultTitle,
              website: url,
              username: username,
              password: password,
            );
            await onSaveItem!(newItem);
          }
        }

        response.statusCode = HttpStatus.created;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'success': true}));
        await response.close();
        return;
      }

      // Route not found
      response.statusCode = HttpStatus.notFound;
      response.write('Not Found');
      await response.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'error': 'Internal server error'}));
        await response.close();
      } catch (_) {}
    }
  }
}
