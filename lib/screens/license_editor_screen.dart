import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/clipboard_service.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/revision_history_sheet.dart';

class LicenseEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const LicenseEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<LicenseEditorScreen> createState() => _LicenseEditorScreenState();
}

class _LicenseEditorScreenState extends State<LicenseEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _productController;
  late TextEditingController _keyController;
  late TextEditingController _licensedToController;
  late TextEditingController _purchaseDateController;
  late TextEditingController _expiryDateController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;

  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultItemRevision> _revisions;
  String? _folderId;
  late bool _isFavorite;
  late bool _isPinned;
  bool _obscureKey = false;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalKey;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _originalTitle = item?.title ?? '';
    _originalKey = item?.licenseKey ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _productController = TextEditingController(text: item?.productName ?? '');
    _keyController = TextEditingController(text: _originalKey);
    _licensedToController = TextEditingController(
      text: item?.licensedTo ?? '',
    );
    _purchaseDateController = TextEditingController(
      text: item?.purchaseDate ?? '',
    );
    _expiryDateController = TextEditingController(
      text: item?.licenseExpiry ?? '',
    );
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();

    _tags = List<String>.from(item?.tags ?? const []);
    _customFields = List<CustomField>.from(item?.customFields ?? const []);
    _revisions = List<VaultItemRevision>.from(item?.revisions ?? const []);
    _folderId = item?.folderId ?? widget.initialFolderId;
    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _productController.dispose();
    _keyController.dispose();
    _licensedToController.dispose();
    _purchaseDateController.dispose();
    _expiryDateController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _keyController.text != _originalKey;

  Future<void> _copyField(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _saveLicense() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _keyController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final base = widget.initialItem ?? vault.createNewLicense(folderId: _folderId);
    final updated = base.copyWith(
      title: title.isNotEmpty
          ? title
          : (_productController.text.trim().isNotEmpty
                ? _productController.text.trim()
                : 'Yazılım Lisansı'),
      productName: _productController.text.trim(),
      licenseKey: _keyController.text.trim(),
      licensedTo: _licensedToController.text.trim(),
      purchaseDate: _purchaseDateController.text.trim(),
      licenseExpiry: _expiryDateController.text.trim(),
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
    _originalKey = _keyController.text;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final expiryWarn = AuditService.evaluateDocumentExpiry(
      _expiryDateController.text,
    );

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kaydedilmemiş Değişiklikler'),
            content: const Text('Değişiklikleri kaydetmeden çıkmak istiyor musunuz?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Çık'),
              ),
            ],
          ),
        );
        if ((discard ?? false) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.initialItem == null
                ? l10n.tr('Yeni Yazılım Lisansı', 'New Software License')
                : l10n.tr('Lisansı Düzenle', 'Edit License'),
          ),
          actions: [
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () {
                  RevisionHistorySheet.show(
                    context,
                    item: widget.initialItem!.copyWith(
                      title: _titleController.text,
                      content: _notesController.text,
                      revisions: _revisions,
                    ),
                    onRestore: (rev) {
                      setState(() {
                        _titleController.text = rev.title;
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
              IconButton(icon: const Icon(Icons.check), onPressed: _saveLicense),
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
                    labelText: 'Lisans Başlığı (örn. JetBrains, Windows Pro)',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _productController,
                  decoration: const InputDecoration(
                    labelText: 'Yazılım / Ürün Adı',
                    prefixIcon: Icon(Icons.apps_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  maxLines: _obscureKey ? 1 : 3,
                  minLines: 1,
                  obscureText: _obscureKey,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Lisans Anahtarı (Serial Key)',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscureKey = !_obscureKey),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            if (_keyController.text.isNotEmpty) {
                              _copyField(_keyController.text, 'Lisans anahtarı');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _licensedToController,
                  decoration: const InputDecoration(
                    labelText: 'Lisans Sahibi (Ad / E-posta)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _purchaseDateController,
                        decoration: const InputDecoration(
                          labelText: 'Satın Alma Tarihi',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _expiryDateController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Bitiş Tarihi (YYYY-AA-GG)',
                        ),
                      ),
                    ),
                  ],
                ),
                if (expiryWarn != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    expiryWarn,
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._tags.map(
                      (tag) => Chip(
                        label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                        onDeleted: () => setState(() => _tags.remove(tag)),
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
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Fatura / Kurulum Notları',
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
