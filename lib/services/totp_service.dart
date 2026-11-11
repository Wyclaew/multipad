import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_pkg;

/// Supported HMAC algorithms for RFC 6238 TOTP generation.
enum TotpAlgorithm { sha1, sha256, sha512 }

extension TotpAlgorithmX on TotpAlgorithm {
  String get uriName {
    switch (this) {
      case TotpAlgorithm.sha1:
        return 'SHA1';
      case TotpAlgorithm.sha256:
        return 'SHA256';
      case TotpAlgorithm.sha512:
        return 'SHA512';
    }
  }

  static TotpAlgorithm parse(String? raw) {
    final norm = (raw ?? '')
        .trim()
        .toUpperCase()
        .replaceAll('-', '')
        .replaceAll('_', '');
    switch (norm) {
      case 'SHA256':
      case 'HMACSHA256':
        return TotpAlgorithm.sha256;
      case 'SHA512':
      case 'HMACSHA512':
        return TotpAlgorithm.sha512;
      case 'SHA1':
      case 'HMACSHA1':
      default:
        return TotpAlgorithm.sha1;
    }
  }
}

class ParsedOtpAuthUri {
  final String secret;
  final String issuer;
  final String accountName;
  final int period;
  final int digits;
  final TotpAlgorithm algorithm;

  const ParsedOtpAuthUri({
    required this.secret,
    this.issuer = '',
    this.accountName = '',
    this.period = 30,
    this.digits = 6,
    this.algorithm = TotpAlgorithm.sha1,
  });

  bool get hasCustomParameters =>
      algorithm != TotpAlgorithm.sha1 || digits != 6 || period != 30;
}

class TotpDetailedCode {
  final String code;
  final String nextCode;
  final int remainingSeconds;
  final int period;
  final int digits;
  final TotpAlgorithm algorithm;
  final String issuer;
  final String accountName;
  final String normalizedSecret;

  const TotpDetailedCode({
    required this.code,
    required this.nextCode,
    required this.remainingSeconds,
    required this.period,
    required this.digits,
    required this.algorithm,
    required this.issuer,
    required this.accountName,
    required this.normalizedSecret,
  });

  bool get isValid => code.isNotEmpty;

  double get progress =>
      period <= 0 ? 0.0 : (remainingSeconds / period).clamp(0.0, 1.0);

  String get formattedCode => TotpService.formatCode(code);

  String get formattedNextCode => TotpService.formatCode(nextCode);
}

