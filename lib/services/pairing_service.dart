import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'crypto_service.dart';

class PairingPayload {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String email;
  final String masterSalt;
  final String? masterKeyBase64;
  final List<Map<String, dynamic>> offlineItems;

  PairingPayload({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.email,
    required this.masterSalt,
    this.masterKeyBase64,
    this.offlineItems = const [],
  });

  String toJsonString() => jsonEncode({
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
        'email': email,
        'masterSalt': masterSalt,
        'masterKeyBase64': masterKeyBase64,
        'offlineItems': offlineItems,
      });

  factory PairingPayload.fromJsonString(String jsonStr) {
    final map = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
    final rawItems = map['offlineItems'] as List<dynamic>? ?? [];
    return PairingPayload(
      supabaseUrl: map['supabaseUrl'] as String? ?? '',
      supabaseAnonKey: map['supabaseAnonKey'] as String? ?? '',
      email: map['email'] as String? ?? '',
      masterSalt: map['masterSalt'] as String? ?? '',
      masterKeyBase64: map['masterKeyBase64'] as String?,
      offlineItems: rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }
}

class ParsedQrPairing {
  final List<String> ips;
  final int port;
  final String pin;

  ParsedQrPairing({
    required this.ips,
    required this.port,
    required this.pin,
  });
}

class DiscoveredPairingDevice {
  final String sessionId;
  final String deviceName;
  final String ip;
  final List<String> allIps;
  final int port;
  final DateTime lastSeen;

  DiscoveredPairingDevice({
    required this.sessionId,
    required this.deviceName,
    required this.ip,
    List<String>? allIps,
    required this.port,
    required this.lastSeen,
  }) : allIps = allIps ?? [ip];
}

enum PairingHostStatus {
  waiting,
  paired,
  lockedOut,
  expired,
  closed,
}

class PairingHostSession {
  static const int discoveryUdpPort = 48291;

  final String pin;
  final String sessionId;
  final PairingPayload _payload;
  final CryptoService _cryptoService;
  final void Function(PairingHostStatus status, String message) onStatusChanged;

  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  Timer? _expiryTimer;
  DateTime? _expiresAt;

  int get remainingSeconds {
    if (_closed || _completed || _expiresAt == null) return 0;
    final secs = _expiresAt!.difference(DateTime.now()).inSeconds;
    return secs < 0 ? 0 : secs;
  }

  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _ephemeralKeyPair;
  String? _senderPubKeyBase64;
  Uint8List? _pairingSaltBytes;

  int _failedAttempts = 0;
  bool _completed = false;
  bool _closed = false;

  List<String> localIps = [];
  int? serverPort;

  PairingHostSession({
    required this.pin,
    required PairingPayload payload,
    required CryptoService cryptoService,
    required this.onStatusChanged,
  })  : _payload = payload,
        _cryptoService = cryptoService,
        sessionId = const Uuid().v4();

  String buildQrPairingUri() {
    final ipsParam = Uri.encodeComponent(localIps.join(','));
    return 'MPPAIR:v1:$ipsParam:${serverPort ?? 0}:$pin';
  }

