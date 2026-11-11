import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/revision_history_sheet.dart';

class SecretEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const SecretEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

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
  late List<CustomField> _customFields;
  late List<VaultItemRevision> _revisions;
  String? _folderId;

  late bool _isFavorite;
  late bool _isPinned;
  bool _obscureSecret = false;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalSecret;
  late String? _originalFolderId;

  final List<String> _secretTypes = [
    'Genel Gizli Bilgi',
    'API Anahtarı / Token',
    'Kurtarma İfadesi (Seed Phrase)',
    'SSH Özel Anahtarı',
    'Lisans Kodu',
    'Veritabanı Bağlantısı',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _originalTitle = item?.title ?? '';
    _originalSecret = item?.password ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _secretController = TextEditingController(text: _originalSecret);
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
    _secretType = item?.secretType ?? _secretTypes.first;
    if (!_secretTypes.contains(_secretType)) {
      _secretTypes.add(_secretType);
    }
    _tags = List<String>.from(item?.tags ?? const []);
    _customFields = List<CustomField>.from(item?.customFields ?? const []);
    _revisions = List<VaultItemRevision>.from(item?.revisions ?? const []);
    _folderId = item?.folderId ?? widget.initialFolderId;
    _originalFolderId = _folderId;

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

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _secretController.text != _originalSecret ||
      _folderId != _originalFolderId;

  Future<void> _copySecret(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _saveSecret() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _secretController.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final updated = (widget.initialItem ?? vault.createNewSecret()).copyWith(
      title: title.isEmpty ? 'Adsız Gizli Kayıt' : title,
      secretType: _secretType,
      password: _secretController.text.trim(),
      content: _notesController.text.trim(),
      folderId: _folderId,
      clearFolderId: _folderId == null,
      tags: _tags,
      customFields: _customFields,
      revisions: _revisions,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
    );

    await vault.saveItem(updated);
    _originalTitle = _titleController.text;
    _originalSecret = _secretController.text;
    _originalFolderId = _folderId;

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
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

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş Değişiklikler'),
        content: const Text(
          'Gizli kayıt değişiklikleri kaydedilmedi. Çıkmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Düzenlemeye Devam Et'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Kaydetmeden Çık'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initialItem == null
                ? l10n.tr('Yeni Gizli Anahtar / Kod', 'New Secret Key')
                : l10n.tr('Gizli Kaydı Düzenle', 'Edit Secret'),
          ),
          actions: [
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: l10n.tr('Sürüm Geçmişi', 'Version History'),
                onPressed: () {
                  RevisionHistorySheet.show(
                    context,
                    item: widget.initialItem!.copyWith(
                      title: _titleController.text,
                      password: _secretController.text,
                      content: _notesController.text,
                      revisions: _revisions,
                    ),
                    onRestore: (rev) {
                      setState(() {
                        _titleController.text = rev.title;
                        if (rev.password.isNotEmpty) {
                          _secretController.text = rev.password;
                        }
                        _notesController.text = rev.content;
                      });
                    },
                  );
                },
              ),
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              color: _isPinned ? theme.colorScheme.primary : null,
              onPressed: () => setState(() => _isPinned = !_isPinned),
            ),
            IconButton(
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
              color: _isFavorite ? Colors.amber : null,
              onPressed: () => setState(() => _isFavorite = !_isFavorite),
            ),
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(icon: const Icon(Icons.check), onPressed: _saveSecret),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Kayıt Başlığı (örn. OpenAI API Key, Ledger 24-Kelime)',
                    prefixIcon: Icon(Icons.enhanced_encryption),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _secretType,
                  decoration: const InputDecoration(
                    labelText: 'Gizli Bilgi Türü',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _secretTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _secretType = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _secretController,
                  maxLines: _obscureSecret ? 1 : 5,
                  minLines: 1,
                  obscureText: _obscureSecret,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Gizli Değer / Anahtar / Token',
                    alignLabelWithHint: true,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureSecret
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscureSecret = !_obscureSecret),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            if (_secretController.text.isNotEmpty) {
                              _copySecret(
                                _secretController.text,
                                'Gizli anahtar',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                      width: 150,
                      child: TextField(
                        controller: _tagInputController,
                        decoration: const InputDecoration(
                          hintText: '+ Etiket ekle',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama / Kullanım Notları',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                CustomFieldsEditor(
                  fields: _customFields,
                  onChanged: (next) => setState(() => _customFields = next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
