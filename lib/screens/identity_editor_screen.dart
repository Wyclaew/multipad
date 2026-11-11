import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/audit_service.dart';
import '../services/clipboard_service.dart';
import '../widgets/attachments_section.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/revision_history_sheet.dart';

class IdentityEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const IdentityEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<IdentityEditorScreen> createState() => _IdentityEditorScreenState();
}

class _IdentityEditorScreenState extends State<IdentityEditorScreen> {
  late final String _itemId;
  late TextEditingController _titleController;
  late TextEditingController _fullNameController;
  late TextEditingController _idNumberController;
  late TextEditingController _nationalityController;
  late TextEditingController _birthDateController;
  late TextEditingController _issueDateController;
  late TextEditingController _expiryDateController;
  late TextEditingController _authorityController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;

  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultAttachmentMeta> _attachments;
  late List<VaultItemRevision> _revisions;
  String? _folderId;
  late bool _isFavorite;
  late bool _isPinned;
  bool _obscureNumber = false;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalNumber;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _itemId = item?.id ?? const Uuid().v4();
    _originalTitle = item?.title ?? '';
    _originalNumber = item?.idNumber ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _fullNameController = TextEditingController(text: item?.fullName ?? '');
    _idNumberController = TextEditingController(text: _originalNumber);
    _nationalityController = TextEditingController(
      text: item?.nationality ?? '',
    );
    _birthDateController = TextEditingController(text: item?.birthDate ?? '');
    _issueDateController = TextEditingController(text: item?.issueDate ?? '');
    _expiryDateController = TextEditingController(text: item?.expiryDate ?? '');
    _authorityController = TextEditingController(
      text: item?.issuingAuthority ?? '',
    );
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();

    _tags = List<String>.from(item?.tags ?? const []);
    _customFields = List<CustomField>.from(item?.customFields ?? const []);
    _attachments = List<VaultAttachmentMeta>.from(
      item?.attachments ?? const [],
    );
    _revisions = List<VaultItemRevision>.from(item?.revisions ?? const []);
    _folderId = item?.folderId ?? widget.initialFolderId;
    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fullNameController.dispose();
    _idNumberController.dispose();
    _nationalityController.dispose();
    _birthDateController.dispose();
    _issueDateController.dispose();
    _expiryDateController.dispose();
    _authorityController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _idNumberController.text != _originalNumber;

  Future<void> _copyField(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _saveIdentity() async {
    final title = _titleController.text.trim();
    if (title.isEmpty &&
        _fullNameController.text.trim().isEmpty &&
        _idNumberController.text.trim().isEmpty &&
        _attachments.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final base = widget.initialItem ??
        vault.createNewIdentity(folderId: _folderId).copyWith(id: _itemId);
    final updated = base.copyWith(
      id: _itemId,
      title: title.isEmpty ? 'Kimlik / Pasaport' : title,
      fullName: _fullNameController.text.trim(),
      idNumber: _idNumberController.text.trim(),
      nationality: _nationalityController.text.trim(),
      birthDate: _birthDateController.text.trim(),
      issueDate: _issueDateController.text.trim(),
      expiryDate: _expiryDateController.text.trim(),
      issuingAuthority: _authorityController.text.trim(),
      content: _notesController.text.trim(),
      folderId: _folderId,
      clearFolderId: _folderId == null,
      tags: _tags,
      customFields: _customFields,
      attachments: _attachments,
      revisions: _revisions,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
    );
    await vault.saveItem(updated);
    _originalTitle = _titleController.text;
    _originalNumber = _idNumberController.text;
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
                ? l10n.tr('Yeni Kimlik / Pasaport', 'New ID / Passport')
                : l10n.tr('Kimlik Kaydını Düzenle', 'Edit ID / Passport'),
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
              IconButton(icon: const Icon(Icons.check), onPressed: _saveIdentity),
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
                    labelText: 'Belge Başlığı (örn. T.C. Kimlik, Pasaport, Ehliyet)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _idNumberController,
                  obscureText: _obscureNumber,
                  decoration: InputDecoration(
                    labelText: 'Belge / Kimlik / Pasaport No',
                    prefixIcon: const Icon(Icons.numbers),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureNumber
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNumber = !_obscureNumber),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            if (_idNumberController.text.isNotEmpty) {
                              _copyField(_idNumberController.text, 'Belge No');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _birthDateController,
                        decoration: const InputDecoration(
                          labelText: 'Doğum Tarihi (GG.AA.YYYY)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _nationalityController,
                        decoration: const InputDecoration(labelText: 'Uyruk'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _issueDateController,
                        decoration: const InputDecoration(
                          labelText: 'Veriliş Tarihi',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _expiryDateController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Son Geçerlilik (YYYY-AA-GG)',
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
                TextField(
                  controller: _authorityController,
                  decoration: const InputDecoration(
                    labelText: 'Veren Makam / Nüfus Müdürlüğü',
                    prefixIcon: Icon(Icons.account_balance_outlined),
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
                    labelText: 'Ek Notlar / Seri No / Adres',
                    alignLabelWithHint: true,
                  ),
                ),
                const Divider(height: 32),
                AttachmentsSection(
                  itemId: _itemId,
                  attachments: _attachments,
                  onChanged: (next) => setState(() => _attachments = next),
                ),
                const Divider(height: 32),
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
