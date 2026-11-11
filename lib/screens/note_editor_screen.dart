import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';
import '../widgets/attachments_section.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/markdown_checklist_view.dart';
import '../widgets/revision_history_sheet.dart';

class NoteEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const NoteEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final String _itemId;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultAttachmentMeta> _attachments;
  late List<VaultItemRevision> _revisions;
  String? _folderId;

  late bool _isFavorite;
  late bool _isPinned;
  bool _isPreviewMode = false;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalContent;
  late List<String> _originalTags;
  late String? _originalFolderId;
  late int _originalFieldCount;
  late int _originalAttachmentCount;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _itemId = item?.id ?? const Uuid().v4();
    _originalTitle = item?.title ?? '';
    _originalContent = item?.content ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _contentController = TextEditingController(text: _originalContent);
    _tagInputController = TextEditingController();
    _tags = List<String>.from(item?.tags ?? const []);
    _customFields = List<CustomField>.from(item?.customFields ?? const []);
    _attachments = List<VaultAttachmentMeta>.from(
      item?.attachments ?? const [],
    );
    _revisions = List<VaultItemRevision>.from(item?.revisions ?? const []);
    _folderId = item?.folderId ?? widget.initialFolderId;

    _originalTags = List<String>.from(_tags);
    _originalFolderId = _folderId;
    _originalFieldCount = _customFields.length;
    _originalAttachmentCount = _attachments.length;

    _isFavorite = item?.isFavorite ?? false;
    _isPinned = item?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _contentController.text != _originalContent ||
      _folderId != _originalFolderId ||
      _tags.join(',') != _originalTags.join(',') ||
      _customFields.length != _originalFieldCount ||
      _attachments.length != _originalAttachmentCount;

  void _insertMarkdownSnippet(String snippet) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final prefixNewline =
        start > 0 && text[start - 1] != '\n' && snippet.startsWith('\n') == false
            ? ''
            : '';
    final updated = text.replaceRange(start, end, '$prefixNewline$snippet');
    _contentController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: start + prefixNewline.length + snippet.length,
      ),
    );
    setState(() {});
  }

  Future<void> _saveNote() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty && _attachments.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final base =
        widget.initialItem ?? vault.createNewNote(folderId: _folderId).copyWith(id: _itemId);

    final updatedItem = base.copyWith(
      id: _itemId,
      title: title.isEmpty ? 'Başlıksız Not' : title,
      content: _contentController.text,
      folderId: _folderId,
      clearFolderId: _folderId == null,
      tags: _tags,
      customFields: _customFields,
      attachments: _attachments,
      revisions: _revisions,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
    );

    await vault.saveItem(updatedItem);

    _originalTitle = _titleController.text;
    _originalContent = _contentController.text;
    _originalTags = List<String>.from(_tags);
    _originalFolderId = _folderId;
    _originalFieldCount = _customFields.length;
    _originalAttachmentCount = _attachments.length;

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
        title: Text(context.l10n.tr('Kaydedilmemiş Değişiklikler', 'Unsaved Changes')),
        content: Text(
          context.l10n.tr(
            'Yaptığınız değişiklikler kaydedilmedi. Çıkmak istediğinize emin misiniz?',
            'Discard unsaved changes?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Düzenlemeye Devam Et', 'Keep Editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.tr('Kaydetmeden Çık', 'Discard')),
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
                ? l10n.tr('Yeni Güvenli Not', 'New Secure Note')
                : l10n.tr('Notu Düzenle', 'Edit Note'),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPreviewMode ? Icons.edit_note : Icons.visibility_outlined,
              ),
              tooltip: _isPreviewMode
                  ? l10n.tr('Düzenleme Modu', 'Edit Mode')
                  : l10n.tr('Markdown & Liste Önizleme', 'Markdown Preview'),
              onPressed: () => setState(() => _isPreviewMode = !_isPreviewMode),
            ),
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: l10n.tr('Sürüm Geçmişi', 'Version History'),
                onPressed: () {
                  RevisionHistorySheet.show(
                    context,
                    item: widget.initialItem!.copyWith(
                      title: _titleController.text,
                      content: _contentController.text,
                      revisions: _revisions,
                    ),
                    onRestore: (rev) {
                      setState(() {
                        _titleController.text = rev.title;
                        _contentController.text = rev.content;
                      });
                    },
                  );
                },
              ),
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              tooltip: l10n.tr('Başa Sabitle', 'Pin'),
              color: _isPinned ? theme.colorScheme.primary : null,
              onPressed: () => setState(() => _isPinned = !_isPinned),
            ),
            IconButton(
              icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
              tooltip: l10n.tr('Favorilere Ekle', 'Favorite'),
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
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: l10n.save,
                onPressed: _saveNote,
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  onChanged: (_) => setState(() {}),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.tr('Başlık...', 'Title...'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
                const SizedBox(height: 8),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 12),
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
                      width: 170,
                      child: TextField(
                        controller: _tagInputController,
                        decoration: InputDecoration(
                          hintText: l10n.tr('+ Etiket ekle', '+ Add tag'),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: _addTag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Formatting toolbar + edit/preview switcher
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.edit, size: 16),
                            label: Text(l10n.tr('Düzenle', 'Edit')),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.checklist, size: 16),
                            label: Text(l10n.tr('Önizle / Liste', 'Preview')),
                          ),
                        ],
                        selected: {_isPreviewMode},
                        onSelectionChanged: (s) =>
                            setState(() => _isPreviewMode = s.first),
                      ),
                      if (!_isPreviewMode) ...[
                        const SizedBox(width: 10),
                        ActionChip(
                          avatar: const Icon(Icons.check_box_outlined, size: 16),
                          label: const Text('To-Do'),
                          onPressed: () =>
                              _insertMarkdownSnippet('\n- [ ] '),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          label: const Text('H1'),
                          onPressed: () => _insertMarkdownSnippet('\n# '),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          label: const Text('**B**'),
                          onPressed: () =>
                              _insertMarkdownSnippet('**kalın**'),
                        ),
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: const Icon(Icons.code, size: 16),
                          label: const Text('Kod'),
                          onPressed: () => _insertMarkdownSnippet(
                            '\n```\n// kod\n```\n',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 24),
                if (_isPreviewMode)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: MarkdownChecklistView(
                      content: _contentController.text,
                      onToggleChecklist: (lineIdx, checked) {
                        setState(() {
                          _contentController.text =
                              MarkdownChecklistView.toggleTaskAtLine(
                                _contentController.text,
                                lineIdx,
                                checked,
                              );
                        });
                      },
                    ),
                  )
                else
                  TextField(
                    controller: _contentController,
                    maxLines: null,
                    minLines: 10,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: l10n.tr(
                        'Şifreli not içeriğinizi yazın... (- [ ] yapılacak listesi, # başlık, ```kod``` desteklenir)',
                        'Write encrypted note... (supports - [ ] checklists, # headings, ```code```)',
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
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