  Future<void> start() async {
    _ephemeralKeyPair = await _x25519.newKeyPair();
    final pubKey = await _ephemeralKeyPair!.extractPublicKey();
    _senderPubKeyBase64 = base64Encode(pubKey.bytes);

    final rand = Random.secure();
    _pairingSaltBytes =
        Uint8List.fromList(List<int>.generate(16, (_) => rand.nextInt(256)));

    localIps = await _getLocalIPv4Addresses();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    serverPort = _server!.port;

    _server!.listen(_handleRequest);

    // Expire automatically after 5 minutes for security
    _expiresAt = DateTime.now().add(const Duration(minutes: 5));
    _expiryTimer = Timer(const Duration(minutes: 5), () {
      if (!_completed && !_closed) {
        onStatusChanged(
          PairingHostStatus.expired,
          'Eşleştirme kodunun süresi doldu (5 dk).',
        );
        stop();
      }
    });

    // Broadcast UDP discovery beacon every 1.5 seconds on LAN
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;
      _sendBeacon();
      _beaconTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _sendBeacon(),
      );
    } catch (e) {
      debugPrint('UDP discovery broadcast unavailable: $e');
    }
  }

  void _sendBeacon() {
    if (_closed || _completed || _udpSocket == null || serverPort == null) return;
    try {
      final msg = jsonEncode({
        'app': 'MultiPad',
        'v': 1,
        'id': sessionId,
        'device': _getFriendlyDeviceName(),
        'ips': localIps,
        'port': serverPort,
      });
      final data = utf8.encode(msg);

      try {
        _udpSocket!.send(
          data,
          InternetAddress('255.255.255.255'),
          discoveryUdpPort,
        );
      } catch (_) {
        // macOS often rejects 255.255.255.255 on certain interfaces; subnet .255 below handles it.
      }

      // Also broadcast to subnet .255 for macOS/Linux/Android Wi-Fi compatibility
      for (final ip in localIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            _udpSocket!.send(
              data,
              InternetAddress(subnetBroadcast),
              discoveryUdpPort,
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Beacon send error: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    var responseClosed = false;
    try {
      if (_closed || _completed || _failedAttempts >= 3) {
        request.response.statusCode = HttpStatus.gone;
        await request.response.close();
        responseClosed = true;
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/info') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'device': _getFriendlyDeviceName(),
          'senderPubKey': _senderPubKeyBase64,
          'salt': base64Encode(_pairingSaltBytes!),
        }));
        await request.response.close();
        responseClosed = true;
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/pair') {
        final bodyStr = await utf8.decoder.bind(request).join();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final receiverPubKeyBase64 = body['receiverPubKey'] as String?;
        final proofBase64 = body['proof'] as String?;

        if (receiverPubKeyBase64 == null || proofBase64 == null) {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          responseClosed = true;
          return;
        }

        List<int>? sessionKeyBytes;
        try {
          final receiverPubKey = SimplePublicKey(
            base64Decode(receiverPubKeyBase64),
            type: KeyPairType.x25519,
          );
          final sharedSecret = await _x25519.sharedSecretKey(
            keyPair: _ephemeralKeyPair!,
            remotePublicKey: receiverPubKey,
          );

          final derivedKey = await _hkdf.deriveKey(
            secretKey: sharedSecret,
            nonce: _pairingSaltBytes!,
            info: utf8.encode('multipad_lan_pair_v1:$pin'),
          );
          // Copy into mutable list so CryptoService.wipe never throws UnsupportedError
          sessionKeyBytes = Uint8List.fromList(await derivedKey.extractBytes());

          final expectedProof = crypto_pkg.Hmac(crypto_pkg.sha256, sessionKeyBytes)
              .convert(utf8.encode('multipad_pair_verify'))
              .bytes;
          final receivedProof = base64Decode(proofBase64);

          if (!CryptoService.constantTimeEquals(expectedProof, receivedProof)) {
            _failedAttempts++;
            final left = 3 - _failedAttempts;
            request.response.statusCode = HttpStatus.forbidden;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({'error': 'Invalid PIN', 'attemptsLeft': left}),
            );
            await request.response.close();
            responseClosed = true;

            if (_failedAttempts >= 3) {
              onStatusChanged(
                PairingHostStatus.lockedOut,
                '3 kez hatalı PIN girildiği için güvenlik amacıyla eşleştirme iptal edildi.',
              );
              await stop();
            } else {
              onStatusChanged(
                PairingHostStatus.waiting,
                'Hatalı PIN denemesi tespit edildi! (Kalan hak: $left)',
              );
            }
            return;
          }

          // PIN & X25519 verified! Encrypt payload with AES-256-GCM using sessionKey
          final encrypted = await _cryptoService.encryptData(
            _payload.toJsonString(),
            sessionKeyBytes,
          );

          _completed = true;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'ciphertext': encrypted.ciphertext,
            'iv': encrypted.iv,
            'mac': encrypted.mac,
          }));
          await request.response.flush();
          await request.response.close();
          responseClosed = true;

          onStatusChanged(
            PairingHostStatus.paired,
            'Cihaz eşleştirildi! Kurulum ve kasa verileri şifreli tünelden aktarıldı.',
          );
          Timer(const Duration(milliseconds: 4000), () => stop(force: false));
          return;
        } finally {
          CryptoService.wipe(sessionKeyBytes);
        }
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      responseClosed = true;
    } catch (e) {
      debugPrint('Pairing host request error: $e');
      if (!responseClosed) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> stop({bool force = true}) async {
    if (_closed) return;
    _closed = true;
    _beaconTimer?.cancel();
    _expiryTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    try {
      await _server?.close(force: force);
    } catch (_) {}
    _server = null;
    CryptoService.wipe(_pairingSaltBytes);
  }

  static String _getFriendlyDeviceName() {
    if (kIsWeb) return 'Web Tarayıcı';
    if (Platform.isMacOS) return 'Mac Bilgisayar';
    if (Platform.isWindows) return 'Windows Bilgisayar';
    if (Platform.isAndroid) return 'Android Cihaz';
    if (Platform.isIOS) return 'iPhone / iPad';
    return Platform.localHostname;
  }

  static Future<List<String>> _getLocalIPv4Addresses() async {
    final List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        // Skip common virtual bridge / tunnel interfaces when listing primary LAN IPs
        final isVirtual = nameLower.startsWith('utun') ||
            nameLower.startsWith('tun') ||
            nameLower.startsWith('tap') ||
            nameLower.startsWith('docker') ||
            nameLower.startsWith('veth') ||
            nameLower.startsWith('vmnet') ||
            nameLower.startsWith('bridge');
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            if (!isVirtual) {
              ips.insert(0, addr.address);
            } else {
              ips.add(addr.address);
            }
          }
        }
      }
      // Prefer standard home/office Wi-Fi subnets (192.168.x.x) first
      ips.sort((a, b) {
        final aHome = a.startsWith('192.168.') ? 0 : (a.startsWith('10.') ? 1 : 2);
        final bHome = b.startsWith('192.168.') ? 0 : (b.startsWith('10.') ? 1 : 2);
        return aHome.compareTo(bHome);
      });
    } catch (e) {
      debugPrint('NetworkInterface list error: $e');
    }
    return ips;
  }
}

