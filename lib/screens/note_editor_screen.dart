import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';

class NoteEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;

  const NoteEditorScreen({super.key, this.initialItem});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late bool _isFavorite;
  late String _itemId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _itemId = item?.id ?? '';
    _titleController = TextEditingController(text: item?.title ?? '');
    _contentController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
    _tags = List<String>.from(item?.tags ?? []);
    _isFavorite = item?.isFavorite ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();

    final updatedItem = (widget.initialItem ?? vault.createNewNote()).copyWith(
      title: title.isEmpty ? 'Başlıksız Not' : title,
      content: content,
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
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notu Sil'),
        content: const Text('Bu şifreli notu silmek istediğinize emin misiniz?'),
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
        title: Text(widget.initialItem == null ? 'Yeni Not' : 'Notu Düzenle'),
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
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title Field
                TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    hintText: 'Not Başlığı...',
                    border: InputBorder.none,
                  ),
                ),
                const Divider(),

                // Tags chips & input
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
                      width: 120,
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
                const SizedBox(height: 12),

                // Note Body
                TextField(
                  controller: _contentController,
                  maxLines: null,
                  minLines: 15,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Şifrelenecek notunuzu buraya yazın...',
                    border: InputBorder.none,
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
