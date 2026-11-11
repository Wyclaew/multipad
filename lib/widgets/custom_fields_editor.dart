import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../services/clipboard_service.dart';

class CustomFieldsEditor extends StatefulWidget {
  final List<CustomField> fields;
  final ValueChanged<List<CustomField>> onChanged;

  const CustomFieldsEditor({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  @override
  State<CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<CustomFieldsEditor> {
  final Set<String> _revealedIds = <String>{};

  Future<void> _showFieldDialog({CustomField? existing}) async {
    final l10n = context.l10n;
    final labelController = TextEditingController(text: existing?.label ?? '');
    final valueController = TextEditingController(text: existing?.value ?? '');
    bool isHidden = existing?.isHidden ?? false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            existing == null
                ? l10n.tr('Özel Alan Ekle', 'Add Custom Field')
                : l10n.tr('Özel Alanı Düzenle', 'Edit Custom Field'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(
                  labelText: l10n.tr('Alan Adı (örn. IBAN, Güvenlik Sorusu)', 'Field Label'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                maxLines: isHidden ? 1 : 3,
                obscureText: isHidden,
                decoration: InputDecoration(
                  labelText: l10n.tr('Değer', 'Value'),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.tr('Değeri Maskele (Gizli Alan)', 'Mask Value (Hidden)')),
                value: isHidden,
                onChanged: (v) => setDlgState(() => isHidden = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final cleanLabel = labelController.text.trim();
      final cleanValue = valueController.text;
      if (cleanLabel.isEmpty) return;

      final next = List<CustomField>.from(widget.fields);
      if (existing == null) {
        next.add(
          CustomField(
            id: const Uuid().v4(),
            label: cleanLabel,
            value: cleanValue,
            isHidden: isHidden,
          ),
        );
      } else {
        final idx = next.indexWhere((f) => f.id == existing.id);
        if (idx >= 0) {
          next[idx] = existing.copyWith(
            label: cleanLabel,
            value: cleanValue,
            isHidden: isHidden,
          );
        }
      }
      widget.onChanged(next);
    }
  }

  Future<void> _copyValue(CustomField field) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(field.value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(field.label, timeout))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.tr('Özel Alanlar (${widget.fields.length})', 'Custom Fields (${widget.fields.length})'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () => _showFieldDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.tr('Alan Ekle', 'Add Field')),
            ),
          ],
        ),
        if (widget.fields.isEmpty)
          Text(
            l10n.tr(
              'IBAN, kurtarma kodu, güvenlik sorusu gibi ek alanlar ekleyebilirsiniz.',
              'Add extra fields like IBAN, recovery code, or security questions.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          )
        else
          ...widget.fields.map((field) {
            final revealed = !field.isHidden || _revealedIds.contains(field.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                title: Text(
                  field.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  revealed ? field.value : '••••••••••••',
                  style: TextStyle(
                    fontFamily: field.isHidden ? 'monospace' : null,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (field.isHidden)
                      IconButton(
                        icon: Icon(
                          revealed ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                        ),
                        tooltip: revealed ? 'Gizle' : 'Göster',
                        onPressed: () {
                          setState(() {
                            if (revealed) {
                              _revealedIds.remove(field.id);
                            } else {
                              _revealedIds.add(field.id);
                            }
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: l10n.copy,
                      onPressed: () => _copyValue(field),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: l10n.edit,
                      onPressed: () => _showFieldDialog(existing: field),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                      tooltip: l10n.delete,
                      onPressed: () {
                        final next = widget.fields
                            .where((f) => f.id != field.id)
                            .toList();
                        widget.onChanged(next);
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
