import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/hibp_service.dart';
import 'credential_editor_screen.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  bool _isCheckingBreaches = false;
  final Map<String, HibpResult> _breachResults = {};

  Future<void> _runBreachCheck() async {
    final vault = context.read<VaultProvider>();
    final credentials = vault.allItems
        .where((i) => i.type == VaultItemType.credential && !i.isTrash && !i.isDeleted)
        .toList();

    if (credentials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taranacak hesap bulunamadı.')),
      );
      return;
    }

    setState(() => _isCheckingBreaches = true);

    int compromisedCount = 0;
    for (final item in credentials) {
      if (item.password.trim().isNotEmpty) {
        final res = await HibpService.checkPasswordBreach(item.password);
        _breachResults[item.id] = res;
        if (res.isCompromised) compromisedCount++;
      }
    }

    setState(() => _isCheckingBreaches = false);

    if (mounted) {
      if (compromisedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Dikkat: $compromisedCount şifreniz bilinen veri sızıntılarında bulundu!'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Harika haber! Hiçbir şifreniz veri sızıntılarında bulunamadı.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final auth = context.watch<AuthProvider>();
    final report = AuditService.analyzeVault(
      vault.allItems,
      globalExpiryDays: auth.globalPasswordExpiryDays,
    );
    final theme = Theme.of(context);

    // Calculate score with breach penalties
    int compromisedCount = _breachResults.values.where((r) => r.isCompromised).length;
    int finalScore = (report.overallScore - (compromisedCount * 20)).clamp(5, 100);

    Color scoreColor = Colors.green;
    String scoreStatus = 'Mükemmel';
    if (finalScore < 50 || compromisedCount > 0) {
      scoreColor = Colors.redAccent;
      scoreStatus = compromisedCount > 0 ? 'Sızıntı Riski Tespit Edildi' : 'Kritik Risk';
    } else if (finalScore < 75) {
      scoreColor = Colors.orangeAccent;
      scoreStatus = 'Geliştirilmeli';
    } else if (finalScore < 90) {
      scoreColor = Colors.blueAccent;
      scoreStatus = 'İyi';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parola Sızıntı & Sağlık Denetimi'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Score Banner
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scoreColor.withOpacity(0.5), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor.withOpacity(0.12),
                    ),
                    child: Center(
                      child: Text(
                        '$finalScore',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          scoreStatus,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          compromisedCount > 0
                              ? '$compromisedCount adet şifreniz internetteki veri sızıntılarında bulundu!'
                              : (report.issues.isEmpty
                                  ? 'Tüm şifreleriniz güçlü ve benzersiz.'
                                  : '${report.issues.length} güvenlik iyileştirmesi tespit edildi.'),
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Cloudflare / HIBP Live Breach Scan Action Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.indigo,
            ),
            icon: _isCheckingBreaches
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.security_update_warning_rounded),
            label: Text(
              _isCheckingBreaches
                  ? 'Sıfır-Bilgi Sızıntı Taraması Yapılıyor...'
                  : 'İnternet Veri Sızıntılarını Tara (HIBP / k-Anonymity)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isCheckingBreaches ? null : _runBreachCheck,
          ),

          const SizedBox(height: 16),

          // 5 Metrics Row (including Expired Passwords)
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: 'Sızdırılmış',
                  count: compromisedCount,
                  color: Colors.redAccent,
                  icon: Icons.dangerous_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  title: 'Süresi Dolan',
                  count: report.expiredPasswordsCount,
                  color: Colors.amber,
                  icon: Icons.alarm_on_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  title: 'Zayıf Şifre',
                  count: report.weakPasswordsCount,
                  color: Colors.orangeAccent,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  title: 'Tekrar Eden',
                  count: report.reusedPasswordsCount,
                  color: Colors.purpleAccent,
                  icon: Icons.repeat_rounded,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricTile(
                  title: '2FA Eksik',
                  count: report.missing2faCount,
                  color: Colors.blueAccent,
                  icon: Icons.phonelink_lock_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          const Text(
            'DETAYLI GÜVENLİK ANALİZİ & EYLEMLER',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
          ),
          const SizedBox(height: 8),

          // Pwned / Compromised items first
          if (_breachResults.isNotEmpty) ...[
            ..._breachResults.entries.where((e) => e.value.isCompromised).map((entry) {
              final item = vault.allItems.firstWhere((i) => i.id == entry.key);
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                ),
                child: ListTile(
                  leading: const Icon(Icons.dangerous_rounded, color: Colors.redAccent, size: 28),
                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  subtitle: Text(
                    '⚠️ Bu şifre internetteki ${entry.value.breachCount} ayrı veri sızıntısında açık olarak bulundu!',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text('Değiştir'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CredentialEditorScreen(initialItem: item)),
                      );
                    },
                  ),
                ),
              );
            }),
          ],

          // Weak / Expired / Reused issues
          ...report.issues.map((issue) {
            Color issueColor = Colors.blueAccent;
            IconData issueIcon = Icons.info_outline_rounded;

            if (issue.issueType == 'expired') {
              issueColor = Colors.amber;
              issueIcon = Icons.alarm_on_rounded;
            } else if (issue.severity == 3) {
              issueColor = Colors.redAccent;
              issueIcon = Icons.error_outline_rounded;
            } else if (issue.severity == 2) {
              issueColor = Colors.orangeAccent;
              issueIcon = Icons.warning_amber_rounded;
            }

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
              ),
              child: ListTile(
                leading: Icon(issueIcon, color: issueColor),
                title: Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(issue.description, style: const TextStyle(fontSize: 12)),
                trailing: TextButton(
                  child: const Text('Düzelt'),
                  onPressed: () {
                    final item = vault.allItems.firstWhere((i) => i.id == issue.itemId);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CredentialEditorScreen(initialItem: item)),
                    );
                  },
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 9, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
