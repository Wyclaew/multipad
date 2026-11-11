import '../models/vault_item.dart';

class AuditIssue {
  final String itemId;
  final String title;
  // 'weak', 'reused', 'missing_2fa', 'expired',
  // 'card_invalid', 'card_expired', 'card_expiring_soon',
  // 'phishing_risk', 'insecure_http', 'identity_expiring'
  final String issueType;
  final String description;
  final int severity; // 1: low, 2: medium, 3: high

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
  final int invalidCardsCount;
  final int expiringCardsCount;
  final int phishingRiskCount;
  final List<AuditIssue> issues;

  AuditReport({
    required this.overallScore,
    required this.totalAccounts,
    required this.weakPasswordsCount,
    required this.reusedPasswordsCount,
    required this.missing2faCount,
    required this.expiredPasswordsCount,
    this.invalidCardsCount = 0,
    this.expiringCardsCount = 0,
    this.phishingRiskCount = 0,
    required this.issues,
  });
}

class AuditService {
  static const List<String> _protectedPopularDomains = [
    'google.com',
    'gmail.com',
    'github.com',
    'microsoft.com',
    'apple.com',
    'icloud.com',
    'paypal.com',
    'amazon.com',
    'netflix.com',
    'instagram.com',
    'facebook.com',
    'linkedin.com',
    'dropbox.com',
    'binance.com',
    'garantibbva.com.tr',
    'isbank.com.tr',
    'akbank.com',
    'yapikredi.com.tr',
    'ziraatbank.com.tr',
    'turkiye.gov.tr',
  ];

  /// Validates card number digits using the Luhn checksum algorithm.
  static bool isValidLuhn(String rawCardNumber) {
    final digits = rawCardNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 13 || digits.length > 19) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int n = digits.codeUnitAt(i) - 48;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  /// Detects major card brands by BIN/IIN prefix.
  static String detectCardBrand(String rawCardNumber) {
    final digits = rawCardNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Kart';
    if (digits.startsWith('9792')) return 'TROY';
    if (digits.startsWith('4')) return 'Visa';
    if (RegExp(r'^(5[1-5]|222[1-9]|22[3-9]|2[3-6]|27[01]|2720)').hasMatch(digits)) {
      return 'Mastercard';
    }
    if (digits.startsWith('34') || digits.startsWith('37')) return 'Amex';
    if (digits.startsWith('6011') || digits.startsWith('65')) return 'Discover';
    return 'Kart';
  }

  /// Evaluates MM/YY or MM/YYYY expiry date relative to [now].
  /// Returns `'expired'`, `'expiring_soon'` (<=60 days), or `null` if healthy/empty.
  static String? evaluateCardExpiry(String rawExpiry, {DateTime? now}) {
    final clean = rawExpiry.trim();
    if (clean.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2})\s*[/\-]\s*(\d{2,4})$').firstMatch(clean);
    if (match == null) return null;

    final month = int.tryParse(match.group(1)!) ?? 0;
    var year = int.tryParse(match.group(2)!) ?? 0;
    if (month < 1 || month > 12) return 'expired';
    if (year < 100) year += 2000;

