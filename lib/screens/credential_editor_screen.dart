import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../widgets/password_generator_dialog.dart';

class CredentialEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const CredentialEditorScreen({super.key, this.initialItem});

  @override
  State<CredentialEditorScreen> createState() => _CredentialEditorScreenState();
}

class _CredentialEditorScreenState extends State<CredentialEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _websiteController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late bool _isFavorite;
  bool _obscurePassword = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _titleController = TextEditingController(text: item?.title ?? '');
    _usernameController = TextEditingController(text: item?.username ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _websiteController = TextEditingController(text: item?.website ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
    _tags = List<String>.from(item?.tags ?? []);
    _isFavorite = item?.isFavorite ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _openPasswordGenerator() async {
    final generated = await showDialog<String>(
      context: context,
      builder: (ctx) => const PasswordGeneratorDialog(),
    );

    if (generated != null && generated.isNotEmpty) {
      setState(() {
        _passwordController.text = generated;
        _obscurePassword = false; // Show newly generated password
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _usernameController.text.isEmpty && _passwordController.text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    final updatedItem = (widget.initialItem ?? vault.createNewCredential()).copyWith(
      title: title.isEmpty ? 'İsimsiz Hesap' : title,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      website: _websiteController.text.trim(),
      content: _notesController.text.trim(),
      tags: _tags,
      isFavorite: _isFavorite,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    await vault.saveItem(updatedItem);
    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceAll('#', '');
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagInputController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabı Sil'),
        content: const Text('Bu şifreli hesap kartını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (widget.initialItem != null) {
        await context.read<VaultProvider>().deleteItem(widget.initialItem!.id);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialItem == null ? 'Yeni Şifre / Hesap' : 'Hesap Düzenle'),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
            color: _isFavorite ? Colors.amber : null,
            tooltip: _isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          if (widget.initialItem != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Sil',
              onPressed: _delete,
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            icon: _isSaving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Kaydet'),
            onPressed: _isSaving ? null : _save,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title (Item Name)
                TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Hesap / Servis Adı',
                    hintText: 'Örn: Google, Banka, GitHub',
                    prefixIcon: Icon(Icons.label_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Website / URL
                TextField(
                  controller: _websiteController,
                  decoration: const InputDecoration(
                    labelText: 'Web Sitesi / URL (İsteğe bağlı)',
                    hintText: 'https://example.com',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Username / Email
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Kullanıcı Adı / E-posta',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Kullanıcı Adını Kopyala',
                      onPressed: () async {
                        if (_usernameController.text.isNotEmpty) {
                          await ClipboardService.copySecurely(_usernameController.text);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kullanıcı adı kopyalandı!')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Password with generator and copy actions
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(
                    fontFamily: _obscurePassword ? null : 'monospace',
                    letterSpacing: _obscurePassword ? 2 : 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          tooltip: _obscurePassword ? 'Şifreyi Göster' : 'Şifreyi Gizle',
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        IconButton(
                          icon: const Icon(Icons.auto_fix_high_outlined, color: Colors.blueAccent),
                          tooltip: 'Güçlü Şifre Üret',
                          onPressed: _openPasswordGenerator,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Şifreyi Kopyala (30 sn)',
                          onPressed: () async {
                            if (_passwordController.text.isNotEmpty) {
                              await ClipboardService.copySecurely(_passwordController.text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Şifre kopyalandı! (30 sn sonra otomatik temizlenir)'),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tags
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._tags.map(
                      (tag) => Chip(
                        label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _removeTag(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _tagInputController,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: '+ etiket ekle',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Extra Notes (Recovery Codes, PINs, etc.)
                TextField(
                  controller: _notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Güvenli Ek Notlar (2FA Kurtarma Kodları, PIN vb.)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
