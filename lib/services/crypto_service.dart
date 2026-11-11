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
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
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
}
