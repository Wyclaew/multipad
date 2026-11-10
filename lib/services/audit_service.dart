import '../models/vault_item.dart';

class AuditIssue {
  final String itemId;
  final String title;
  final String issueType; // 'weak', 'reused', 'missing_2fa', 'expired'
  final String description;
  final int severity;    // 1: low, 2: medium, 3: high

  AuditIssue({
    required this.itemId,
    required this.title,
    required this.issueType,
    required this.description,
    required this.severity,
  });
}

class AuditReport {
  final int overallScore; // 0 to 100
  final int totalAccounts;
  final int weakPasswordsCount;
  final int reusedPasswordsCount;
  final int missing2faCount;
  final int expiredPasswordsCount;
  final List<AuditIssue> issues;

  AuditReport({
    required this.overallScore,
    required this.totalAccounts,
    required this.weakPasswordsCount,
    required this.reusedPasswordsCount,
    required this.missing2faCount,
    required this.expiredPasswordsCount,
    required this.issues,
  });
}

class AuditService {
  /// Evaluates the password health and security of all credentials in the vault.
  static AuditReport analyzeVault(List<VaultItem> items, {int globalExpiryDays = 90}) {
    final credentials = items.where((i) => i.type == VaultItemType.credential && !i.isTrash && !i.isDeleted).toList();

    final List<AuditIssue> issues = [];
    final Map<String, List<VaultItem>> passwordOccurrences = {};

    int weakCount = 0;
    int missing2faCount = 0;
    int expiredCount = 0;

    for (final item in credentials) {
      final pass = item.password;

      // Track password occurrences for reuse detection
      if (pass.isNotEmpty) {
        passwordOccurrences.putIfAbsent(pass, () => []).add(item);
      }

      // Check weakness
      final isWeak = _isPasswordWeak(pass);
      if (isWeak) {
        weakCount++;
        issues.add(AuditIssue(
          itemId: item.id,
          title: item.title,
          issueType: 'weak',
          description: pass.length < 8
              ? 'Şifre çok kısa (8 karakterden az).'
              : 'Şifre zayıf (rakam, büyük harf veya sembol eksik).',
          severity: 3,
        ));
      }

      // Check 2FA
      if (item.totpSecret.trim().isEmpty) {
        missing2faCount++;
        issues.add(AuditIssue(
          itemId: item.id,
          title: item.title,
          issueType: 'missing_2fa',
          description: '2FA / TOTP koruması eklenmemiş.',
          severity: 1,
        ));
      }

      // Check Password Expiry (Item 30)
      if (item.isPasswordExpired(globalExpiryDays)) {
        expiredCount++;
        issues.add(AuditIssue(
          itemId: item.id,
          title: item.title,
          issueType: 'expired',
          description: 'Şifre yenileme zamanı geldi (${item.passwordAgeDays} gündür güncellenmedi).',
          severity: 2,
        ));
      }
    }

    // Check reused passwords
    int reusedCount = 0;
    for (final entry in passwordOccurrences.entries) {
      if (entry.value.length > 1) {
        reusedCount += entry.value.length;
        for (final item in entry.value) {
          issues.add(AuditIssue(
            itemId: item.id,
            title: item.title,
            issueType: 'reused',
            description: 'Bu şifre başka ${entry.value.length - 1} hesapta daha kullanılıyor.',
            severity: 2,
          ));
        }
      }
    }

    // Calculate score (0-100)
    int score = 100;
    if (credentials.isNotEmpty) {
      final weakPenalty = (weakCount / credentials.length) * 40;
      final reusedPenalty = (reusedCount / credentials.length) * 30;
      final no2faPenalty = (missing2faCount / credentials.length) * 15;
      final expiredPenalty = (expiredCount / credentials.length) * 15;

      score = (100 - (weakPenalty + reusedPenalty + no2faPenalty + expiredPenalty)).round().clamp(10, 100);
    }

    return AuditReport(
      overallScore: score,
      totalAccounts: credentials.length,
      weakPasswordsCount: weakCount,
      reusedPasswordsCount: reusedCount,
      missing2faCount: missing2faCount,
      expiredPasswordsCount: expiredCount,
      issues: issues,
    );
  }

  static bool _isPasswordWeak(String password) {
    if (password.length < 10) return true;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigits = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int criteria = 0;
    if (hasUpper) criteria++;
    if (hasLower) criteria++;
    if (hasDigits) criteria++;
    if (hasSpecial) criteria++;

    return criteria < 3;
  }
}
