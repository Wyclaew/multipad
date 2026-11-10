import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/backup_service.dart';
import '../services/clipboard_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Export state
  final _exportPasswordController = TextEditingController();
  String? _exportedPackage;
  bool _isExporting = false;

  // Import state
  final _importDataController = TextEditingController();
  final _importPasswordController = TextEditingController();
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _exportPasswordController.dispose();
    _importDataController.dispose();
    _importPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final password = _exportPasswordController.text;
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yedekleme şifresi en az 8 karakter olmalıdır.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final auth = context.read<AuthProvider>();
      final vault = context.read<VaultProvider>();
      final backupService = BackupService(auth.cryptoService);

      final pkg = await backupService.exportEncryptedBackup(
        items: vault.allItems,
        backupPassword: password,
      );

      setState(() => _exportedPackage = pkg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifreli yedek başarıyla oluşturuldu!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedekleme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleImport() async {
    final data = _importDataController.text.trim();
    final password = _importPasswordController.text;

    if (data.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yedek verisini ve şifresini eksiksiz girin.')),
      );
      return;
    }

    setState(() => _isImporting = true);
    try {
      final auth = context.read<AuthProvider>();
      final vault = context.read<VaultProvider>();
      final backupService = BackupService(auth.cryptoService);

      final importedItems = await backupService.importEncryptedBackup(
        backupString: data,
        backupPassword: password,
      );

      for (final item in importedItems) {
        await vault.saveItem(item);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${importedItems.length} öğe başarıyla kasanıza aktarıldı!')),
        );
        _importDataController.clear();
        _importPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geri yükleme başarısız. Şifre hatalı veya dosya bozuk: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Şifreli Yedekleme & Geri Yükleme'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.upload_file_outlined), text: 'Yedek Al (Export)'),
            Tab(icon: Icon(Icons.download_for_offline_outlined), text: 'Geri Yükle (Import)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Export Tab
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Tüm Kasanızı AES-256 ile Şifreleyip Yedekleyin',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Belirleyeceğiniz yedek şifresi ile tüm notlarınız ve şifreleriniz tek bir güvenli metin paketine dönüştürülür.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _exportPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Yedekleme İçin Bir Parola Belirleyin',
                  hintText: 'En az 8 karakter',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isExporting ? null : _handleExport,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Şifreli Yedeği Oluştur'),
              ),
              if (_exportedPackage != null) ...[
                const SizedBox(height: 24),
                const Text('Oluşturulan Şifreli Paket:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _exportedPackage!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    maxLines: 6,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Yedek Metnini Kopyala'),
                  onPressed: () async {
                    await ClipboardService.copySecurely(_exportedPackage!, timeoutSeconds: 120);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Yedek paketi panoya kopyalandı!')),
                      );
                    }
                  },
                ),
              ],
            ],
          ),

          // Import Tab
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Şifreli Yedeği Kasanıza Aktarın',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Daha önce aldığınız şifreli yedek metnini ve yedeği alırken belirlediğiniz şifreyi girin.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _importDataController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Şifreli Yedek Metni',
                  hintText: '{"format": "multipad_backup_e2ee", ...}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _importPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Yedeğin Şifresi',
                  prefixIcon: Icon(Icons.key_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isImporting ? null : _handleImport,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Çöz ve Kasanıza Aktar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
