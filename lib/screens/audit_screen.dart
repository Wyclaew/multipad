import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import 'credential_editor_screen.dart';

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final report = AuditService.analyzeVault(vault.allItems);
    final theme = Theme.of(context);

    Color scoreColor = Colors.green;
    String scoreStatus = 'Mükemmel';
    if (report.overallScore < 50) {
      scoreColor = Colors.redAccent;
      scoreStatus = 'Kritik Risk';
    } else if (report.overallScore < 75) {
      scoreColor = Colors.orangeAccent;
      scoreStatus = 'Geliştirilmeli';
    } else if (report.overallScore < 90) {
      scoreColor = Colors.blueAccent;
      scoreStatus = 'İyi';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parola Güvenlik Denetimi'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                        '${report.overallScore}',
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
                          'Kasa Güvenlik Durumu: $scoreStatus',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.issues.isEmpty
                              ? 'Tebrikler! Tüm şifreleriniz güçlü ve benzersiz.'
                              : '${report.issues.length} güvenlik uyarısı tespit edildi.',
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 3 Metrics Row
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  title: 'Zayıf Şifre',
                  count: report.weakPasswordsCount,
                  color: Colors.redAccent,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context,
                  title: 'Tekrar Eden',
                  count: report.reusedPasswordsCount,
                  color: Colors.orangeAccent,
                  icon: Icons.repeat_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  context,
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
            'GÜVENLİK ÖNERİLERİ & SORUNLAR',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
          ),
          const SizedBox(height: 10),

          if (report.issues.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        'Harika! Hiçbir güvenlik sorunu bulunamadı.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...report.issues.map((issue) {
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                ),
                child: ListTile(
                  leading: Icon(
                    issue.severity == 3
                        ? Icons.error_outline_rounded
                        : issue.severity == 2
                            ? Icons.warning_amber_rounded
                            : Icons.info_outline_rounded,
                    color: issue.severity == 3
                        ? Colors.redAccent
                        : issue.severity == 2
                            ? Colors.orangeAccent
                            : Colors.blueAccent,
                  ),
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

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
