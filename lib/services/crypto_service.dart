import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../constants.dart';

class EncryptedPayload {
  final String ciphertext; // Base64
  final String iv; // Base64
  final String mac; // Base64

  EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertext,
        'iv': iv,
        'mac': mac,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      ciphertext: json['ciphertext'] as String,
      iv: json['iv'] as String,
      mac: json['mac'] as String,
    );
  }
}

class CryptoService {
  final AesGcm _aesGcm = AesGcm.with256bits();

  /// Generates a cryptographically secure random byte buffer.
  Uint8List generateRandomBytes(int length) {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Generates a 32-byte salt.
  /// When [useArgon2id] is true, formats the salt string with Argon2id
  /// parameters (`v2:argon2id:m<KiB>:t<iter>:p<par>:<base64>`) so legacy
  /// Supabase deployments without extra schema columns store KDF metadata seamlessly.
  String generateSalt({bool useArgon2id = false}) {
    final saltBytes = generateRandomBytes(32);
    final b64 = base64Encode(saltBytes);
    if (!useArgon2id) return b64;
    return 'v2:argon2id:m${AppConstants.argon2MemoryKib}:t${AppConstants.argon2Iterations}:p${AppConstants.argon2Parallelism}:$b64';
  }

  String generateArgon2idSalt() => generateSalt(useArgon2id: true);

  static bool isArgon2idSalt(String saltSpec) {
    return saltSpec.startsWith('v2:argon2id:');
  }

  /// Derives the 256-bit Master Key from [masterPassword] and [saltSpec] off the UI isolate.
  /// Supports both legacy raw Base64 PBKDF2-HMAC-SHA256 salts and `v2:argon2id:...` salts.
  /// Always returns a mutable [Uint8List] so callers can safely wipe it afterwards.
  Future<Uint8List> deriveMasterKey(
    String masterPassword,
    String saltSpec,
  ) async {
    return Isolate.run(
      () => _deriveKeyIsolate(masterPassword, saltSpec),
    );
  }

  static Future<Uint8List> _deriveKeyIsolate(
    String masterPassword,
    String saltSpec,
  ) async {
    if (saltSpec.startsWith('v2:argon2id:')) {
      final parts = saltSpec.split(':');
      if (parts.length != 6) {
        throw const FormatException('Invalid Argon2id salt format');
      }
      final memoryKib = int.parse(parts[2].substring(1));
      final iterations = int.parse(parts[3].substring(1));
      final parallelism = int.parse(parts[4].substring(1));
      final saltBytes = base64Decode(parts[5]);

      final argon2 = Argon2id(
        memory: memoryKib,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: AppConstants.keyLength,
      );
      final secretKey = await argon2.deriveKeyFromPassword(
        password: masterPassword,
        nonce: saltBytes,
      );
      final extracted = await secretKey.extractBytes();
      return Uint8List.fromList(extracted);
    }

    final Uint8List saltBytes = base64Decode(saltSpec);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: AppConstants.pbkdf2Iterations,
      bits: 256,
    );
    final SecretKey secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: saltBytes,
    );
    final extracted = await secretKey.extractBytes();
    return Uint8List.fromList(extracted);
  }

  /// Derives a 256-bit wrapping key from a local PIN using PBKDF2.
  Future<Uint8List> derivePinWrappingKey(String pin, String saltBase64) async {
    return Isolate.run(() async {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 50000,
        bits: 256,
      );
      final secretKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode('multipad_pin_v1:$pin')),
        nonce: base64Decode(saltBase64),
      );
      return Uint8List.fromList(await secretKey.extractBytes());
    });
  }

  /// Derives a verification tag for Duress password checking.
  String deriveDuressVerifier(List<int> duressKey) {
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, duressKey);
    final digest = hmac.convert(utf8.encode('multipad_duress_verifier_v1'));
    return base64Encode(digest.bytes);
  }

  /// Derives the Auth Password string sent to Supabase Auth.
  /// The user's actual master password NEVER leaves the device.
  String deriveAuthPassword(List<int> masterKey) {
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, masterKey);
    final digest = hmac.convert(utf8.encode('multipad_auth_token_v1'));
    return base64Encode(digest.bytes);
  }

  /// Encrypts a plaintext string using AES-256-GCM.
  /// Generates a new 12-byte random nonce for every operation.
  Future<EncryptedPayload> encryptData(
    String plaintext,
    List<int> masterKey,
  ) async {
    return encryptBytes(utf8.encode(plaintext), masterKey);
  }

  /// Encrypts raw binary data (e.g. encrypted attachments) using AES-256-GCM.
  Future<EncryptedPayload> encryptBytes(
    List<int> plaintextBytes,
    List<int> masterKey,
  ) async {
    final SecretKey secretKey = SecretKey(masterKey);
    final SecretBox secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
    );

    return EncryptedPayload(
      ciphertext: base64Encode(secretBox.cipherText),
      iv: base64Encode(secretBox.nonce),
      mac: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypts AES-256-GCM ciphertext into a UTF-8 string.
  /// Throws an exception if the key is incorrect or if data has been tampered with.
  Future<String> decryptData({
    required String ciphertextBase64,
    required String ivBase64,
    required String macBase64,
    required List<int> masterKey,
  }) async {
    final decryptedBytes = await decryptBytes(
      ciphertextBase64: ciphertextBase64,
      ivBase64: ivBase64,
      macBase64: macBase64,
      masterKey: masterKey,
    );
    return utf8.decode(decryptedBytes);
  }

  /// Decrypts AES-256-GCM ciphertext into raw bytes.
  Future<Uint8List> decryptBytes({
    required String ciphertextBase64,
    required String ivBase64,
    required String macBase64,
    required List<int> masterKey,
  }) async {
    final SecretKey secretKey = SecretKey(masterKey);
    final List<int> cipherText = base64Decode(ciphertextBase64);
    final List<int> nonce = base64Decode(ivBase64);
    final List<int> macBytes = base64Decode(macBase64);

    final SecretBox secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final List<int> decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decryptedBytes);
  }

  /// Computes SHA-256 hex digest (used for sync conflict base hashing and update checks).
  static String sha256Hex(String input) {
    return crypto_pkg.sha256.convert(utf8.encode(input)).toString();
  }

  static String sha256HexBytes(List<int> bytes) {
    return crypto_pkg.sha256.convert(bytes).toString();
  }

  /// Constant-time byte comparison to prevent timing side-channel attacks.
  /// Accumulates length differences into bitwise OR rather than early exiting,
  /// preventing length discrepancy information leakage via execution timing.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    int diff = a.length ^ b.length;
    final minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Constant-time string comparison.
  static bool constantTimeStringEquals(String a, String b) {
    return constantTimeEquals(utf8.encode(a), utf8.encode(b));
  }

  /// Safely wipes sensitive byte arrays in RAM with zeros.
  /// Never throws even if given a fixed/unmodifiable list view.
  static void wipe(List<int>? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      try {
        bytes.fillRange(0, bytes.length, 0);
      } catch (_) {
        // Unmodifiable Uint8List views (e.g. from external crypto libraries) cannot be mutated in-place.
      }
    }
  }

  /// RFC 5869 HKDF-Expand with HMAC-SHA256 producing a subkey of requested length.
  static Uint8List hkdfExpandSha256(List<int> prk, String info, [int length = 32]) {
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, prk);
    final infoBytes = utf8.encode(info);
    final output = <int>[];
    List<int> t = [];
    int blockIndex = 1;
    while (output.length < length) {
      final input = <int>[...t, ...infoBytes, blockIndex];
      t = hmac.convert(input).bytes;
      output.addAll(t);
      blockIndex++;
    }
    return Uint8List.fromList(output.sublist(0, length));
  }

  /// Derives Bitwarden-compatible encryption and MAC keys from password and salt.
  Future<({Uint8List encKey, Uint8List macKey})> deriveBitwardenSubKeys({
    required String password,
    required String salt,
    int kdfType = 0,
    int? iterations,
    int? kdfIterations,
    int? memoryKib,
    int? kdfMemory,
    int? parallelism,
    int? kdfParallelism,
  }) async {
    final actualIterations = iterations ?? kdfIterations ?? 100000;
    final actualMemory = memoryKib ?? kdfMemory ?? 64;
    final actualParallelism = parallelism ?? kdfParallelism ?? 4;

    return Isolate.run(() async {
      List<int> saltBytes;
      try {
        saltBytes = base64Decode(salt);
        if (saltBytes.isEmpty) {
          saltBytes = utf8.encode(salt.toLowerCase().trim());
        }
      } catch (_) {
        saltBytes = utf8.encode(salt.toLowerCase().trim());
      }

      Uint8List masterKeyBytes;
      if (kdfType == 1) {
        // Argon2id: Bitwarden memory is in MB or KiB
        final memKib = actualMemory > 1024 ? actualMemory : actualMemory * 1024;
        final iters = actualIterations > 0 ? actualIterations : 3;
        final par = actualParallelism > 0 ? actualParallelism : 4;

        final argon2 = Argon2id(
          memory: memKib,
          iterations: iters,
          parallelism: par,
          hashLength: 32,
        );
        final secretKey = await argon2.deriveKeyFromPassword(
          password: password,
          nonce: saltBytes,
        );
        masterKeyBytes = Uint8List.fromList(await secretKey.extractBytes());
      } else {
        // PBKDF2-HMAC-SHA256
        final iters = actualIterations > 0 ? actualIterations : 100000;
        final pbkdf2 = Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: iters,
          bits: 256,
        );
        final secretKey = await pbkdf2.deriveKey(
          secretKey: SecretKey(utf8.encode(password)),
          nonce: saltBytes,
        );
        masterKeyBytes = Uint8List.fromList(await secretKey.extractBytes());
      }

      final encKey = hkdfExpandSha256(masterKeyBytes, 'enc', 32);
      final macKey = hkdfExpandSha256(masterKeyBytes, 'mac', 32);
      CryptoService.wipe(masterKeyBytes);

      return (encKey: encKey, macKey: macKey);
    });
  }

  /// Encrypts plaintext string into Bitwarden CipherString format: `2.<iv>|<ciphertext>|<mac>`.
  Future<String> encryptBitwardenCipherString({
    required String plaintext,
    required List<int> encKey,
    required List<int> macKey,
    List<int>? ivOverride,
  }) async {
    final iv = ivOverride != null
        ? Uint8List.fromList(ivOverride)
        : generateRandomBytes(16);

    final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
    final secretBox = await aesCbc.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(encKey),
      nonce: iv,
    );

    final ivB64 = base64Encode(iv);
    final cipherB64 = base64Encode(secretBox.cipherText);

    final macPayload = Uint8List.fromList([...iv, ...secretBox.cipherText]);
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, macKey);
    final macDigest = hmac.convert(macPayload);
    final macB64 = base64Encode(macDigest.bytes);

    return '2.$ivB64|$cipherB64|$macB64';
  }

  /// Decrypts a Bitwarden CipherString (`2.<iv>|<ciphertext>|<mac>`) with HMAC-SHA256 verification.
  Future<String> decryptBitwardenCipherString({
    required String cipherString,
    required List<int> encKey,
    required List<int> macKey,
  }) async {
    if (!cipherString.startsWith('2.')) {
      throw const FormatException('Unsupported or invalid Bitwarden encType');
    }
    final raw = cipherString.substring(2);
    final parts = raw.split('|');
    if (parts.length != 3) {
      throw const FormatException('Invalid Bitwarden CipherString structure');
    }

    final Uint8List iv;
    final Uint8List cipherText;
    final Uint8List expectedMac;
    try {
      iv = base64Decode(parts[0]);
      cipherText = base64Decode(parts[1]);
      expectedMac = base64Decode(parts[2]);
    } catch (e) {
      throw FormatException('Invalid base64 in Bitwarden CipherString: $e');
    }

    if (iv.length != 16) {
      throw const FormatException('Invalid IV length for AES-CBC');
    }

    // Verify HMAC-SHA256 in constant time
    final macPayload = Uint8List.fromList([...iv, ...cipherText]);
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, macKey);
    final calculatedMac = hmac.convert(macPayload).bytes;

    if (!CryptoService.constantTimeEquals(calculatedMac, expectedMac)) {
      throw const FormatException('Bitwarden MAC verification failed (wrong password or tampered data)');
    }

    try {
      final aesCbc = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);
      final decryptedBytes = await aesCbc.decrypt(
        SecretBox(cipherText, nonce: iv, mac: Mac.empty),
        secretKey: SecretKey(encKey),
      );
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw FormatException('Bitwarden AES-CBC decryption failed: $e');
    }
  }

  /// High-level decryption of a Bitwarden password-protected encrypted JSON export string.
  Future<String> decryptBitwardenJson(String rawJson, String password) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Bitwarden JSON export structure');
    }
    final salt = (decoded['salt'] ?? decoded['userEmail'] ?? '').toString();
    if (salt.isEmpty) {
      throw const FormatException('Bitwarden encrypted export missing salt');
    }
    final kdfType = (decoded['kdfType'] ?? decoded['kdf'] ?? 0) as int;
    final kdfIterations = (decoded['kdfIterations'] ?? decoded['iterations'] ?? 100000) as int;
    final kdfMemory = (decoded['kdfMemory'] ?? decoded['memory'] ?? 64) as int;
    final kdfParallelism = (decoded['kdfParallelism'] ?? decoded['parallelism'] ?? 4) as int;
    final cipherString = decoded['data']?.toString();

    if (cipherString == null || cipherString.isEmpty) {
      throw const FormatException('Bitwarden encrypted JSON missing data cipherstring');
    }

    final subkeys = await deriveBitwardenSubKeys(
      password: password,
      salt: salt,
      kdfType: kdfType,
      iterations: kdfIterations,
      memoryKib: kdfMemory,
      parallelism: kdfParallelism,
    );

    try {
      return await decryptBitwardenCipherString(
        cipherString: cipherString,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );
    } finally {
      CryptoService.wipe(subkeys.encKey);
      CryptoService.wipe(subkeys.macKey);
    }
  }
}
