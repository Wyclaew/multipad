import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';

class SecretEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const SecretEditorScreen({super.key, this.initialItem});

  @override
  State<SecretEditorScreen> createState() => _SecretEditorScreenState();
}

class _SecretEditorScreenState extends State<SecretEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _secretController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;
  late String _secretType;
  late List<String> _tags;
  late bool _isFavorite;
  late bool _isPinned;

  bool _obscureSecret = true;
  bool _isSaving = false;

  final List<String> _secretTypes = [
    'API Anahtarı / Token',
    'SSH Özel Anahtarı (Private Key)',
    'Kripto Cüzdan Kurtarma Kelimeleri (Seed)',
    'Veritabanı Bağlantı Dizesi (Connection String)',
    'Yazılım Lisans Anahtarı',
    'Genel Gizli Bilgi',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _titleController = TextEditingController(text: item?.title ?? '');
    _secretController = TextEditingController(text: item?.password ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
    _secretType = item?.secretType ?? _secretTypes.first;
    if (!_secretTypes.contains(_secretType)) {
      _secretTypes.add(_secretType);
    }
    _tags = List<String>.from(item?.tags ?? []);
    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _secretController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _secretController.text.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    final updated = (widget.initialItem ?? vault.createNewSecret()).copyWith(
      title: title.isEmpty ? 'İsimsiz Gizli Anahtar' : title,
      secretType: _secretType,
      password: _secretController.text.trim(),
      content: _notesController.text.trim(),
      tags: _tags,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
      clientUpdatedAt: DateTime.now().toUtc(),
    );

    await vault.saveItem(updated);
    setState(() => _isSaving = false);

    if (mounted) Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialItem == null ? 'Yeni Gizli Anahtar' : 'Gizli Anahtarı Düzenle'),
        actions: [
          IconButton(
            icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: _isPinned ? Colors.blueAccent : null,
            tooltip: _isPinned ? 'Sabitlemeyi Kaldır' : 'Başa Sabitle',
            onPressed: () => setState(() => _isPinned = !_isPinned),
          ),
          IconButton(
            icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
            color: _isFavorite ? Colors.amber : null,
            tooltip: _isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
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
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Başlık / Tanım',
                    hintText: 'Örn: AWS Production Token, SSH RSA Key',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Secret Type Dropdown
                DropdownButtonFormField<String>(
                  value: _secretType,
                  decoration: const InputDecoration(
                    labelText: 'Gizli Veri Türü',
                    prefixIcon: Icon(Icons.category_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _secretTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _secretType = val);
                  },
                ),
                const SizedBox(height: 16),

                // Secret Value (Monospace multi-line)
                TextField(
                  controller: _secretController,
                  obscureText: _obscureSecret,
                  maxLines: _obscureSecret ? 1 : 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Gizli Anahtar / Değer',
                    alignLabelWithHint: true,
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_obscureSecret ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          tooltip: _obscureSecret ? 'Değeri Göster' : 'Değeri Gizle',
                          onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: 'Kopyala (30 sn)',
                          onPressed: () async {
                            if (_secretController.text.isNotEmpty) {
                              await ClipboardService.copySecurely(_secretController.text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Gizli değer kopyalandı! (30 sn sonra temizlenir)')),
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

                // Extra Notes
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama veya Kullanım Notları',
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
