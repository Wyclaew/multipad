import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';

class AttachmentsSection extends StatefulWidget {
  final String itemId;
  final List<VaultAttachmentMeta> attachments;
  final ValueChanged<List<VaultAttachmentMeta>> onChanged;

  const AttachmentsSection({
    super.key,
    required this.itemId,
    required this.attachments,
    required this.onChanged,
  });

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  bool _isBusy = false;

  String _guessMime(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
      case '.md':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pickAndEncryptAttachment() async {
    final auth = context.read<AuthProvider>();
    final vault = context.read<VaultProvider>();

    setState(() => _isBusy = true);
    try {
      final result = await auth.runWithoutAutoLock(
        () => FilePicker.pickFiles(withData: true),
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) return;

      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maksimum 10 MB dosya eki desteklenmektedir.'),
          ),
        );
        return;
      }

      final meta = await vault.encryptAndStoreAttachment(
        itemId: widget.itemId,
        fileName: file.name,
        mimeType: _guessMime(file.name),
        bytes: bytes,
      );

      widget.onChanged([...widget.attachments, meta]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${meta.fileName} AES-256-GCM ile şifrelenip eklendi.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya eki eklenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _previewOrExport(VaultAttachmentMeta meta) async {
    final vault = context.read<VaultProvider>();
    final bytes = await vault.loadDecryptedAttachment(meta.id);
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dosya bu cihazın yerel şifreli önbelleğinde bulunamadı.'),
        ),
      );
      return;
    }

    final isImage = meta.mimeType.startsWith('image/');
    final isText = meta.mimeType.startsWith('text/');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(meta.fileName, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  )
                else if (isText)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      utf8.decode(bytes, allowMalformed: true),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Boyut: ${_formatSize(meta.sizeBytes)}\nSHA-256: ${meta.sha256}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final savedPath = await auth.runWithoutAutoLock(
                () => FilePicker.saveFile(
                  dialogTitle: 'Şifresi Çözülen Dosyayı Kaydet',
                  fileName: meta.fileName,
                  bytes: bytes,
                ),
              );
              if (savedPath != null && savedPath.isNotEmpty) {
                try {
                  final target = File(savedPath);
                  if (!await target.exists() || await target.length() == 0) {
                    await target.writeAsBytes(bytes);
                  }
                } catch (e) {
                  debugPrint('Export write fallback warning: $e');
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dosya dışa aktarıldı.')),
                  );
                }
              }
            },
            child: const Text('Dışa Aktar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeAttachment(VaultAttachmentMeta meta) async {
    final vault = context.read<VaultProvider>();
    await vault.deleteEncryptedAttachment(meta.id);
    widget.onChanged(
      widget.attachments.where((a) => a.id != meta.id).toList(),
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
              l10n.tr(
                'Şifreli Dosya Ekleri (${widget.attachments.length})',
                'Encrypted Attachments (${widget.attachments.length})',
              ),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _isBusy ? null : _pickAndEncryptAttachment,
              icon: _isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, size: 18),
              label: Text(l10n.tr('Dosya / Belge Ekle', 'Attach File')),
            ),
          ],
        ),
        if (widget.attachments.isEmpty)
          Text(
            l10n.tr(
              'Kurtarma belgeleri, kimlik görselleri veya dosyaları AES-256-GCM ile şifreleyip ekleyebilirsiniz.',
              'Attach recovery docs or ID scans encrypted locally with AES-256-GCM.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          )
        else
          ...widget.attachments.map(
            (meta) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  meta.mimeType.startsWith('image/')
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(meta.fileName, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_formatSize(meta.sizeBytes)} • AES-256-GCM'),
                onTap: () => _previewOrExport(meta),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  onPressed: () => _removeAttachment(meta),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
