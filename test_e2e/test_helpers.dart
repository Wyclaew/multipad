// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:multipad/models/vault_folder.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Comprehensive test environment helpers, mock harnesses, and cryptographic
/// reference vectors for MultiPad opaque-box E2E tests.
class E2ETestHelpers {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.multipad.multipad/native');
  static const MethodChannel _localAuthChannel =
      MethodChannel('plugins.flutter.io/local_auth');

  static bool _biometricsHardwareSupported = true;
  static bool _biometricsEnrollmentStatus = true;
  static bool _biometricsShouldSucceed = true;
  static String? _pendingLaunchAction;
  static final List<String> _invokedNativeMethods = [];
  static final List<Map<String, String>> _lastAutofillEntries = [];

  static void setupMockPlatformChannels() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, (MethodCall call) async {
      _invokedNativeMethods.add('local_auth:${call.method}');
      switch (call.method) {
        case 'isDeviceSupported':
          return _biometricsHardwareSupported;
        case 'canCheckBiometrics':
          return _biometricsEnrollmentStatus;
        case 'getAvailableBiometrics':
          return ['fingerprint', 'face'];
        case 'authenticate':
          return _biometricsShouldSucceed;
        case 'stopAuthentication':
          return true;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeChannel, (MethodCall call) async {
      _invokedNativeMethods.add('native:${call.method}');
      final args = call.arguments as Map<dynamic, dynamic>?;
      switch (call.method) {
        case 'consumePendingLaunchAction':
          final action = _pendingLaunchAction;
          _pendingLaunchAction = null;
          return action;
        case 'setFlagSecure':
        case 'setMulticastLock':
        case 'configureDesktopShell':
        case 'bringWindowToFront':
        case 'openAutofillSettings':
        case 'installApk':
          return true;
        case 'copyConfidential':
          return true;
        case 'updateAutofillIndex':
          _lastAutofillEntries.clear();
          if (args != null && args['entries'] is List) {
            for (final item in (args['entries'] as List)) {
              if (item is Map) {
                _lastAutofillEntries.add(Map<String, String>.from(item));
              }
            }
          }
          return true;
        case 'clearAutofillIndex':
          _lastAutofillEntries.clear();
          return true;
        default:
          return null;
      }
    });
  }