class TotpService {
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Normalizes a Base32 secret (strips whitespace, hyphens, padding, uppercases).
  static String normalizeBase32(String input) {
    return input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-=]'), '');
  }

  /// Checks whether [input] decodes to a non-empty Base32 secret.
  static bool isValidBase32(String input) => decodeBase32(input).isNotEmpty;

  /// Encodes raw bytes to unpadded RFC 4648 Base32 uppercase string.
  static String encodeBase32(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final buffer = StringBuffer();
    int bitBuffer = 0;
    int bitsLeft = 0;

    for (final b in bytes) {
      bitBuffer = (bitBuffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        final index = (bitBuffer >> (bitsLeft - 5)) & 0x1f;
        buffer.write(_base32Alphabet[index]);
        bitsLeft -= 5;
      }
    }

    if (bitsLeft > 0) {
      final index = (bitBuffer << (5 - bitsLeft)) & 0x1f;
      buffer.write(_base32Alphabet[index]);
    }

    return buffer.toString();
  }

  /// Parses `otpauth://totp/...` URIs as emitted by 2FA providers and authenticators.
  static ParsedOtpAuthUri? parseOtpAuthUri(String input) {
    final trimmed = input.trim();
    if (!trimmed.toLowerCase().startsWith('otpauth://')) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.toLowerCase() != 'totp') return null;

    final secret = normalizeBase32(uri.queryParameters['secret'] ?? '');
    if (secret.isEmpty || decodeBase32(secret).isEmpty) return null;

    final rawPath = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.join('/')
        : uri.path.replaceFirst(RegExp(r'^/+'), '');
    final decodedLabel = _safeUriDecode(rawPath);

    String issuerFromLabel = '';
    String accountName = decodedLabel;
    final colonIdx = decodedLabel.indexOf(':');
    if (colonIdx >= 0) {
      issuerFromLabel = decodedLabel.substring(0, colonIdx).trim();
      accountName = decodedLabel.substring(colonIdx + 1).trim();
    }

    final issuerParam = (uri.queryParameters['issuer'] ?? '').trim();
    final issuer = issuerParam.isNotEmpty ? issuerParam : issuerFromLabel;

    final rawPeriod = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;
    final period = rawPeriod > 0 && rawPeriod <= 3600 ? rawPeriod : 30;

    final rawDigits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    final digits = (rawDigits == 6 || rawDigits == 8 || (rawDigits >= 4 && rawDigits <= 10))
        ? rawDigits
        : 6;

    final algorithm = TotpAlgorithmX.parse(uri.queryParameters['algorithm']);

    return ParsedOtpAuthUri(
      secret: secret,
      issuer: issuer,
      accountName: accountName,
      period: period,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Builds a canonical `otpauth://totp/...` URI from parameters.
  static String buildOtpAuthUri({
    required String secret,
    String issuer = '',
    String accountName = '',
    int period = 30,
    int digits = 6,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
  }) {
    final normSecret = normalizeBase32(secret);
    final cleanIssuer = issuer.trim();
    final cleanAccount = accountName.trim();
    final label = cleanIssuer.isNotEmpty && cleanAccount.isNotEmpty
        ? '$cleanIssuer:$cleanAccount'
        : (cleanAccount.isNotEmpty
            ? cleanAccount
            : (cleanIssuer.isNotEmpty ? cleanIssuer : 'MultiPad 2FA'));

    final params = <String, String>{
      'secret': normSecret,
    };
    if (cleanIssuer.isNotEmpty) {
      params['issuer'] = cleanIssuer;
    }
    if (algorithm != TotpAlgorithm.sha1) {
      params['algorithm'] = algorithm.uriName;
    }
    if (digits != 6) {
      params['digits'] = '$digits';
    }
    if (period != 30) {
      params['period'] = '$period';
    }

    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      pathSegments: [label],
      queryParameters: params,
    ).toString();
  }

  /// Chooses compact Base32 storage when defaults (`SHA1`, `6` digits, `30`s) apply,
  /// or full `otpauth://totp/...` URI so custom algorithm/digits/period persist cleanly.
  static String formatForVaultStorage({
    required String secret,
    String issuer = '',
    String accountName = '',
    int period = 30,
    int digits = 6,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
  }) {
    final normSecret = normalizeBase32(secret);
    if (normSecret.isEmpty) return '';
    if (algorithm == TotpAlgorithm.sha1 && digits == 6 && period == 30) {
      return normSecret;
    }
    return buildOtpAuthUri(
      secret: normSecret,
      issuer: issuer,
      accountName: accountName,
      period: period,
      digits: digits,
      algorithm: algorithm,
    );
  }

  /// Extracts the normalized Base32 secret from either an `otpauth://` URI or plain Base32.
  static String extractNormalizedSecret(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase().startsWith('otpauth://')) {
      return parseOtpAuthUri(trimmed)?.secret ?? '';
    }
    return normalizeBase32(trimmed);
  }

  /// Generates current + next-window TOTP details from a Base32 secret or `otpauth://` URI.
  static TotpDetailedCode generateDetailed(
    String rawInput, {
    int? timeMs,
  }) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const TotpDetailedCode(
        code: '',
        nextCode: '',
        remainingSeconds: 30,
        period: 30,
        digits: 6,
        algorithm: TotpAlgorithm.sha1,
        issuer: '',
        accountName: '',
        normalizedSecret: '',
      );
    }

    final parsed = parseOtpAuthUri(trimmed);
    final secret = parsed?.secret ?? normalizeBase32(trimmed);
    final period = parsed?.period ?? 30;
    final digits = parsed?.digits ?? 6;
    final algorithm = parsed?.algorithm ?? TotpAlgorithm.sha1;
    final issuer = parsed?.issuer ?? '';
    final accountName = parsed?.accountName ?? '';

    final nowMs = timeMs ?? DateTime.now().millisecondsSinceEpoch;
    final code = generateCode(
          secret,
          period: period,
          digits: digits,
          algorithm: algorithm,
          timeMs: nowMs,
        ) ??
        '';
    final nextCode = code.isEmpty
        ? ''
        : (generateCode(
              secret,
              period: period,
              digits: digits,
              algorithm: algorithm,
              timeMs: nowMs + period * 1000,
            ) ??
            '');
    final remaining = getRemainingSeconds(period: period, timeMs: nowMs);

    return TotpDetailedCode(
      code: code,
      nextCode: nextCode,
      remainingSeconds: remaining,
      period: period,
      digits: digits,
      algorithm: algorithm,
      issuer: issuer,
      accountName: accountName,
      normalizedSecret: secret,
    );
  }

  /// Generates a current RFC 6238 TOTP code from a Base32 secret or `otpauth://totp/` URI.
  /// Returns `null` when the input cannot be decoded to a valid key.
  static String? generateCode(
    String rawSecret, {
    int period = 30,
    int digits = 6,
    TotpAlgorithm? algorithm,
    int? timeMs,
  }) {
    final trimmed = rawSecret.trim();
    if (trimmed.isEmpty) return null;

    final parsed = parseOtpAuthUri(trimmed);
    final secretStr = parsed?.secret ?? trimmed;
    final effectivePeriod = parsed?.period ?? period;
    final effectiveDigits = parsed?.digits ?? digits;
    final effectiveAlgorithm = algorithm ?? parsed?.algorithm ?? TotpAlgorithm.sha1;

    if (effectivePeriod <= 0) return null;

    final keyBytes = decodeBase32(secretStr);
    if (keyBytes.isEmpty) return null;

    final nowMs = timeMs ?? DateTime.now().millisecondsSinceEpoch;
    final counter = (nowMs ~/ 1000) ~/ effectivePeriod;

    final counterBytes = Uint8List(8);
    var value = counter;
    for (int i = 7; i >= 0; i--) {
      counterBytes[i] = value & 0xff;
      value >>= 8;
    }

    final hash = switch (effectiveAlgorithm) {
      TotpAlgorithm.sha1 => crypto_pkg.sha1,
      TotpAlgorithm.sha256 => crypto_pkg.sha256,
      TotpAlgorithm.sha512 => crypto_pkg.sha512,
    };

    final hmac = crypto_pkg.Hmac(hash, keyBytes);
    final digest = hmac.convert(counterBytes).bytes;

    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);

    final mod = _pow10(effectiveDigits);
    final otp = binary % mod;
    return otp.toString().padLeft(effectiveDigits, '0');
  }

  static int getRemainingSeconds({int period = 30, int? timeMs}) {
    if (period <= 0) return 30;
    final nowSeconds = (timeMs ?? DateTime.now().millisecondsSinceEpoch) ~/ 1000;
    final elapsed = nowSeconds % period;
    return period - elapsed;
  }

  static double getProgress({int period = 30, int? timeMs}) {
    if (period <= 0) return 1.0;
    return getRemainingSeconds(period: period, timeMs: timeMs) / period;
  }

  /// Formats a numeric TOTP code for readability (e.g. `123 456` or `1234 5678`).
  static String formatCode(String code) {
    if (code.length == 6) {
      return '${code.substring(0, 3)} ${code.substring(3)}';
    }
    if (code.length == 8) {
      return '${code.substring(0, 4)} ${code.substring(4)}';
    }
    return code;
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (int i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static String _safeUriDecode(String input) {
    try {
      return Uri.decodeComponent(input);
    } catch (_) {
      return input;
    }
  }

  /// Decodes a Base32 string into raw secret bytes (returns empty on malformed chars).
  static List<int> decodeBase32(String input) {
    final cleaned = normalizeBase32(input);
    if (cleaned.isEmpty) return [];

    final List<int> out = [];
    int buffer = 0;
    int bitsLeft = 0;

    for (int i = 0; i < cleaned.length; i++) {
      final charIndex = _base32Alphabet.indexOf(cleaned[i]);
      if (charIndex < 0) return [];
      buffer = (buffer << 5) | charIndex;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        out.add((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }
    return out;
  }
}
