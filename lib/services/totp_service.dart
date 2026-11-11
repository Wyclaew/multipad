import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_pkg;

class ParsedOtpAuthUri {
  final String secret;
  final String issuer;
  final String accountName;
  final int period;
  final int digits;

  const ParsedOtpAuthUri({
    required this.secret,
    this.issuer = '',
    this.accountName = '',
    this.period = 30,
    this.digits = 6,
  });
}

class TotpService {
  /// Base32 Alphabet RFC 4648
  static const String _base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Parses an `otpauth://totp/...` URI into structured components, or returns null.
  static ParsedOtpAuthUri? parseOtpAuthUri(String raw) {
    final clean = raw.trim();
    if (!clean.toLowerCase().startsWith('otpauth://')) return null;
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;
    final secret = uri.queryParameters['secret']?.trim();
    if (secret == null || secret.isEmpty) return null;

    var label = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    label = Uri.decodeComponent(label);
    String issuer = uri.queryParameters['issuer']?.trim() ?? '';
    String account = label;
    if (label.contains(':')) {
      final parts = label.split(':');
      if (issuer.isEmpty) issuer = parts.first.trim();
      account = parts.sublist(1).join(':').trim();
    }
    final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;
    final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    return ParsedOtpAuthUri(
      secret: secret.replaceAll(' ', '').toUpperCase(),
      issuer: issuer,
      accountName: account,
      period: period > 0 ? period : 30,
      digits: (digits >= 6 && digits <= 8) ? digits : 6,
    );
  }

  /// Generates a current TOTP code (typically 6 digits) for a given Base32 secret or `otpauth://` URI.
  /// Returns null if secret is empty or invalid.
  static String? generateCode(
    String rawSecret, {
    int? timeMs,
    int intervalSeconds = 30,
    int digits = 6,
  }) {
    String clean = rawSecret.trim();
    if (clean.isEmpty) return null;

    int effectiveInterval = intervalSeconds;
    int effectiveDigits = digits;

    if (clean.toLowerCase().startsWith('otpauth://')) {
      final parsed = parseOtpAuthUri(clean);
      if (parsed == null) return null;
      clean = parsed.secret;
      effectiveInterval = parsed.period;
      effectiveDigits = parsed.digits;
    }

    final cleanSecret =
        clean.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
    if (cleanSecret.isEmpty) return null;

    try {
      final keyBytes = _decodeBase32(cleanSecret);
      if (keyBytes.isEmpty) return null;

      final int currentSec =
          (timeMs ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000;
      final int counter = currentSec ~/ effectiveInterval;

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

      int mod = 1;
      for (int i = 0; i < effectiveDigits; i++) {
        mod *= 10;
      }
      final int otp = binary % mod;
      return otp.toString().padLeft(effectiveDigits, '0');
    } catch (_) {
      return null;
    }
  }

  /// Returns remaining seconds in the current window (1 to intervalSeconds)
  static int getRemainingSeconds({int intervalSeconds = 30}) {
    final int currentSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return intervalSeconds - (currentSec % intervalSeconds);
  }

  /// Returns progress from 0.0 to 1.0 of the current cycle
  static double getProgress({int intervalSeconds = 30}) {
    final int remaining =
        getRemainingSeconds(intervalSeconds: intervalSeconds);
    return remaining / intervalSeconds;
  }

  /// Decodes RFC 4648 Base32 string to bytes
  static Uint8List _decodeBase32(String input) {
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
