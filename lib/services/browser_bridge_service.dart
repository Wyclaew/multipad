import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/totp_service.dart';

/// Local authenticated loopback HTTP bridge service connecting desktop browser
/// extensions (Chrome, Firefox, Edge) to the running MultiPad vault.
///
/// Binds strictly to 127.0.0.1 (default port: 48292).
class BrowserBridgeService {
  static const int defaultPort = 48292;
  static const String currentVersion = '1.3.0';

  final bool Function() isUnlocked;
  final List<VaultItem> Function() getItems;
  final Future<void> Function(VaultItem item)? onSaveItem;
  final void Function(Map<String, dynamic> data)? onCredentialCaptured;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  String _pairingToken;

  BrowserBridgeService({
    required this.isUnlocked,
    required this.getItems,
    this.onSaveItem,
    this.onCredentialCaptured,
    String? initialToken,
  }) : _pairingToken = initialToken ?? const Uuid().v4();

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get pairingToken => _pairingToken;
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Generates a fresh pairing token and returns it.
  String rotatePairingToken() {
    _pairingToken = const Uuid().v4();
    return _pairingToken;
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

    _server = await HttpServer.bind(targetAddress, port);
    _subscription = _server!.listen(_handleHttpRequest);
  }

  /// Stops the bridge server and cleans up resources.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  /// Internal HTTP request handler.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;

    // Apply CORS headers for extension compatibility
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, Content-Type, Authorization, Accept',
    );

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    // Origin header security enforcement
    final origin = request.headers.value('origin') ?? request.headers.value('Origin') ?? '';
    if (origin.isNotEmpty &&
        !origin.startsWith('chrome-extension://') &&
        !origin.startsWith('moz-extension://') &&
        !origin.startsWith('extension://')) {
      response.statusCode = HttpStatus.forbidden;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': 'Forbidden origin'}));
      await response.close();
      return;
    }

    // Read request body
    final bodyBytes = await request.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
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

    // Pairing endpoint (returns active pairing token)
    if (path == '/pair' && request.method == 'POST') {
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
      final matches = activeItems.where((item) {
        if (item.type != VaultItemType.credential || item.isTrash || item.isDeleted) {
          return false;
        }
        final siteHost = _extractDomain(item.website);
        if (siteHost.isEmpty) return false;

        // Strict canonical host matching: match ONLY if siteHost is not empty and
        // either queryHost equals siteHost or queryHost is a subdomain of siteHost.
        final bool isSubdomain = siteHost.contains('.') && queryHost.endsWith('.$siteHost');
        return queryHost == siteHost || isSubdomain;
      }).map((item) {
        String liveTotp = '';
        if (item.totpSecret.isNotEmpty) {
          liveTotp = TotpService.generateCode(item.totpSecret) ?? item.totpSecret;
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

      if (onSaveItem != null && (username.isNotEmpty || password.isNotEmpty)) {
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
  }
}
