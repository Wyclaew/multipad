import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_pkg;

class TotpService {
  /// Base32 Alphabet RFC 4648
  static const String _base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Generates a current 6-digit TOTP code for a given Base32 secret.
  /// Also supports full otpauth:// URI strings!
  /// Returns null if secret is empty or invalid.
  static String? generateCode(String rawSecret, {int? timeMs, int intervalSeconds = 30}) {
    String clean = rawSecret.trim();
    if (clean.isEmpty) return null;

    // Check if input is a full otpauth URI (e.g. otpauth://totp/...?secret=JBSWY3DPEHPK3PXP)
    if (clean.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(clean);
      if (uri != null && uri.queryParameters.containsKey('secret')) {
        clean = uri.queryParameters['secret']!;
      }
    }

    final cleanSecret = clean.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
    if (cleanSecret.isEmpty) return null;

    try {
      final keyBytes = _decodeBase32(cleanSecret);
      if (keyBytes.isEmpty) return null;

      final int currentSec = (timeMs ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000;
      final int counter = currentSec ~/ intervalSeconds;

      final ByteData counterBuffer = ByteData(8);
      counterBuffer.setUint64(0, counter, Endian.big);
      final List<int> counterBytes = counterBuffer.buffer.asUint8List();

      final hmac = crypto_pkg.Hmac(crypto_pkg.sha1, keyBytes);
      final digest = hmac.convert(counterBytes).bytes;

      final int offset = digest[digest.length - 1] & 0x0f;
      final int binary = ((digest[offset] & 0x7f) << 24) |
          ((digest[offset + 1] & 0xff) << 16) |
          ((digest[offset + 2] & 0xff) << 8) |
          (digest[offset + 3] & 0xff);

      final int otp = binary % 1000000;
      return otp.toString().padLeft(6, '0');
    } catch (_) {
      return null;
    }
  }

  /// Returns remaining seconds in the current 30-second window (1 to 30)
  static int getRemainingSeconds({int intervalSeconds = 30}) {
    final int currentSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return intervalSeconds - (currentSec % intervalSeconds);
  }

  /// Returns progress from 0.0 to 1.0 of the current 30-second cycle
  static double getProgress({int intervalSeconds = 30}) {
    final int remaining = getRemainingSeconds(intervalSeconds: intervalSeconds);
    return remaining / intervalSeconds;
  }

  /// Decodes RFC 4648 Base32 string to bytes
  static Uint8List _decodeBase32(String input) {
    // Remove padding characters '='
    final sanitized = input.replaceAll('=', '');
    final List<int> bytes = [];

    int buffer = 0;
    int bitsLeft = 0;

    for (int i = 0; i < sanitized.length; i++) {
      final char = sanitized[i];
      final val = _base32Chars.indexOf(char);
      if (val == -1) continue;

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bytes.add((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }

    return Uint8List.fromList(bytes);
  }
}
