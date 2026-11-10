import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_pkg;
import '../constants.dart';

class EncryptedPayload {
  final String ciphertext; // Base64
  final String iv;         // Base64
  final String mac;        // Base64

  EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
  });
}

class CryptoService {
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: AppConstants.pbkdf2Iterations,
    bits: 256,
  );

  /// Generates a cryptographically secure 32-byte salt as a Base64 string.
  String generateSalt() {
    final Random random = Random.secure();
    final Uint8List saltBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      saltBytes[i] = random.nextInt(256);
    }
    return base64Encode(saltBytes);
  }

  /// Derives the 256-bit Master Key from Master Password and Salt using PBKDF2-HMAC-SHA256.
  Future<List<int>> deriveMasterKey(String masterPassword, String saltBase64) async {
    final Uint8List saltBytes = base64Decode(saltBase64);
    final SecretKey secretKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: saltBytes,
    );
    return await secretKey.extractBytes();
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
  Future<EncryptedPayload> encryptData(String plaintext, List<int> masterKey) async {
    final SecretKey secretKey = SecretKey(masterKey);
    final List<int> plaintextBytes = utf8.encode(plaintext);

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

  /// Decrypts AES-256-GCM ciphertext using the master key, nonce, and MAC tag.
  /// Throws an exception if the key is incorrect or if data has been tampered with.
  Future<String> decryptData({
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

    return utf8.decode(decryptedBytes);
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
  static void wipe(List<int>? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}
