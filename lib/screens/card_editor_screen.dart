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

class CardEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const CardEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _holderController;
  late TextEditingController _numberController;
  late TextEditingController _expiryController;
  late TextEditingController _cvvController;
  late TextEditingController _pinController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultItemRevision> _revisions;
  String? _folderId;

  late bool _isFavorite;
  late bool _isPinned;
  bool _obscureNumber = false;
  bool _obscureCvv = true;
  bool _obscurePin = true;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalNumber;
  late String? _originalFolderId;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _originalTitle = item?.title ?? '';
    _originalNumber = item?.cardNumber ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _holderController = TextEditingController(text: item?.cardHolder ?? '');
    _numberController = TextEditingController(text: _originalNumber);
    _expiryController = TextEditingController(text: item?.cardExpiry ?? '');
    _cvvController = TextEditingController(text: item?.cardCvv ?? '');
    _pinController = TextEditingController(text: item?.cardPin ?? '');
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();
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
    _holderController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _numberController.text != _originalNumber ||
      _folderId != _originalFolderId;

  Future<void> _copyField(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _saveCard() async {
    final title = _titleController.text.trim();
    if (title.isEmpty && _numberController.text.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final updated = (widget.initialItem ?? vault.createNewCard()).copyWith(
      title: title.isEmpty ? 'Adsız Kart' : title,
      cardHolder: _holderController.text.trim(),
      cardNumber: _numberController.text.trim(),
      cardExpiry: _expiryController.text.trim(),
      cardCvv: _cvvController.text.trim(),
      cardPin: _pinController.text.trim(),
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
    _originalNumber = _numberController.text;
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
          'Kart bilgileriniz kaydedilmedi. Çıkmak istediğinize emin misiniz?',
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
    final rawNum = _numberController.text;
    final hasDigits = rawNum.replaceAll(RegExp(r'[^0-9]'), '').isNotEmpty;
    final luhnOk = !hasDigits || AuditService.isValidLuhn(rawNum);
    final brand = hasDigits ? AuditService.detectCardBrand(rawNum) : 'Kart';
    final expiryWarn = AuditService.evaluateCardExpiry(_expiryController.text);

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
                ? l10n.tr('Yeni Ödeme Kartı', 'New Payment Card')
                : l10n.tr('Kartı Düzenle', 'Edit Card'),
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
              IconButton(icon: const Icon(Icons.check), onPressed: _saveCard),
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
                    labelText: 'Kart Adı (örn. Garanti Bonus, Enpara)',
                    prefixIcon: Icon(Icons.credit_card),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _holderController,
                  decoration: const InputDecoration(
                    labelText: 'Kart Üzerindeki İsim',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureNumber,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Kart Numarası',
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
                            if (_numberController.text.isNotEmpty) {
                              _copyField(
                                _numberController.text,
                                'Kart numarası',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasDigits) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        avatar: Icon(
                          luhnOk ? Icons.verified : Icons.error_outline,
                          size: 16,
                          color: luhnOk ? Colors.green : Colors.redAccent,
                        ),
                        label: Text(
                          luhnOk
                              ? '$brand • Luhn Geçerli'
                              : '$brand • Luhn Hatası (Numarayı kontrol edin)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _expiryController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Son Kullanma (AA/YY)',
                          prefixIcon: Icon(Icons.date_range),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _cvvController,
                        keyboardType: TextInputType.number,
                        obscureText: _obscureCvv,
                        decoration: InputDecoration(
                          labelText: 'CVV / CVC',
                          prefixIcon: const Icon(Icons.security),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCvv
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscureCvv = !_obscureCvv),
                          ),
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
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: _obscurePin,
                  decoration: InputDecoration(
                    labelText: 'Kart PIN Kodu (İsteğe Bağlı)',
                    prefixIcon: const Icon(Icons.dialpad),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePin ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscurePin = !_obscurePin),
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
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Banka Şubesi / Müşteri Hizmetleri / Ek Notlar',
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
