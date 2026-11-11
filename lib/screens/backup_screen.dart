import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/backup_service.dart';
import '../services/clipboard_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _exportPasswordController = TextEditingController();
  final _importDataController = TextEditingController();
  final _importPasswordController = TextEditingController();

  String? _exportedPackage;
  bool _isWorking = false;

  @override
  void dispose() {
    _exportPasswordController.dispose();
    _importDataController.dispose();
    _importPasswordController.dispose();
    super.dispose();
  }

  Future<void> _exportBackup() async {
    final pass = _exportPasswordController.text.trim();
    if (pass.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yedekleme şifresi en az 8 karakter olmalıdır.'),
        ),
      );
      return;
    }

    setState(() => _isWorking = true);
    try {
      final auth = context.read<AuthProvider>();
      final vault = context.read<VaultProvider>();
      if (auth.isDuressMode) {
        throw Exception('Bu modda yedek alınamaz.');
      }
      final backupService = BackupService(auth.cryptoService);
      final pkg = await backupService.exportEncryptedBackup(
        items: vault.allItems,
        backupPassword: pass,
      );
      setState(() => _exportedPackage = pkg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Şifreli Argon2id/AES-GCM yedeği oluşturuldu!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedekleme hatası: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _importBackup() async {
    final pkg = _importDataController.text.trim();
    final pass = _importPasswordController.text.trim();
    if (pkg.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yedek verisini ve şifresini eksiksiz girin.'),
        ),
      );
      return;
    }

    setState(() => _isWorking = true);
    try {
      final auth = context.read<AuthProvider>();
      final vault = context.read<VaultProvider>();
      final backupService = BackupService(auth.cryptoService);
      final importedItems = await backupService.importEncryptedBackup(
        backupString: pkg,
        backupPassword: pass,
      );

      for (final item in importedItems) {
        await vault.saveItem(item);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${importedItems.length} öğe başarıyla kasanıza aktarıldı!',
            ),
          ),
        );
        _importDataController.clear();
        _importPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Geri yükleme hatası: ${e.toString().replaceAll("Exception: ", "")}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backup)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.cloud_upload_outlined, color: Colors.indigoAccent),
                          SizedBox(width: 8),
                          Text(
                            'Şifreli Yedek Oluştur (Dışa Aktar)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tüm notlar, şifreler, kartlar, klasörler ve özel alanlar Argon2id + AES-256-GCM ile şifrelenerek taşınabilir pakete dönüştürülür.',
                        style: TextStyle(fontSize: 13, color: theme.hintColor),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _exportPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Yedek Şifresi (en az 8 karakter)',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _isWorking ? null : _exportBackup,
                        icon: const Icon(Icons.download),
                        label: const Text('Şifreli Yedek Paketi Üret'),
                      ),
                      if (_exportedPackage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            _exportedPackage!,
                            maxLines: 5,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ClipboardService.copySecurely(
                              _exportedPackage!,
                              timeoutSeconds: 120,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Yedek paketi panoya kopyalandı (120 sn sonra temizlenir)!',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Yedeği Panoya Kopyala'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.restore_page_outlined, color: Colors.teal),
                          SizedBox(width: 8),
                          Text(
                            'Şifreli Yedeği Geri Yükle (İçe Aktar)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _importDataController,
                        maxLines: 4,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'JSON Yedek Verisini Buraya Yapıştırın',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _importPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Yedekleme Şifresi',
                          prefixIcon: Icon(Icons.vpn_key_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.tonalIcon(
                        onPressed: _isWorking ? null : _importBackup,
                        icon: _isWorking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file),
                        label: const Text('Yedeği Çöz ve Kasaya Ekle'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
