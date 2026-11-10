import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasa Ayarları & Güvenlik'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // User Profile Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.blueAccent.withOpacity(0.15),
                    child: const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.currentUserEmail ?? 'Giriş Yapıldı',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Sıfır-Bilgi (E2EE) Korumalı',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'GÜVENLİK & KİLİT',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
            ),
          ),

          // Biometrics Toggle (Touch ID / Parmak İzi)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded, size: 28, color: Colors.blueAccent),
              title: const Text('Biyometrik Kilit Açma'),
              subtitle: Text(
                auth.canUseBiometrics
                    ? 'Touch ID / Parmak İzi ile şifre girmeden kasayı aç'
                    : 'Cihazınızda biyometrik donanım algılanamadı',
                style: const TextStyle(fontSize: 12),
              ),
              value: auth.isBiometricEnabled && auth.canUseBiometrics,
              onChanged: auth.canUseBiometrics
                  ? (val) async {
                      await auth.toggleBiometrics(val);
                    }
                  : null,
            ),
          ),

          const SizedBox(height: 12),

          // Immediate Lock Button
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.lock_clock_outlined, color: Colors.amber),
              title: const Text('Kasayı Şimdi Kilitle'),
              subtitle: const Text('Şifreleme anahtarını bellekten anında siler', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                auth.lockVault();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),

          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'ŞİFRELEME TEKNOLOJİSİ',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
            ),
          ),

          // Security Information Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 20, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Uçtan Uca Şifreleme (E2EE)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Anahtar Türetme: PBKDF2-HMAC-SHA256 (100.000 Tur)\n'
                    '• Veri Şifreleme: AES-256-GCM (Her kayıtta rastgele IV & MAC koruması)\n'
                    '• Donanım Kasası: Apple Keychain / Android Keystore\n'
                    '• Sıfır-Bilgi: Sunucu yalnızca şifrelenmiş anlamsız baytları depolar. Supabase dahil hiç kimse notlarınızı okuyamaz.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Logout
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: Colors.redAccent,
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Hesaptan Çıkış Yap'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Çıkış Yap'),
                  content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Çıkış Yap'),
                    ),
                  ],
                ),
              );

              if (confirmed == true && context.mounted) {
                await auth.logout();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