  static void resetMockPlatformChannels() {
    _biometricsHardwareSupported = true;
    _biometricsEnrollmentStatus = true;
    _biometricsShouldSucceed = true;
    _pendingLaunchAction = null;
    _invokedNativeMethods.clear();
    _lastAutofillEntries.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localAuthChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeChannel, null);
  }

  static void setBiometricsBehavior({
    bool hardwareSupported = true,
    bool enrolled = true,
    bool shouldSucceed = true,
  }) {
    _biometricsHardwareSupported = hardwareSupported;
    _biometricsEnrollmentStatus = enrolled;
    _biometricsShouldSucceed = shouldSucceed;
  }

  static void setPendingLaunchAction(String? action) {
    _pendingLaunchAction = action;
  }

  static List<String> get invokedNativeMethods =>
      List.unmodifiable(_invokedNativeMethods);
  static List<Map<String, String>> get lastAutofillEntries =>
      List.unmodifiable(_lastAutofillEntries);

  /// Standard environment setup executed before each E2E test.
  static Future<void> setupE2ETestEnvironment({
    Map<String, Object> initialPrefs = const {},
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.configureForTesting(dbPath: inMemoryDatabasePath);
    SharedPreferences.setMockInitialValues(Map.from(initialPrefs));
    FlutterSecureStorage.setMockInitialValues({});
    ClipboardService.setDefaultTimeoutSeconds(30);
    NativeBridgeService.resetForTesting();
    setupMockPlatformChannels();
  }

  /// Standard teardown executed after each E2E test.
  static Future<void> teardownE2ETestEnvironment() async {
    ClipboardService.cancelScheduledClear();
    NativeBridgeService.resetForTesting();
    await DatabaseService.closeForTesting();
    resetMockPlatformChannels();
  }

  // ---------------------------------------------------------------------------
  // 2FA Re-Prompt Interval Logic
  // ---------------------------------------------------------------------------

  /// Authoritative evaluator for 2FA re-prompt interval contract.
  static bool evaluateTwoFactorPromptDue({
    required DateTime? lastVerified,
    required int intervalDays,
    required DateTime now,
  }) {
    if (intervalDays <= 0) return true;
    if (lastVerified == null) return true;
    final diff = now.difference(lastVerified);
    return diff >= Duration(days: intervalDays);
  }

  // ---------------------------------------------------------------------------
  // Bitwarden Encrypted JSON Cryptographic Reference Pipeline
  // ---------------------------------------------------------------------------

  /// RFC 5869 HKDF-Expand with HMAC-SHA256 for 32-byte subkey.
  static Uint8List hkdfExpandSha256(List<int> prk, String info) {
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, prk);
    final digest = hmac.convert([...utf8.encode(info), 1]);
    return Uint8List.fromList(digest.bytes);
  }

  /// Generates a Bitwarden-compatible HKDF expanded key pair (32-byte encKey, 32-byte macKey).
  static Future<({Uint8List encKey, Uint8List macKey})> deriveBitwardenSubKeys({
    required String password,
    required String salt,
    int kdfIterations = 100000,
  }) async {
    // 1. PBKDF2 derivation of 32-byte master key
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: kdfIterations,
      bits: 256,
    );
    final masterKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: utf8.encode(salt.toLowerCase().trim()),
    );
    final masterKeyBytes = await masterKey.extractBytes();

    // 2. HKDF-Expand with "enc" and "mac" application info strings
    final encKeyBytes = hkdfExpandSha256(masterKeyBytes, 'enc');
    final macKeyBytes = hkdfExpandSha256(masterKeyBytes, 'mac');

    return (
      encKey: encKeyBytes,
      macKey: macKeyBytes,
    );
  }

  /// Encrypts plaintext string into Bitwarden CipherString format: `2.<iv>|<ciphertext>|<mac>`.
  static Future<String> encryptBitwardenCipherString({
    required String plaintext,
    required Uint8List encKey,
    required Uint8List macKey,
  }) async {
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = (i * 17 + 5) & 0xFF; // Deterministic test IV
    }

    final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretBox = await aesCbc.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(encKey),
      nonce: iv,
    );

    final ivB64 = base64Encode(iv);
    final cipherB64 = base64Encode(secretBox.cipherText);

    // Compute HMAC-SHA256 across (iv + ciphertext)
    final macPayload = Uint8List.fromList([...iv, ...secretBox.cipherText]);
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, macKey);
    final macDigest = hmac.convert(macPayload);
    final macB64 = base64Encode(macDigest.bytes);

    return '2.$ivB64|$cipherB64|$macB64';
  }

  /// Decrypts Bitwarden CipherString (`2.<iv>|<ciphertext>|<mac>`) verifying HMAC-SHA256.
  static Future<String> decryptBitwardenCipherString({
    required String cipherString,
    required Uint8List encKey,
    required Uint8List macKey,
  }) async {
    if (!cipherString.startsWith('2.')) {
      throw const FormatException('Unsupported or invalid Bitwarden encType');
    }
    final raw = cipherString.substring(2);
    final parts = raw.split('|');
    if (parts.length != 3) {
      throw const FormatException('Invalid Bitwarden CipherString structure');
    }

    final iv = base64Decode(parts[0]);
    final cipherText = base64Decode(parts[1]);
    final expectedMac = base64Decode(parts[2]);

    // Verify HMAC-SHA256
    final macPayload = Uint8List.fromList([...iv, ...cipherText]);
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, macKey);
    final calculatedMac = hmac.convert(macPayload).bytes;

    if (!CryptoService.constantTimeEquals(calculatedMac, expectedMac)) {
      throw const FormatException('Bitwarden MAC verification failed (wrong password or tampered data)');
    }

    final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final decryptedBytes = await aesCbc.decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac.empty),
      secretKey: SecretKey(encKey),
    );

    return utf8.decode(decryptedBytes);
  }

  /// Generates a valid Bitwarden encrypted JSON export string for testing.
  static Future<String> createBitwardenEncryptedJsonFixture({
    required String password,
    required String userEmail,
    required String innerJsonPlaintext,
  }) async {
    final subKeys = await deriveBitwardenSubKeys(
      password: password,
      salt: userEmail,
    );
    final encryptedData = await encryptBitwardenCipherString(
      plaintext: innerJsonPlaintext,
      encKey: subKeys.encKey,
      macKey: subKeys.macKey,
    );

    final envelope = {
      'encrypted': true,
      'passwordProtected': true,
      'kdfType': 0, // PBKDF2
      'kdfIterations': 100000,
      'salt': userEmail,
      'data': encryptedData,
    };
    return jsonEncode(envelope);
  }

  // ---------------------------------------------------------------------------
  // Desktop Browser Extension Loopback Bridge Harness
  // ---------------------------------------------------------------------------

  /// Creates a local HTTP loopback bridge server simulating `BrowserBridgeService`.
  static Future<TestBrowserBridgeHarness> startTestBridge({
    required String pairingToken,
    required List<VaultItem> Function() getItems,
    required bool Function() isUnlocked,
    void Function(Map<String, dynamic> captured)? onCredentialCaptured,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final harness = TestBrowserBridgeHarness(
      server: server,
      pairingToken: pairingToken,
      getItems: getItems,
      isUnlocked: isUnlocked,
      onCredentialCaptured: onCredentialCaptured,
    );
    harness.listen();
    return harness;
  }

  // ---------------------------------------------------------------------------
  // Centralized TOTP Ticker Simulator
  // ---------------------------------------------------------------------------

  /// Creates a centralized ticker stream controller to verify timer consolidation.
  static CentralizedTotpTicker createCentralTicker() {
    return CentralizedTotpTicker();
  }

  /// Generates a secure random password with requested complexity options.
  static String generateSecureRandomPassword({
    int length = 20,
    bool includeUppercase = true,
    bool includeLowercase = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
    bool avoidAmbiguous = false,
  }) {
    String upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String lower = 'abcdefghijklmnopqrstuvwxyz';
    String numbers = '0123456789';
    String symbols = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    if (avoidAmbiguous) {
      upper = upper.replaceAll(RegExp(r'[OI]'), '');
      lower = lower.replaceAll(RegExp(r'[l]'), '');
      numbers = numbers.replaceAll(RegExp(r'[01]'), '');
    }

    String pool = '';
    if (includeUppercase) pool += upper;
    if (includeLowercase) pool += lower;
    if (includeNumbers) pool += numbers;
    if (includeSymbols) pool += symbols;

    if (pool.isEmpty) return '';

    final random = Random.secure();
    final chars = <String>[];
    if (includeUppercase && upper.isNotEmpty) chars.add(upper[random.nextInt(upper.length)]);
    if (includeLowercase && lower.isNotEmpty) chars.add(lower[random.nextInt(lower.length)]);
    if (includeNumbers && numbers.isNotEmpty) chars.add(numbers[random.nextInt(numbers.length)]);
    if (includeSymbols && symbols.isNotEmpty) chars.add(symbols[random.nextInt(symbols.length)]);

    while (chars.length < length) {
      chars.add(pool[random.nextInt(pool.length)]);
    }

    chars.shuffle(random);
    return chars.join();
  }

  // ---------------------------------------------------------------------------
  // Sample Data Fixtures
  // ---------------------------------------------------------------------------

  static VaultItem sampleCredential({
    String id = 'cred-1',
    String title = 'GitHub Dev',
    String username = 'octocat',
    String password = 'SuperSecretPassword!2026',
    String website = 'https://github.com/login',
    String totpSecret = 'JBSWY3DPEHPK3PXP',
    String? folderId,
  }) {
    return VaultItem(
      id: id,
      type: VaultItemType.credential,
      title: title,
      username: username,
      password: password,
      website: website,
      totpSecret: totpSecret,
      folderId: folderId,
      passwordLastModified: DateTime.now().toUtc(),
      clientUpdatedAt: DateTime.now().toUtc(),
    );
  }

  static VaultItem sampleCard({
    String id = 'card-1',
    String title = 'Work Corporate Card',
    String cardNumber = '4111 1111 1111 1111',
    String cardExpiry = '12/28',
    String cardCvv = '123',
    String cardHolder = 'Alice Cooper',
  }) {
    return VaultItem(
      id: id,
      type: VaultItemType.card,
      title: title,
      cardNumber: cardNumber,
      cardExpiry: cardExpiry,
      cardCvv: cardCvv,
      cardHolder: cardHolder,
      clientUpdatedAt: DateTime.now().toUtc(),
    );
  }

  static VaultFolder sampleFolder({
    String id = 'folder-1',
    String name = 'Development',
  }) {
    return VaultFolder(
      id: id,
      name: name,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

/// Harness managing an ephemeral loopback bridge for testing extension integration.
class TestBrowserBridgeHarness {
  final HttpServer server;
  final String pairingToken;
  final List<VaultItem> Function() getItems;
  final bool Function() isUnlocked;
  final void Function(Map<String, dynamic> captured)? onCredentialCaptured;
  StreamSubscription<HttpRequest>? _subscription;

  TestBrowserBridgeHarness({
    required this.server,
    required this.pairingToken,
    required this.getItems,
    required this.isUnlocked,
    this.onCredentialCaptured,
  });

  int get port => server.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  http.Client get client => _TestBridgeHttpClient(this);

  Future<http.Response> handleRequest({
    required String path,
    required String method,
    Map<String, String>? headers,
    String? bodyStr,
  }) async {
    final origin = headers?['origin'] ?? headers?['Origin'] ?? '';
    if (origin.isNotEmpty &&
        !origin.startsWith('chrome-extension://') &&
        !origin.startsWith('moz-extension://')) {
      return http.Response(jsonEncode({'error': 'Forbidden origin'}), HttpStatus.forbidden);
    }

    final authHeader = headers?['authorization'] ?? headers?['Authorization'] ?? '';
    final isPaired = authHeader == 'Bearer $pairingToken';

    if (path == '/status' && method == 'GET') {
      return http.Response(
        jsonEncode({
          'status': isUnlocked() ? 'unlocked' : 'locked',
          'version': '1.2.0',
        }),
        HttpStatus.ok,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/pair' && method == 'POST') {
      return http.Response(
        jsonEncode({'token': pairingToken}),
        HttpStatus.ok,
        headers: {'content-type': 'application/json'},
      );
    }

    if (!isPaired) {
      return http.Response(
        jsonEncode({'error': 'Unauthorized'}),
        HttpStatus.unauthorized,
        headers: {'content-type': 'application/json'},
      );
    }

    if (!isUnlocked()) {
      return http.Response(
        jsonEncode({'error': 'Vault is locked'}),
        HttpStatus.locked,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/query' && method == 'POST') {
      final Map<String, dynamic> body;
      try {
        body = (bodyStr != null && bodyStr.isNotEmpty)
            ? jsonDecode(bodyStr) as Map<String, dynamic>
            : <String, dynamic>{};
      } catch (_) {
        return http.Response(
          jsonEncode({'error': 'Malformed JSON payload'}),
          HttpStatus.badRequest,
          headers: {'content-type': 'application/json'},
        );
      }
      final queryUrl = (body['url']?.toString() ?? '').toLowerCase();
      final matches = getItems().where((item) {
        if (item.type != VaultItemType.credential) return false;
        final site = item.website.toLowerCase();
        return queryUrl.isNotEmpty && site.contains(queryUrl);
      }).map((item) => {
            'id': item.id,
            'title': item.title,
            'username': item.username,
            'password': item.password,
            'totp': item.totpSecret,
          }).toList();

      return http.Response(
        jsonEncode({'matches': matches}),
        HttpStatus.ok,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/capture' && method == 'POST') {
      final Map<String, dynamic> body;
      try {
        body = (bodyStr != null && bodyStr.isNotEmpty)
            ? jsonDecode(bodyStr) as Map<String, dynamic>
            : <String, dynamic>{};
      } catch (_) {
        return http.Response(
          jsonEncode({'error': 'Malformed JSON payload'}),
          HttpStatus.badRequest,
          headers: {'content-type': 'application/json'},
        );
      }
      onCredentialCaptured?.call(body);
      return http.Response(
        jsonEncode({'success': true}),
        HttpStatus.created,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response('Not Found', HttpStatus.notFound);
  }

  void listen() {
    _subscription = server.listen((request) async {
      final bodyBytes = await request.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      final bodyStr = utf8.decode(bodyBytes);
      final headersMap = <String, String>{};
      request.headers.forEach((name, values) {
        if (values.isNotEmpty) headersMap[name] = values.first;
      });

      final response = await handleRequest(
        path: request.uri.path,
        method: request.method,
        headers: headersMap,
        bodyStr: bodyStr,
      );

      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, value) {
        request.response.headers.set(name, value);
      });
      request.response.write(response.body);
      await request.response.close();
    });
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await server.close(force: true);
  }
}

class _TestBridgeHttpClient extends http.BaseClient {
  final TestBrowserBridgeHarness harness;
  _TestBridgeHttpClient(this.harness);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final bodyStr = utf8.decode(bodyBytes);
    final response = await harness.handleRequest(
      path: request.url.path,
      method: request.method,
      headers: request.headers,
      bodyStr: bodyStr,
    );
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

/// Consolidated TOTP ticker broadcasting stream for low background footprint.
class CentralizedTotpTicker {
  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  Timer? _timer;
  int _activeSubscribers = 0;
  bool _isPaused = false;

  CentralizedTotpTicker() {
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && !_controller.isClosed) {
        _controller.add(DateTime.now());
      }
    });
  }

  StreamSubscription<DateTime> subscribe(void Function(DateTime) onTick) {
    _activeSubscribers++;
    final sub = _controller.stream.listen(onTick);
    return _TickerSubscription(sub, () {
      _activeSubscribers = (_activeSubscribers - 1).clamp(0, 999999);
    });
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  int get activeSubscribers => _activeSubscribers;
  bool get isPaused => _isPaused;

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

class _TickerSubscription implements StreamSubscription<DateTime> {
  final StreamSubscription<DateTime> _inner;
  final void Function() _onCancel;
  _TickerSubscription(this._inner, this._onCancel);

  @override
  Future<void> cancel() {
    _onCancel();
    return _inner.cancel();
  }

  @override
  void onData(void Function(DateTime data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}