    final ref = now ?? DateTime.now();
    // Card is valid until the last second of that month
    final lastDayOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);
    if (ref.isAfter(lastDayOfMonth)) return 'expired';
    final diff = lastDayOfMonth.difference(ref).inDays;
    if (diff <= 60) return 'expiring_soon';
    return null;
  }

  /// Evaluates generic document/license expiry date (`YYYY-MM-DD` or `DD.MM.YYYY` or `MM/YY`).
  static String? evaluateDocumentExpiry(String rawDate, {DateTime? now}) {
    final clean = rawDate.trim();
    if (clean.isEmpty) return null;
    final cardCheck = evaluateCardExpiry(clean, now: now);
    if (cardCheck != null) return cardCheck;

    DateTime? parsed = DateTime.tryParse(clean);
    if (parsed == null) {
      final dotMatch =
          RegExp(r'^(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})$').firstMatch(clean);
      if (dotMatch != null) {
        final d = int.parse(dotMatch.group(1)!);
        final m = int.parse(dotMatch.group(2)!);
        final y = int.parse(dotMatch.group(3)!);
        parsed = DateTime(y, m, d, 23, 59, 59);
      }
    }
    if (parsed == null) return null;
    final ref = now ?? DateTime.now();
    if (ref.isAfter(parsed)) return 'expired';
    if (parsed.difference(ref).inDays <= 60) return 'expiring_soon';
    return null;
  }

  /// Checks a website URL for phishing indicators: punycode, non-ASCII homographs,
  /// raw IP host, typo lookalike against popular domains, or insecure HTTP.
  static ({String? issueType, String? reason}) checkWebsiteSecurity(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return (issueType: null, reason: null);

    final withScheme =
        trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return (issueType: null, reason: null);
    }

    final host = uri.host.toLowerCase();

    // Non-ASCII characters / Punycode homograph attack
    if (host.contains('xn--') ||
        host.codeUnits.any((c) => c > 127)) {
      return (
        issueType: 'phishing_risk',
        reason: 'Alan adında Punycode veya görsel benzerlik (homograph) riski tespit edildi: $host',
      );
    }

    // Raw IP address login URL
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      return (
        issueType: 'phishing_risk',
        reason: 'Alan adı yerine doğrudan IP adresi kullanılıyor ($host) — kimlik avı riski.',
      );
    }

    // Lookalike / typosquatting detection against popular domains (normalized leetspeak & distance <= 1)
    final registrable = _extractRegistrableDomain(host);
    for (final safeDomain in _protectedPopularDomains) {
      if (registrable == safeDomain) break;
      final safeLabel = safeDomain.split('.').first;
      final hostLabel = registrable.split('.').first;
      if (hostLabel.length >= 4 &&
          (_normalizedLookalike(hostLabel) == safeLabel ||
              _levenshtein(hostLabel, safeLabel) == 1)) {
        return (
          issueType: 'phishing_risk',
          reason: '"$host" alan adı popüler "$safeDomain" sitesini taklit ediyor olabilir.',
        );
      }
    }

    // Explicit non-HTTPS warning
    if (trimmed.toLowerCase().startsWith('http://')) {
      return (
        issueType: 'insecure_http',
        reason: 'Site adresi şifrelenmemiş HTTP kullanıyor (HTTPS önerilir).',
      );
    }

    return (issueType: null, reason: null);
  }

  static String _extractRegistrableDomain(String host) {
    final parts = host.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return host;
    if (parts.length >= 3 &&
        (parts[parts.length - 2] == 'com' ||
            parts[parts.length - 2] == 'gov' ||
            parts[parts.length - 2] == 'org' ||
            parts[parts.length - 2] == 'co') &&
        parts.last.length == 2) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return parts.sublist(parts.length - 2).join('.');
  }

  static String _normalizedLookalike(String s) {
    return s
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('rn', 'm')
        .replaceAll('vv', 'w')
        .replaceAll('5', 's')
        .replaceAll('3', 'e');
  }

  static int _levenshtein(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 99;
    final dp = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (int i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }

  /// Evaluates password, card, identity/license, and domain health across the vault.
  static AuditReport analyzeVault(
    List<VaultItem> items, {
    int globalExpiryDays = 90,
  }) {
    final activeItems = items.where((i) => !i.isTrash && !i.isDeleted).toList();
    final credentials = activeItems
        .where((i) => i.type == VaultItemType.credential)
        .toList();
    final passwordCredentials =
        credentials.where((i) => !i.isTotpOnly).toList();
    final cards =
        activeItems.where((i) => i.type == VaultItemType.card).toList();
    final docs = activeItems
        .where((i) =>
            i.type == VaultItemType.identity ||
            i.type == VaultItemType.license)
        .toList();

    final List<AuditIssue> issues = [];
    final Map<String, List<VaultItem>> passwordOccurrences = {};

    int weakCount = 0;
    int missing2faCount = 0;
    int expiredCount = 0;
    int invalidCardsCount = 0;
    int expiringCardsCount = 0;
    int phishingRiskCount = 0;

    for (final item in credentials) {
      if (item.isTotpOnly) {
        final siteCheck = checkWebsiteSecurity(item.website);
        if (siteCheck.issueType != null) {
          if (siteCheck.issueType == 'phishing_risk') {
            phishingRiskCount++;
          }
          issues.add(AuditIssue(
            itemId: item.id,
            title: item.title,
            issueType: siteCheck.issueType!,
            description: siteCheck.reason!,
            severity: siteCheck.issueType == 'phishing_risk' ? 3 : 2,
          ));
        }
        continue;
      }

      final pass = item.password;

      if (pass.isNotEmpty) {
        passwordOccurrences.putIfAbsent(pass, () => []).add(item);
      }

      if (isPasswordWeak(pass)) {
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

      if (item.isPasswordExpired(globalExpiryDays)) {
        expiredCount++;
        issues.add(AuditIssue(
          itemId: item.id,
          title: item.title,
          issueType: 'expired',
          description:
              'Şifre yenileme zamanı geldi (${item.passwordAgeDays} gündür güncellenmedi).',
          severity: 2,
        ));
      }

      final siteCheck = checkWebsiteSecurity(item.website);
      if (siteCheck.issueType != null) {
        if (siteCheck.issueType == 'phishing_risk') {
          phishingRiskCount++;
        }
        issues.add(AuditIssue(
          itemId: item.id,
          title: item.title,
          issueType: siteCheck.issueType!,
          description: siteCheck.reason!,
          severity: siteCheck.issueType == 'phishing_risk' ? 3 : 2,
        ));
      }
    }

    int reusedCount = 0;
    for (final entry in passwordOccurrences.entries) {
      if (entry.value.length > 1) {
        reusedCount += entry.value.length;
        for (final item in entry.value) {
          issues.add(AuditIssue(
            itemId: item.id,
            title: item.title,
            issueType: 'reused',
            description:
                'Bu şifre başka ${entry.value.length - 1} hesapta daha kullanılıyor.',
            severity: 2,
          ));
        }
      }
    }

    // Card checks: Luhn validity & expiration
    for (final card in cards) {
      if (card.cardNumber.trim().isNotEmpty && !isValidLuhn(card.cardNumber)) {
        invalidCardsCount++;
        issues.add(AuditIssue(
          itemId: card.id,
          title: card.title,
          issueType: 'card_invalid',
          description: 'Kart numarası Luhn doğrulamasından geçmedi (eksik veya hatalı hane).',
          severity: 3,
        ));
      }

      final expiryState = evaluateCardExpiry(card.cardExpiry);
      if (expiryState == 'expired') {
        expiringCardsCount++;
        issues.add(AuditIssue(
          itemId: card.id,
          title: card.title,
          issueType: 'card_expired',
          description: 'Kartın son kullanma tarihi (${card.cardExpiry}) geçmiş.',
          severity: 3,
        ));
      } else if (expiryState == 'expiring_soon') {
        expiringCardsCount++;
        issues.add(AuditIssue(
          itemId: card.id,
          title: card.title,
          issueType: 'card_expiring_soon',
          description:
              'Kartın son kullanma tarihi (${card.cardExpiry}) 60 gün içinde doluyor.',
          severity: 2,
        ));
      }
    }

    // Identity / License expiry checks
    for (final doc in docs) {
      final rawDate = doc.type == VaultItemType.identity
          ? doc.expiryDate
          : doc.licenseExpiry;
      final state = evaluateDocumentExpiry(rawDate);
      if (state == 'expired' || state == 'expiring_soon') {
        issues.add(AuditIssue(
          itemId: doc.id,
          title: doc.title,
          issueType: 'identity_expiring',
          description: state == 'expired'
              ? 'Belge / lisans son geçerlilik tarihi ($rawDate) dolmuş.'
              : 'Belge / lisans son geçerlilik tarihi ($rawDate) yaklaşıyor.',
          severity: state == 'expired' ? 3 : 2,
        ));
      }
    }

    // Sort highest severity issues first
    issues.sort((a, b) => b.severity.compareTo(a.severity));

    int score = 100;
    if (passwordCredentials.isNotEmpty) {
      final weakPenalty = (weakCount / passwordCredentials.length) * 35;
      final reusedPenalty = (reusedCount / passwordCredentials.length) * 25;
      final no2faPenalty = (missing2faCount / passwordCredentials.length) * 15;
      final expiredPenalty = (expiredCount / passwordCredentials.length) * 10;
      final phishingPenalty = phishingRiskCount * 8;
      final cardPenalty = (invalidCardsCount + expiringCardsCount) * 5;

      score = (100 -
              (weakPenalty +
                  reusedPenalty +
                  no2faPenalty +
                  expiredPenalty +
                  phishingPenalty +
                  cardPenalty))
          .round()
          .clamp(10, 100);
    } else if (invalidCardsCount > 0 || expiringCardsCount > 0) {
      score = (100 - (invalidCardsCount * 15 + expiringCardsCount * 10))
          .clamp(10, 100);
    }

    return AuditReport(
      overallScore: score,
      totalAccounts: passwordCredentials.length,
      weakPasswordsCount: weakCount,
      reusedPasswordsCount: reusedCount,
      missing2faCount: missing2faCount,
      expiredPasswordsCount: expiredCount,
      invalidCardsCount: invalidCardsCount,
      expiringCardsCount: expiringCardsCount,
      phishingRiskCount: phishingRiskCount,
      issues: issues,
    );
  }

  static bool isPasswordWeak(String password) {
    if (password.length < 10) return true;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigits = password.contains(RegExp(r'[0-9]'));
    final hasSpecial = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=~]'));

    int criteria = 0;
    if (hasUpper) criteria++;
    if (hasLower) criteria++;
    if (hasDigits) criteria++;
    if (hasSpecial) criteria++;

    return criteria < 3;
  }
}
