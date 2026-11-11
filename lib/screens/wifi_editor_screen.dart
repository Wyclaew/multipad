import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../widgets/custom_fields_editor.dart';
import '../widgets/folder_selector.dart';
import '../widgets/password_generator_dialog.dart';
import '../widgets/revision_history_sheet.dart';

class WifiEditorScreen extends StatefulWidget {
  final VaultItem? initialItem;
  final String? initialFolderId;

  const WifiEditorScreen({
    super.key,
    this.initialItem,
    this.initialFolderId,
  });

  @override
  State<WifiEditorScreen> createState() => _WifiEditorScreenState();
}

class _WifiEditorScreenState extends State<WifiEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _ssidController;
  late TextEditingController _passwordController;
  late TextEditingController _notesController;
  late TextEditingController _tagInputController;

  late String _security;
  late bool _hidden;
  late List<String> _tags;
  late List<CustomField> _customFields;
  late List<VaultItemRevision> _revisions;
  String? _folderId;
  late bool _isFavorite;
  late bool _isPinned;
  bool _obscurePassword = true;
  bool _isSaving = false;

  late String _originalTitle;
  late String _originalSsid;
  late String _originalPassword;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _originalTitle = item?.title ?? '';
    _originalSsid = item?.wifiSsid ?? '';
    _originalPassword = item?.wifiPassword ?? '';

    _titleController = TextEditingController(text: _originalTitle);
    _ssidController = TextEditingController(text: _originalSsid);
    _passwordController = TextEditingController(text: _originalPassword);
    _notesController = TextEditingController(text: item?.content ?? '');
    _tagInputController = TextEditingController();

    _security = item?.wifiSecurity ?? 'WPA';
    if (!['WPA', 'WEP', 'nopass'].contains(_security)) {
      _security = 'WPA';
    }
    _hidden = item?.wifiHidden ?? false;
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
    _ssidController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges =>
      _titleController.text != _originalTitle ||
      _ssidController.text != _originalSsid ||
      _passwordController.text != _originalPassword;

  VaultItem _buildDraft(VaultProvider vault) {
    final base = widget.initialItem ?? vault.createNewWifi(folderId: _folderId);
    final title = _titleController.text.trim();
    final ssid = _ssidController.text.trim();
    return base.copyWith(
      title: title.isNotEmpty ? title : (ssid.isNotEmpty ? ssid : 'Wi-Fi Ağı'),
      wifiSsid: ssid,
      wifiPassword: _security == 'nopass' ? '' : _passwordController.text,
      wifiSecurity: _security,
      wifiHidden: _hidden,
      content: _notesController.text.trim(),
      folderId: _folderId,
      clearFolderId: _folderId == null,
      tags: _tags,
      customFields: _customFields,
      revisions: _revisions,
      isFavorite: _isFavorite,
      isPinned: _isPinned,
    );
  }

  Future<void> _copyField(String value, String label) async {
    final timeout = context.read<SettingsProvider>().clipboardTimeoutSeconds;
    await ClipboardService.copySecurely(value, timeoutSeconds: timeout);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.copiedWithTimeout(label, timeout))),
    );
  }

  Future<void> _openPasswordGenerator() async {
    final generated = await showDialog<String>(
      context: context,
      builder: (_) => const PasswordGeneratorDialog(),
    );
    if (generated != null && generated.isNotEmpty) {
      setState(() => _passwordController.text = generated);
    }
  }

  Future<void> _saveWifi() async {
    if (_titleController.text.trim().isEmpty &&
        _ssidController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    final vault = context.read<VaultProvider>();
    final updated = _buildDraft(vault);
    await vault.saveItem(updated);
    _originalTitle = _titleController.text;
    _originalSsid = _ssidController.text;
    _originalPassword = _passwordController.text;
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
    final vault = context.read<VaultProvider>();
    final draft = _buildDraft(vault);
    final canShowQr = draft.wifiSsid.trim().isNotEmpty;

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
                ? l10n.tr('Yeni Wi-Fi Ağı', 'New Wi-Fi Network')
                : l10n.tr('Wi-Fi Kaydını Düzenle', 'Edit Wi-Fi'),
          ),
          actions: [
            if (widget.initialItem != null)
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () {
                  RevisionHistorySheet.show(
                    context,
                    item: draft,
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
              IconButton(icon: const Icon(Icons.check), onPressed: _saveWifi),
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
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Ağ Başlığı (örn. Ev Wi-Fi, Ofis)',
                    prefixIcon: Icon(Icons.wifi),
                  ),
                ),
                const SizedBox(height: 12),
                FolderSelector(
                  selectedFolderId: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ssidController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Ağ Adı (SSID)',
                    prefixIcon: const Icon(Icons.router_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        if (_ssidController.text.isNotEmpty) {
                          _copyField(_ssidController.text, 'Wi-Fi SSID');
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _security,
                  decoration: const InputDecoration(
                    labelText: 'Güvenlik Protokolü',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'WPA', child: Text('WPA / WPA2 / WPA3')),
                    DropdownMenuItem(value: 'WEP', child: Text('WEP (Eski)')),
                    DropdownMenuItem(value: 'nopass', child: Text('Şifresiz (Açık Ağ)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _security = val);
                  },
                ),
                if (_security != 'nopass') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Wi-Fi Parolası',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.auto_fix_high),
                            onPressed: _openPasswordGenerator,
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              if (_passwordController.text.isNotEmpty) {
                                _copyField(
                                  _passwordController.text,
                                  'Wi-Fi Parolası',
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gizli Ağ (Hidden SSID)'),
                  value: _hidden,
                  onChanged: (v) => setState(() => _hidden = v),
                ),
                if (canShowQr) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            l10n.tr('QR Kod ile Wi-Fi Paylaş', 'Share Wi-Fi via QR'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: QrImageView(
                              data: draft.toWifiQrPayload(),
                              size: 170,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.tr(
                              'Misafirler telefon kamerasıyla okutup doğrudan bağlanabilir.',
                              'Guests can scan this QR code with their phone camera to join.',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
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
                    labelText: 'Modem Arayüzü / Notlar',
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
