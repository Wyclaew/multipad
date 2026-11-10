import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/update_service.dart';
import '../widgets/easter_egg_dialog.dart';
import 'audit_screen.dart';
import 'backup_screen.dart';
import 'trash_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _easterEggTapCount = 0;
  bool _isCheckingUpdate = false;

  void _handleDeveloperTap() {
    setState(() => _easterEggTapCount++);

    if (_easterEggTapCount == 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🐾 Gizli sürpriz için son 2 tık!'), duration: Duration(milliseconds: 1000)),
      );
    } else if (_easterEggTapCount == 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🐾 Son 1 tık!'), duration: Duration(milliseconds: 1000)),
      );
    } else if (_easterEggTapCount >= 7) {
      setState(() => _easterEggTapCount = 0);
      showDialog(
        context: context,
        builder: (_) => const EasterEggDialog(),
      );
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final updateInfo = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (updateInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncelleme kontrolü başarısız oldu. İnternet bağlantınızı kontrol edin.')),
      );
      return;
    }

    if (updateInfo.hasUpdate) {
      final asset = updateInfo.platformAsset;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Colors.blueAccent),
              const SizedBox(width: 10),
              Text('Yeni Sürüm: ${updateInfo.latestVersion}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mevcut Sürüm: ${updateInfo.currentVersion}'),
              const SizedBox(height: 12),
              const Text('Yenilikler:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                updateInfo.releaseNotes.isEmpty ? 'Hata düzeltmeleri ve performans iyileştirmeleri.' : updateInfo.releaseNotes,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              if (asset != null) ...[
                const SizedBox(height: 12),
                Text('Dosya: ${asset.name} (${(asset.size / (1024 * 1024)).toStringAsFixed(1)} MB)', style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Daha Sonra'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Şimdi İndir & Yükle'),
              onPressed: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${asset?.name ?? 'Güncelleme'} indirme adresi: ${updateInfo.htmlUrl}')),
                );
              },
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MultiPad güncel! En son sürümü kullanıyorsunuz (${updateInfo.currentVersion}).'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ana Şifreyi Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ana şifrenizi değiştirdiğinizde kasadaki tüm öğeler yeni şifreniz ile yeniden şifrelenecektir.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: currentController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mevcut Ana Şifre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Yeni Ana Şifre (En az 8 kr)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Yeni Ana Şifre Tekrar', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (currentController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Lütfen mevcut ana şifrenizi girin.')));
                return;
              }
              if (newController.text.length < 8) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Yeni şifre en az 8 karakter olmalıdır.')));
                return;
              }
              if (newController.text != confirmController.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Şifreler eşleşmiyor.')));
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Şifreyi Değiştir'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final auth = context.read<AuthProvider>();
      final vault = context.read<VaultProvider>();

      final currentPass = currentController.text;
      final newPass = newController.text;

      // Wipe controllers
      currentController.clear();
      newController.clear();
      confirmController.clear();

      final success = await auth.changeMasterPassword(
        currentPassword: currentPass,
        newPassword: newPass,
        vault: vault,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ana şifre başarıyla değiştirildi ve kasa yeni anahtarla yeniden şifrelendi!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(auth.errorMessage ?? 'Şifre değiştirilemedi.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar & Güvenlik'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // User Status Banner
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
                          auth.currentUserEmail ?? 'Yerel Kasa Kullanıcısı',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.lock_rounded, size: 14, color: Colors.green),
                            SizedBox(width: 4),
                            Text('Sıfır-Bilgi (Zero-Knowledge) E2EE Aktif', style: TextStyle(fontSize: 12, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const _SectionHeader(title: 'GÜVENLİK & KASA SEÇENEKLERİ'),

          // Biometrics
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded, size: 26, color: Colors.blueAccent),
              title: const Text('Biyometrik Kilit'),
              subtitle: Text(
                auth.canUseBiometrics
                    ? 'Touch ID / Parmak İzi ile kasanın kilidini aç'
                    : 'Cihazda biyometrik donanım bulunamadı',
                style: const TextStyle(fontSize: 12),
              ),
              value: auth.isBiometricEnabled && auth.canUseBiometrics,
              onChanged: auth.canUseBiometrics ? (val) => auth.toggleBiometrics(val) : null,
            ),
          ),
          const SizedBox(height: 8),

          // Global Password Expiration Reminder Settings (Item 30)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.alarm_on_rounded, color: Colors.blueAccent, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Şifre Yenileme Hatırlatıcısı (Item 30)', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('Eski şifreler için periyodik güncelleme uyarısı', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: auth.globalPasswordExpiryDays,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Genel Hatırlatma Aralığı',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Kapalı (Hatırlatma Yok)')),
                      DropdownMenuItem(value: 30, child: Text('30 Günde Bir')),
                      DropdownMenuItem(value: 60, child: Text('60 Günde Bir')),
                      DropdownMenuItem(value: 90, child: Text('90 Günde Bir (Önerilen / Standart)')),
                      DropdownMenuItem(value: 180, child: Text('180 Günde Bir (6 Ay)')),
                      DropdownMenuItem(value: 365, child: Text('365 Günde Bir (1 Yıl)')),
                    ],
                    onChanged: (val) {
                      if (val != null) auth.setGlobalPasswordExpiryDays(val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Change Master Password
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.key_rounded, color: Colors.purpleAccent),
              title: const Text('Ana Şifreyi Değiştir'),
              subtitle: const Text('Kasayı yeni bir anahtar ile tekrar şifreler', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _showChangePasswordDialog,
            ),
          ),
          const SizedBox(height: 8),

          // Lock Vault Immediately
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.lock_clock_outlined, color: Colors.amber),
              title: const Text('Kasayı Şimdi Kilitle'),
              subtitle: const Text('Şifreleme anahtarını bellekten (RAM) anında siler', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () {
                auth.lockVault();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),

          const SizedBox(height: 20),
          const _SectionHeader(title: 'RAPORLAR & ARAÇLAR'),

          // Audit
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined, color: Colors.green),
              title: const Text('Parola Sızıntı & Sağlık Denetimi'),
              subtitle: const Text('Sızdırılmış şifreleri (HIBP), süresi dolanları ve zayıf parolaları denetle', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditScreen())),
            ),
          ),
          const SizedBox(height: 8),

          // Backup
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.archive_outlined, color: Colors.blueAccent),
              title: const Text('Şifreli Yedekleme & Geri Yükleme'),
              subtitle: const Text('Kasanızı AES-256 ile şifrelenmiş tek dosya olarak dışa aktarın', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupScreen())),
            ),
          ),
          const SizedBox(height: 8),

          // Trash
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Çöp Kutusu'),
              subtitle: const Text('Silinen öğeleri görüntüle, geri yükle veya temizle', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashScreen())),
            ),
          ),

          const SizedBox(height: 20),
          const _SectionHeader(title: 'SÜRÜM & GÜNCELLEMELER'),

          // Check for Updates
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: _isCheckingUpdate
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update_rounded, color: Colors.blueAccent),
              title: const Text('GitHub Üzerinden Güncellemeleri Denetle'),
              subtitle: const Text('En güncel sürüm olup olmadığını kontrol et', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.refresh_rounded),
              onTap: _isCheckingUpdate ? null : _checkForUpdate,
            ),
          ),

          const SizedBox(height: 20),
          const _SectionHeader(title: 'HAKKINDA & GELİŞTİRİCİ'),

          // About & Easter Egg Tile
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _handleDeveloperTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.code_rounded, color: Colors.blueAccent),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MultiPad Vault v1.0.3', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Yapımcı: WycDev', style: TextStyle(fontSize: 13, color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Icon(Icons.favorite_rounded, size: 16, color: Colors.pinkAccent),
                  ],
                ),
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
                  content: const Text('Kasadan çıkmak istediğinize emin misiniz? Biyometrik oturumunuz ve anahtarınız bellekten temizlenecektir.'),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
      ),
    );
  }
}
