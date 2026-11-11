import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/clipboard_service.dart';
import '../services/hibp_service.dart';
import 'card_editor_screen.dart';
import 'credential_editor_screen.dart';
import 'identity_editor_screen.dart';
import 'license_editor_screen.dart';
import 'note_editor_screen.dart';
import 'secret_editor_screen.dart';
import 'wifi_editor_screen.dart';

enum _AuditFilter { all, passwords, twofa, cardsAndDocs, phishing }

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  bool _isCheckingHibp = false;
  bool _hibpChecked = false;
  int _hibpProgress = 0;
  int _hibpTotal = 0;
  int _hibpNetworkErrors = 0;
  final Map<String, HibpResult> _hibpResults = {};
  _AuditFilter _filter = _AuditFilter.all;

  Future<void> _runHibpCheck(List<VaultItem> items) async {
    final credentials = items
        .where(
          (i) =>
              i.type == VaultItemType.credential &&
              !i.isDeleted &&
              i.password.isNotEmpty,
        )
        .toList();

    if (credentials.isEmpty) return;

    final uniquePasswords = credentials.map((c) => c.password).toSet().toList();

    setState(() {
      _isCheckingHibp = true;
      _hibpProgress = 0;
      _hibpTotal = uniquePasswords.length;
      _hibpNetworkErrors = 0;
      _hibpResults.clear();
    });

    final passwordMap = <String, HibpResult>{};
    int errors = 0;
    for (int i = 0; i < uniquePasswords.length; i++) {
      if (!mounted) return;
      final pass = uniquePasswords[i];
      final res = await HibpService.checkPasswordBreach(pass);
      passwordMap[pass] = res;
      if (res.errorMessage != null) errors++;
      if (!mounted) return;
      setState(() => _hibpProgress = i + 1);
    }

    if (!mounted) return;
    setState(() {
      for (final cred in credentials) {
        final r = passwordMap[cred.password];
        if (r != null) _hibpResults[cred.id] = r;
      }
      _isCheckingHibp = false;
      _hibpChecked = true;
      _hibpNetworkErrors = errors;
    });
  }

  void _openItemEditor(VaultItem item) {
    Widget screen;
    switch (item.type) {
      case VaultItemType.note:
        screen = NoteEditorScreen(initialItem: item);
        break;
      case VaultItemType.credential:
        screen = CredentialEditorScreen(initialItem: item);
        break;
      case VaultItemType.card:
        screen = CardEditorScreen(initialItem: item);
        break;
      case VaultItemType.secret:
        screen = SecretEditorScreen(initialItem: item);
        break;
      case VaultItemType.wifi:
        screen = WifiEditorScreen(initialItem: item);
        break;
      case VaultItemType.identity:
        screen = IdentityEditorScreen(initialItem: item);
        break;
      case VaultItemType.license:
        screen = LicenseEditorScreen(initialItem: item);
        break;
      case VaultItemType.folder:
        return;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  String _generateSecurePassword({int length = 20}) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#\$%^&*()-_=+[]{}';
    const all = '$upper$lower$digits$symbols';

    final rand = Random.secure();
    final chars = <String>[
      upper[rand.nextInt(upper.length)],
      lower[rand.nextInt(lower.length)],
      digits[rand.nextInt(digits.length)],
      symbols[rand.nextInt(symbols.length)],
    ];
    while (chars.length < length) {
      chars.add(all[rand.nextInt(all.length)]);
    }
    chars.shuffle(rand);
    return chars.join();
  }

  Future<void> _openPasswordRenewalWizard(
    VaultProvider vault,
    AuditReport report,
  ) async {
    final l10n = context.l10n;
    final flaggedIds = <String>{};
    final reasonsById = <String, List<String>>{};

    for (final issue in report.issues) {
      if (issue.issueType == 'weak' ||
          issue.issueType == 'reused' ||
          issue.issueType == 'expired') {
        flaggedIds.add(issue.itemId);
        reasonsById.putIfAbsent(issue.itemId, () => []).add(issue.description);
      }
    }
    for (final entry in _hibpResults.entries) {
      if (entry.value.isCompromised) {
        flaggedIds.add(entry.key);
        reasonsById
            .putIfAbsent(entry.key, () => [])
            .add(
              l10n.tr(
                'Sızıntı veritabanında ${entry.value.breachCount} kez bulundu',
                'Found ${entry.value.breachCount} times in breach database',
              ),
            );
      }
    }

    final targets = vault.items
        .where(
          (i) =>
              i.type == VaultItemType.credential &&
              flaggedIds.contains(i.id) &&
              !i.isDeleted,
        )
        .toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              'Yenilenmesi gereken zayıf, tekrarlanan veya süresi dolmuş parola bulunamadı.',
              'No weak, reused, expired, or breached passwords need renewal.',
            ),
          ),
        ),
      );
      return;
    }

    int index = 0;
    int length = 20;
    String generated = _generateSecurePassword(length: length);
    final passCtrl = TextEditingController(text: generated);
    bool obscure = false;
    bool saving = false;
    int renewedCount = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final current = targets[index];
          final reasons = reasonsById[current.id] ?? const <String>[];
          final settings = ctx.read<SettingsProvider>();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tr(
                      'Şifre Yenileme Sihirbazı (${index + 1}/${targets.length})',
                      'Password Renewal Wizard (${index + 1}/${targets.length})',
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: (index + 1) / targets.length,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      current.title.isEmpty
                          ? l10n.tr('Adsız Hesap', 'Untitled Account')
                          : current.title,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (current.username.isNotEmpty)
                      Text(
                        current.username,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    if (current.website.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            current.website,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.open_in_new, size: 14),
                            label: Text(
                              l10n.tr('Siteyi Aç', 'Open Site'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () async {
                              final raw = current.website.trim();
                              final uri = Uri.tryParse(
                                raw.contains('://') ? raw : 'https://$raw',
                              );
                              if (uri != null) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    if (reasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: reasons
                              .map(
                                (r) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 1,
                                  ),
                                  child: Text(
                                    '• $r',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: l10n.tr(
                          'Yeni Güçlü Parola',
                          'New Strong Password',
                        ),
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                obscure
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setDlgState(() => obscure = !obscure),
                            ),
                            IconButton(
                              tooltip: l10n.tr('Yeniden Üret', 'Regenerate'),
                              icon: const Icon(Icons.refresh),
                              onPressed: () => setDlgState(() {
                                generated = _generateSecurePassword(
                                  length: length,
                                );
                                passCtrl.text = generated;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          l10n.tr('Uzunluk: $length', 'Length: $length'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: length.toDouble(),
                            min: 14,
                            max: 32,
                            divisions: 18,
                            onChanged: (v) {
                              setDlgState(() {
                                length = v.round();
                                generated = _generateSecurePassword(
                                  length: length,
                                );
                                passCtrl.text = generated;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    Text(
                      l10n.tr(
                        'Önce yeni parolayı kopyalayıp sitenin şifre değiştirme sayfasında güncelleyin, ardından "Kopyala, Kaydet & Sonraki" butonuna basın.',
                        'First update the password on the website, then tap "Copy, Save & Next" so your vault stays in sync.',
                      ),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: Text(l10n.close),
              ),
              if (index + 1 < targets.length)
                TextButton(
                  onPressed: saving
                      ? null
                      : () => setDlgState(() {
                          index++;
                          generated = _generateSecurePassword(length: length);
                          passCtrl.text = generated;
                        }),
                  child: Text(l10n.tr('Atla', 'Skip')),
                ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final newPass = passCtrl.text.trim();
                        if (newPass.isEmpty) return;
                        setDlgState(() => saving = true);

                        await ClipboardService.copySecurely(
                          newPass,
                          timeoutSeconds: settings.clipboardTimeoutSeconds,
                        );

                        final history = List<String>.from(
                          current.passwordHistory,
                        );
                        if (current.password.isNotEmpty &&
                            current.password != newPass &&
                            !history.contains(current.password)) {
                          history.insert(0, current.password);
                          if (history.length > 10) history.removeLast();
                        }

                        final updated = current.copyWith(
                          password: newPass,
                          passwordHistory: history,
                          passwordLastModified: DateTime.now().toUtc(),
                        );
                        await vault.saveItem(updated);
                        renewedCount++;

                        if (!ctx.mounted) return;
                        if (index + 1 < targets.length) {
                          setDlgState(() {
                            saving = false;
                            index++;
                            generated = _generateSecurePassword(length: length);
                            passCtrl.text = generated;
                          });
                        } else {
                          Navigator.of(ctx).pop();
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  index + 1 < targets.length
                      ? l10n.tr('Kopyala, Kaydet & Sonraki', 'Copy, Save & Next')
                      : l10n.tr('Kopyala & Kaydet', 'Copy & Save'),
                ),
              ),
            ],
          );
        },
      ),
    );

    passCtrl.dispose();
    if (!mounted || renewedCount == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.tr(
            '$renewedCount hesabın parolası yenilendi ve panoya kopyalandı.',
            'Renewed $renewedCount account password(s) and copied to clipboard.',
          ),
        ),
      ),
    );
  }

  bool _matchesFilter(AuditIssue issue) {
    switch (_filter) {
      case _AuditFilter.all:
        return true;
      case _AuditFilter.passwords:
        return issue.issueType == 'weak' ||
            issue.issueType == 'reused' ||
            issue.issueType == 'expired';
      case _AuditFilter.twofa:
        return issue.issueType == 'missing_2fa';
      case _AuditFilter.cardsAndDocs:
        return issue.issueType == 'card_invalid' ||
            issue.issueType == 'card_expired' ||
            issue.issueType == 'card_expiring_soon' ||
            issue.issueType == 'identity_expiring';
      case _AuditFilter.phishing:
        return issue.issueType == 'phishing_risk' ||
            issue.issueType == 'insecure_http';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final vault = context.watch<VaultProvider>();
    final auth = context.watch<AuthProvider>();
    final activeItems = vault.items.where((i) => !i.isDeleted).toList();
    final report = AuditService.analyzeVault(
      activeItems,
      globalExpiryDays: auth.globalPasswordExpiryDays,
    );

    final theme = Theme.of(context);
    Color scoreColor = Colors.green;
    String statusText = l10n.tr('Mükemmel', 'Excellent');
    if (report.overallScore < 50) {
      scoreColor = Colors.redAccent;
      statusText = l10n.tr('Kritik Risk', 'Critical Risk');
    } else if (report.overallScore < 80) {
      scoreColor = Colors.orangeAccent;
      statusText = l10n.tr('İyileştirilebilir', 'Needs Attention');
    }

    final breachedItems = activeItems
        .where((i) => _hibpResults[i.id]?.isCompromised == true)
        .toList();

    final filteredIssues = report.issues.where(_matchesFilter).toList();
    final hasRenewablePasswords = report.issues.any(
      (i) =>
          i.issueType == 'weak' ||
          i.issueType == 'reused' ||
          i.issueType == 'expired',
    ) ||
        breachedItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.audit)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: report.overallScore / 100.0,
                              strokeWidth: 9,
                              color: scoreColor,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                            Center(
                              child: Text(
                                '${report.overallScore}',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.tr('Güvenlik Skoru', 'Security Score'),
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              statusText,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.tr(
                                '${report.totalAccounts} hesap, kart ve kimlik belgesi tarandı.',
                                'Scanned ${report.totalAccounts} account(s), cards & IDs.',
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricPill(
                        label: l10n.tr('Zayıf', 'Weak'),
                        count: report.weakPasswordsCount,
                        color: Colors.redAccent,
                      ),
                      _MetricPill(
                        label: l10n.tr('Tekrarlanan', 'Reused'),
                        count: report.reusedPasswordsCount,
                        color: Colors.orangeAccent,
                      ),
                      _MetricPill(
                        label: l10n.tr('2FA Eksik', 'No 2FA'),
                        count: report.missing2faCount,
                        color: Colors.amber,
                      ),
                      _MetricPill(
                        label: l10n.tr('Süresi Dolan', 'Expired'),
                        count: report.expiredPasswordsCount,
                        color: Colors.deepOrange,
                      ),
                      _MetricPill(
                        label: l10n.tr('Geçersiz Kart', 'Invalid Card'),
                        count: report.invalidCardsCount,
                        color: Colors.red,
                      ),
                      _MetricPill(
                        label: l10n.tr('Kart/Belge Süre', 'Expiring'),
                        count: report.expiringCardsCount,
                        color: Colors.purpleAccent,
                      ),
                      _MetricPill(
                        label: l10n.tr('Phishing/HTTP', 'Phishing/HTTP'),
                        count: report.phishingRiskCount,
                        color: Colors.pinkAccent,
                      ),
                    ],
                  ),
                  if (hasRenewablePasswords) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () =>
                            _openPasswordRenewalWizard(vault, report),
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: Text(
                          l10n.tr(
                            'Tek Tıkla Şifre Yenileme Sihirbazını Başlat',
                            'Launch 1-Click Password Renewal Wizard',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security_update_warning,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.tr(
                            'Veri Sızıntısı Taraması (HIBP k-Anonymity)',
                            'Data Breach Scan (HIBP k-Anonymity)',
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr(
                      'Parolalarınızın yalnızca SHA-1 özetinin ilk 5 karakteri HaveIBeenPwned servisine gönderilir; parolanız asla paylaşılmaz.',
                      'Only the first 5 characters of your password SHA-1 hash are sent to HaveIBeenPwned; plaintext passwords never leave your device.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_isCheckingHibp) ...[
                    LinearProgressIndicator(
                      value: _hibpTotal > 0 ? _hibpProgress / _hibpTotal : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.tr(
                        'Taranıyor: $_hibpProgress / $_hibpTotal benzersiz parola...',
                        'Scanning: $_hibpProgress / $_hibpTotal unique password(s)...',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: report.totalAccounts > 0
                          ? () => _runHibpCheck(activeItems)
                          : null,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(
                        _hibpChecked
                            ? l10n.tr('Tekrar Tara', 'Scan Again')
                            : l10n.tr(
                                'Sızıntı Taramasını Başlat',
                                'Start Breach Scan',
                              ),
                      ),
                    ),
                    if (_hibpChecked) ...[
                      const SizedBox(height: 10),
                      if (_hibpNetworkErrors > 0)
                        Text(
                          l10n.tr(
                            'Uyarı: $_hibpNetworkErrors sorgu ağ hatası nedeniyle tamamlanamadı.',
                            'Warning: $_hibpNetworkErrors query(ies) failed due to network errors.',
                          ),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                          ),
                        ),
                      Text(
                        breachedItems.isEmpty
                            ? l10n.tr(
                                'Harika! Bilinen veri sızıntılarında eşleşen parola bulunamadı.',
                                'Great! No passwords matched known data breaches.',
                              )
                            : l10n.tr(
                                'DİKKAT: ${breachedItems.length} hesabın parolası veri sızıntılarında tespit edildi!',
                                'ALERT: ${breachedItems.length} account password(s) appeared in known data breaches!',
                              ),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: breachedItems.isEmpty
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                      ),
                      ...breachedItems.map((item) {
                        final count = _hibpResults[item.id]?.breachCount ?? 0;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.redAccent,
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            l10n.tr(
                              'Sızıntılarda $count kez görüldü',
                              'Seen $count time(s) in breaches',
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () => _openItemEditor(item),
                            child: Text(l10n.tr('Değiştir', 'Change')),
                          ),
                        );
                      }),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChipBtn(
                  label: l10n.tr(
                    'Tümü (${report.issues.length})',
                    'All (${report.issues.length})',
                  ),
                  selected: _filter == _AuditFilter.all,
                  onTap: () => setState(() => _filter = _AuditFilter.all),
                ),
                _FilterChipBtn(
                  label: l10n.tr('Parola Sorunları', 'Passwords'),
                  selected: _filter == _AuditFilter.passwords,
                  onTap: () => setState(() => _filter = _AuditFilter.passwords),
                ),
                _FilterChipBtn(
                  label: l10n.tr('2FA Eksik', 'Missing 2FA'),
                  selected: _filter == _AuditFilter.twofa,
                  onTap: () => setState(() => _filter = _AuditFilter.twofa),
                ),
                _FilterChipBtn(
                  label: l10n.tr('Kart & Kimlik', 'Cards & IDs'),
                  selected: _filter == _AuditFilter.cardsAndDocs,
                  onTap: () =>
                      setState(() => _filter = _AuditFilter.cardsAndDocs),
                ),
                _FilterChipBtn(
                  label: l10n.tr('Phishing & HTTP', 'Phishing & HTTP'),
                  selected: _filter == _AuditFilter.phishing,
                  onTap: () => setState(() => _filter = _AuditFilter.phishing),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (filteredIssues.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.verified_user,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.tr(
                        'Bu kategoride güvenlik uyarısı bulunmuyor.',
                        'No security warnings in this category.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredIssues.map((issue) {
              VaultItem? matchingItem;
              for (final i in activeItems) {
                if (i.id == issue.itemId) {
                  matchingItem = i;
                  break;
                }
              }

              final sevColor = issue.severity >= 3
                  ? Colors.redAccent
                  : (issue.severity == 2
                        ? Colors.orangeAccent
                        : Colors.amber);

              final icon = switch (issue.issueType) {
                'phishing_risk' || 'insecure_http' => Icons.phishing_rounded,
                'card_invalid' ||
                'card_expired' ||
                'card_expiring_soon' =>
                  Icons.credit_card_off_rounded,
                'identity_expiring' => Icons.badge_rounded,
                'missing_2fa' => Icons.phonelink_lock_rounded,
                _ => Icons.password_rounded,
              };

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: sevColor.withValues(alpha: 0.16),
                    child: Icon(icon, color: sevColor, size: 20),
                  ),
                  title: Text(issue.title),
                  subtitle: Text(issue.description),
                  trailing: matchingItem == null
                      ? null
                      : FilledButton.tonal(
                          onPressed: () => _openItemEditor(matchingItem!),
                          child: Text(l10n.tr('Düzelt', 'Fix')),
                        ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? color : Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