class PairingService {
  final CryptoService _cryptoService;

  PairingService(this._cryptoService);

  /// Generates a cryptographically secure 6-digit pairing PIN
  static String generateSixDigitPin() {
    final rand = Random.secure();
    final code = rand.nextInt(1000000);
    return code.toString().padLeft(6, '0');
  }

  /// Creates an active LAN host session to pair a second device
  Future<PairingHostSession> startHostSession({
    required PairingPayload payload,
    required void Function(PairingHostStatus status, String message) onStatusChanged,
  }) async {
    final pin = generateSixDigitPin();
    final session = PairingHostSession(
      pin: pin,
      payload: payload,
      cryptoService: _cryptoService,
      onStatusChanged: onStatusChanged,
    );
    await session.start();
    return session;
  }

  static ParsedQrPairing? parseQrPairingUri(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('MPPAIR:v1:')) return null;
    final parts = trimmed.split(':');
    if (parts.length != 5) return null;
    final ipsRaw = Uri.decodeComponent(parts[2]);
    final ips = ipsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final port = int.tryParse(parts[3]);
    final pin = parts[4].trim();
    if (ips.isEmpty || port == null || port <= 0 || pin.length != 6) {
      return null;
    }
    return ParsedQrPairing(ips: ips, port: port, pin: pin);
  }

  /// Tries multiple candidate host IPs (e.g. from QR or multi-NIC host) in order.
  /// Immediately aborts on Wrong PIN or closed/expired session rather than retrying other IPs.
  Future<PairingPayload> connectAndPairAny({
    required List<String> hostIps,
    required int port,
    required String pin,
  }) async {
    final uniqueIps = <String>[];
    for (final ip in hostIps) {
      final clean = ip.trim();
      if (clean.isNotEmpty && !uniqueIps.contains(clean)) {
        uniqueIps.add(clean);
      }
    }
    if (uniqueIps.isEmpty) {
      throw Exception('Geçerli bir IP adresi bulunamadı.');
    }

    if (uniqueIps.length > 1) {
      final results = await Future.wait(
        uniqueIps.map((ip) async {
          try {
            final socket = await Socket.connect(
              ip,
              port,
              timeout: const Duration(milliseconds: 1500),
            );
            socket.destroy();
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      final reachable = <String>[];
      final unreachable = <String>[];
      for (var i = 0; i < uniqueIps.length; i++) {
        if (results[i]) {
          reachable.add(uniqueIps[i]);
        } else {
          unreachable.add(uniqueIps[i]);
        }
      }
      uniqueIps
        ..clear()
        ..addAll(reachable)
        ..addAll(unreachable);
    }

    Object? lastError;
    for (final ip in uniqueIps) {
      try {
        return await connectAndPair(hostIp: ip, port: port, pin: pin);
      } catch (e) {
        final msg = e.toString();
        // Do not retry different NICs on authentication/lockout errors
        if (msg.contains('PIN kodu hatalı') ||
            msg.contains('Oturum güvenlik nedeniyle kapatıldı') ||
            msg.contains('süresi doldu') ||
            msg.contains('6 haneli')) {
          rethrow;
        }
        lastError = e;
      }
    }
    throw lastError ?? Exception('Hiçbir IP adresi üzerinden bağlantı kurulamadı.');
  }

  /// Connects to a discovered or manually typed LAN host and completes X25519 + PIN key exchange
  Future<PairingPayload> connectAndPair({
    required String hostIp,
    required int port,
    required String pin,
  }) async {
    final cleanPin = pin.replaceAll(RegExp(r'\s+'), '');
    if (cleanPin.length != 6) {
      throw Exception('Lütfen 6 haneli eşleştirme PIN kodunu girin.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..findProxy = (_) => 'DIRECT';
    List<int>? sessionKeyBytes;

    try {
      // 1. Fetch ephemeral X25519 public key & salt from host
      final infoReq = await client.getUrl(Uri.parse('http://$hostIp:$port/info'));
      final infoRes = await infoReq.close().timeout(const Duration(seconds: 6));

      if (infoRes.statusCode == HttpStatus.gone) {
        throw Exception('Eşleştirme oturumu kapandı veya süresi doldu.');
      }
      if (infoRes.statusCode != HttpStatus.ok) {
        throw Exception('Cihaza bağlanılamadı (HTTP ${infoRes.statusCode}).');
      }

      final infoStr = await utf8.decoder.bind(infoRes).join();
      final infoMap = jsonDecode(infoStr) as Map<String, dynamic>;
      final senderPubKeyBase64 = infoMap['senderPubKey'] as String;
      final saltBytes = base64Decode(infoMap['salt'] as String);

      // 2. Compute ephemeral X25519 keypair + HKDF session key bound to PIN
      final x25519 = X25519();
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

      final receiverKeyPair = await x25519.newKeyPair();
      final receiverPubKey = await receiverKeyPair.extractPublicKey();
      final senderPubKey = SimplePublicKey(
        base64Decode(senderPubKeyBase64),
        type: KeyPairType.x25519,
      );

      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: receiverKeyPair,
        remotePublicKey: senderPubKey,
      );

      final derivedKey = await hkdf.deriveKey(
        secretKey: sharedSecret,
        nonce: saltBytes,
        info: utf8.encode('multipad_lan_pair_v1:$cleanPin'),
      );
      // Copy into mutable list so CryptoService.wipe never throws UnsupportedError
      sessionKeyBytes = Uint8List.fromList(await derivedKey.extractBytes());

      final proof = crypto_pkg.Hmac(crypto_pkg.sha256, sessionKeyBytes)
          .convert(utf8.encode('multipad_pair_verify'))
          .bytes;

      // 3. Send public key & HMAC proof
      final pairReq = await client.postUrl(Uri.parse('http://$hostIp:$port/pair'));
      pairReq.headers.contentType = ContentType.json;
      pairReq.write(jsonEncode({
        'receiverPubKey': base64Encode(receiverPubKey.bytes),
        'proof': base64Encode(proof),
      }));

      final pairRes = await pairReq.close().timeout(const Duration(seconds: 8));
      final pairBodyStr = await utf8.decoder.bind(pairRes).join();

      if (pairRes.statusCode == HttpStatus.forbidden) {
        final err = jsonDecode(pairBodyStr) as Map<String, dynamic>;
        final left = err['attemptsLeft'] ?? 0;
        throw Exception('PIN kodu hatalı! Kalan hak: $left');
      }
      if (pairRes.statusCode == HttpStatus.gone) {
        throw Exception('Oturum güvenlik nedeniyle kapatıldı. Karşı cihazda yeni kod üretin.');
      }
      if (pairRes.statusCode != HttpStatus.ok) {
        throw Exception('Eşleştirme başarısız oldu (${pairRes.statusCode}).');
      }

      // 4. Decrypt AES-256-GCM pairing package
      final encryptedMap = jsonDecode(pairBodyStr) as Map<String, dynamic>;
      final decryptedJson = await _cryptoService.decryptData(
        ciphertextBase64: encryptedMap['ciphertext'] as String,
        ivBase64: encryptedMap['iv'] as String,
        macBase64: encryptedMap['mac'] as String,
        masterKey: sessionKeyBytes,
      );

      return PairingPayload.fromJsonString(decryptedJson);
    } finally {
      CryptoService.wipe(sessionKeyBytes);
      client.close();
    }
  }

  /// Listens for LAN UDP broadcasts from host devices
  static Future<RawDatagramSocket?> startDiscoveryListener(
    void Function(DiscoveredPairingDevice device) onDeviceFound,
  ) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        PairingHostSession.discoveryUdpPort,
        reuseAddress: true,
      );
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) return;
          try {
            final msg = utf8.decode(datagram.data);
            final data = jsonDecode(msg) as Map<String, dynamic>;
            if (data['app'] == 'MultiPad' && data['port'] != null) {
              final ips = (data['ips'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .where((e) => e.isNotEmpty)
                      .toList() ??
                  [];
              final senderIp = datagram.address.address;
              final preferredIp =
                  (senderIp.isNotEmpty && !senderIp.startsWith('0.'))
                      ? senderIp
                      : (ips.isNotEmpty ? ips.first : senderIp);
              final combinedIps = <String>[
                if (preferredIp.isNotEmpty) preferredIp,
                ...ips.where((ip) => ip != preferredIp),
              ];

              onDeviceFound(DiscoveredPairingDevice(
                sessionId: data['id'] as String? ?? preferredIp,
                deviceName: data['device'] as String? ?? 'MultiPad Cihazı',
                ip: preferredIp,
                allIps: combinedIps,
                port: data['port'] as int,
                lastSeen: DateTime.now(),
              ));
            }
          } catch (_) {}
        }
      });
      return socket;
    } catch (e) {
      debugPrint('Could not bind UDP discovery listener: $e');
      return null;
    }
  }

  /// Exports a portable encrypted setup token (`MPSETUP:...`) for remote / different-network transfer
  Future<String> createEncryptedSetupToken({
    required PairingPayload payload,
    required String passphrase,
  }) async {
    final cleanPass = passphrase.trim();
    if (cleanPass.length < 6) {
      throw Exception('Aktarım şifresi / PIN en az 6 karakter olmalıdır.');
    }

    final salt = _cryptoService.generateArgon2idSalt();
    List<int>? key;
    try {
      key = await _cryptoService.deriveMasterKey(cleanPass, salt);
      final encrypted = await _cryptoService.encryptData(payload.toJsonString(), key);
      final wrapper = jsonEncode({
        'v': 2,
        's': salt,
        'iv': encrypted.iv,
        'mac': encrypted.mac,
        'd': encrypted.ciphertext,
      });
      return 'MPSETUP:${base64UrlEncode(utf8.encode(wrapper))}';
    } finally {
      CryptoService.wipe(key);
    }
  }

  /// Decrypts a portable `MPSETUP:...` token using the passphrase
  Future<PairingPayload> parseEncryptedSetupToken({
    required String token,
    required String passphrase,
  }) async {
    String clean = token.trim();
    if (!clean.startsWith('MPSETUP:')) {
      throw Exception('Geçersiz kurulum kodu biçimi. Kod "MPSETUP:" ile başlamalıdır.');
    }
    clean = clean.substring('MPSETUP:'.length).trim();

    List<int>? key;
    try {
      final wrapperJson = utf8.decode(base64Url.decode(clean));
      final wrapper = jsonDecode(wrapperJson) as Map<String, dynamic>;
      final salt = wrapper['s'] as String;
      final iv = wrapper['iv'] as String;
      final mac = wrapper['mac'] as String;
      final data = wrapper['d'] as String;

      key = await _cryptoService.deriveMasterKey(passphrase.trim(), salt);
      final decryptedJson = await _cryptoService.decryptData(
        ciphertextBase64: data,
        ivBase64: iv,
        macBase64: mac,
        masterKey: key,
      );

      return PairingPayload.fromJsonString(decryptedJson);
    } catch (e) {
      throw Exception('Aktarım kodu çözülemedi. PIN/şifre hatalı veya kod eksik kopyalanmış olabilir.');
    } finally {
      CryptoService.wipe(key);
    }
  }
}
