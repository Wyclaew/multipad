import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_folder.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../services/import_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportSourceFormat _formatHint = ImportSourceFormat.autoDetect;
  String? _fileName;
  String? _rawContent;
  ParsedImportPreview? _preview;
  CsvColumnMapping? _mapping;
  bool _isImporting = false;
  String? _error;

  String _formatLabel(ImportSourceFormat fmt, AppLocalizations l10n) {
    switch (fmt) {
      case ImportSourceFormat.autoDetect:
        return l10n.tr('Otomatik Algıla', 'Auto-Detect');
      case ImportSourceFormat.chromeEdgeCsv:
        return 'Chrome / Edge (CSV)';
      case ImportSourceFormat.bitwardenCsv:
        return 'Bitwarden (CSV)';
      case ImportSourceFormat.bitwardenJson:
        return 'Bitwarden (JSON)';
      case ImportSourceFormat.keepassCsv:
        return 'KeePass (CSV)';
      case ImportSourceFormat.keepassXml:
        return 'KeePass 2.x (XML)';
      case ImportSourceFormat.genericCsv:
        return l10n.tr('Genel CSV (Sütun Eşleştirmeli)', 'Generic CSV');
    }
  }

  void _parseContent(String raw, {String fileName = ''}) {
    try {
      final preview = ImportService.inspectFile(
        raw,
        fileName: fileName,
        formatHint: _formatHint,
      );
      setState(() {
        _rawContent = raw;
        _preview = preview;
        _mapping = preview.suggestedMapping;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _mapping = null;
        _error = 'Dosya ayrıştırılamadı: $e';
      });
    }
  }

  Future<void> _pickFile() async {
    final auth = context.read<AuthProvider>();
    try {
      final res = await auth.runWithoutAutoLock(
        () => FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv', 'json', 'xml', 'txt'],
          withData: true,
        ),
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        setState(() => _error = 'Seçilen dosya okunamadı.');
        return;
      }
      final raw = utf8.decode(bytes, allowMalformed: true);
      _fileName = file.name;
      _parseContent(raw, fileName: file.name);
    } catch (e) {
      setState(() => _error = 'Dosya seçim hatası: $e');
    }
  }

  Future<void> _pasteDialog() async {
    final ctrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV / JSON / XML İçeriği Yapıştır'),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Dışa aktarılan parola verisini buraya yapıştırın...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Önizle'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pasted != null && pasted.trim().isNotEmpty) {
      _fileName = 'pasted.txt';
      _parseContent(pasted);
    }
  }

  Future<void> _executeImport(
    List<VaultItem> items,
    List<VaultFolder> folders,
  ) async {
    final vault = context.read<VaultProvider>();
    if (vault.isDuressMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu modda toplu içe aktarma desteklenmiyor.'),
        ),
      );
      return;
    }

    setState(() => _isImporting = true);
    try {
      final count = await vault.importBulk(
        itemsToImport: items,
        foldersToImport: folders,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count kayıt${folders.isNotEmpty ? " ve ${folders.length} klasör" : ""} kasanıza şifrelenerek eklendi!',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _error = 'İçe aktarma hatası: $e';
        });
      }
    }
  }

  Widget _buildMappingDropdown(
    String label,
    int? currentValue,
    List<String> headers,
    ValueChanged<int?> onChanged,
  ) {
    final safeVal =
        (currentValue != null && currentValue >= 0 && currentValue < headers.length)
            ? currentValue
            : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<int?>(
        key: ValueKey<String>('$label:${headers.join("|")}:$safeVal'),
        initialValue: safeVal,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('— Eşleştirme Yok —')),
          for (int i = 0; i < headers.length; i++)
            DropdownMenuItem<int?>(
              value: i,
              child: Text('${headers[i]} (Sütun ${i + 1})'),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final built = (_preview != null && _mapping != null)
        ? ImportService.buildItemsFromPreview(_preview!, _mapping!)
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importPasswords)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.tr(
                          'Chrome, Edge, Bitwarden (CSV/JSON) veya KeePass (CSV/XML) yedeklerinizi şifreli MultiPad kasanıza aktarın.',
                          'Import exports from Chrome, Edge, Bitwarden (CSV/JSON), or KeePass (CSV/XML).',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<ImportSourceFormat>(
                        initialValue: _formatHint,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Kaynak Formatı', 'Source Format'),
                        ),
                        items: ImportSourceFormat.values
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(_formatLabel(f, l10n)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _formatHint = v);
                          if (_rawContent != null) {
                            _parseContent(
                              _rawContent!,
                              fileName: _fileName ?? '',
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isImporting ? null : _pickFile,
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                l10n.tr('Dosya Seç (CSV / JSON / XML)', 'Choose File'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _isImporting ? null : _pasteDialog,
                            icon: const Icon(Icons.paste),
                            label: Text(l10n.tr('Metin Yapıştır', 'Paste')),
                          ),
                        ],
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.tr("Seçilen dosya", "Selected file")}: $_fileName',
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.redAccent.withValues(alpha: 0.14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
              if (_preview != null && _mapping != null) ...[
                const SizedBox(height: 16),
                if (_preview!.headers.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sütun Eşleştirme (${_formatLabel(_preview!.detectedFormat, l10n)})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMappingDropdown(
                            'Başlık / Site Adı',
                            _mapping!.titleIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: v,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            'Kullanıcı Adı / E-posta',
                            _mapping!.usernameIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: v,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            'Şifre',
                            _mapping!.passwordIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: v,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            'Web Sitesi (URL)',
                            _mapping!.websiteIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: v,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            '2FA / TOTP Anahtarı',
                            _mapping!.totpIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: v,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            'Notlar',
                            _mapping!.notesIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: v,
                                folderIndex: _mapping!.folderIndex,
                              ),
                            ),
                          ),
                          _buildMappingDropdown(
                            'Klasör / Grup',
                            _mapping!.folderIndex,
                            _preview!.headers,
                            (v) => setState(
                              () => _mapping = CsvColumnMapping(
                                titleIndex: _mapping!.titleIndex,
                                usernameIndex: _mapping!.usernameIndex,
                                passwordIndex: _mapping!.passwordIndex,
                                websiteIndex: _mapping!.websiteIndex,
                                totpIndex: _mapping!.totpIndex,
                                notesIndex: _mapping!.notesIndex,
                                folderIndex: v,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (built != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Önizleme: ${built.items.length} kayıt'
                            '${built.folders.isNotEmpty ? ", ${built.folders.length} klasör" : ""}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...built.items.take(6).map(
                                (item) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    item.type == VaultItemType.note
                                        ? Icons.description_outlined
                                        : Icons.key_outlined,
                                  ),
                                  title: Text(item.title),
                                  subtitle: Text(
                                    item.username.isNotEmpty
                                        ? item.username
                                        : item.website,
                                  ),
                                ),
                              ),
                          if (built.items.length > 6)
                            Text(
                              '... ve ${built.items.length - 6} kayıt daha',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _isImporting || built.items.isEmpty
                                ? null
                                : () => _executeImport(
                                      built.items,
                                      built.folders,
                                    ),
                            icon: _isImporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_done),
                            label: Text(
                              '${built.items.length} Kaydı Kasaya Aktar',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
