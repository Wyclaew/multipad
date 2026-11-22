import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
  static const String currentVersion = '1.3.1';
  static const int maxBodyBytes = 256 * 1024; // 256 KB max payload

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
        _pairingCode = initialPairingCode ?? _generatePairingCode();

  static String _generatePairingCode() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  String get pairingToken => _pairingToken;
  String get pairingCode => _pairingCode;
  String get baseUrl => 'http://127.0.0.1:$port';

  /// Generates a fresh pairing token and returns it.
  String rotatePairingToken() {
    _pairingToken = const Uuid().v4();
    return _pairingToken;
  }

  /// Generates a fresh pairing verification code and returns it.
  String rotatePairingCode() {
    _pairingCode = _generatePairingCode();
    return _pairingCode;
  }

  /// Explicitly sets the pairing code (e.g. user-defined or for testing).
  void setPairingCode(String code) {
    _pairingCode = code;
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
