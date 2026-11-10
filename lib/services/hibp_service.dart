import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:http/http.dart' as http;

class HibpResult {
  final bool isCompromised;
  final int breachCount;
  final String? errorMessage;

  HibpResult({
    required this.isCompromised,
    required this.breachCount,
    this.errorMessage,
  });
}

class HibpService {
  /// Checks whether a password has appeared in known data breaches using
  /// Have I Been Pwned's official k-Anonymity API model.
  /// 
  /// The full password and full hash NEVER leave the device!
  /// Only the first 5 characters of the SHA-1 hash are sent to the server.
  static Future<HibpResult> checkPasswordBreach(String password) async {
    if (password.trim().isEmpty) {
      return HibpResult(isCompromised: false, breachCount: 0);
    }

    try {
      // 1. Calculate SHA-1 hash of password
      final bytes = utf8.encode(password);
      final digest = crypto_pkg.sha1.convert(bytes);
      final hash = digest.toString().toUpperCase();

      // 2. Split into 5-char prefix and 35-char suffix
      final prefix = hash.substring(0, 5);
      final suffix = hash.substring(5);

      // 3. Query Cloudflare HIBP API with prefix
      final url = Uri.parse('https://api.pwnedpasswords.com/range/$prefix');
      final response = await http.get(
        url,
        headers: {'Add-Padding': 'true', 'User-Agent': 'MultiPad-Vault-Client'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        return HibpResult(
          isCompromised: false,
          breachCount: 0,
          errorMessage: 'Sızıntı kontrol sunucusuna ulaşılamadı (${response.statusCode})',
        );
      }

      // 4. Parse lines formatted as "HASH_SUFFIX:COUNT"
      final lines = const LineSplitter().convert(response.body);
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final returnedSuffix = parts[0].trim().toUpperCase();
          if (returnedSuffix == suffix) {
            final count = int.tryParse(parts[1].trim()) ?? 1;
            return HibpResult(isCompromised: true, breachCount: count);
          }
        }
      }

      // No match found in the prefix list
      return HibpResult(isCompromised: false, breachCount: 0);
    } catch (e) {
      return HibpResult(
        isCompromised: false,
        breachCount: 0,
        errorMessage: 'Kontrol hatası: $e',
      );
    }
  }
}
