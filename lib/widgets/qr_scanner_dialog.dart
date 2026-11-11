import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/qr_scanner_service.dart';

class QrScannerDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const QrScannerDialog({
    super.key,
    required this.title,
    this.subtitle = '',
  });

  static Future<String?> scan(
    BuildContext context, {
    String title = 'QR Kod Tara',
    String subtitle = '',
  }) async {
    final auth = context.read<AuthProvider>();
    return await auth.runWithoutAutoLock(
      () => showDialog<String>(
        context: context,
        builder: (_) => QrScannerDialog(title: title, subtitle: subtitle),
      ),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  MobileScannerController? _controller;
  bool _handled = false;
  bool _useCamera = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool _isDecodingFile = false;
  String? _error;

  bool get _supportsCamera =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_useCamera && _supportsCamera) {
      _initCamera();
    }
  }

  void _initCamera() {
    _controller?.dispose();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      formats: [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickImageFile() async {
    setState(() {
      _isDecodingFile = true;
      _error = null;
    });
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) {
        if (mounted) setState(() => _isDecodingFile = false);
        return;
      }
      final file = res.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        if (mounted) {
          setState(() {
            _isDecodingFile = false;
            _error = 'Görsel dosyası okunamadı.';
          });
        }
        return;
      }

      final decoded = QrScannerService.decodeQrFromImageBytes(bytes);
      if (decoded != null && decoded.trim().isNotEmpty) {
        if (mounted) Navigator.pop(context, decoded.trim());
      } else {
        if (mounted) {
          setState(() {
            _isDecodingFile = false;
            _error = 'Seçilen görselde geçerli bir QR kod bulunamadı.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDecodingFile = false;
          _error = 'Görsel taranırken hata oluştu: $e';
        });
      }
    }
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handled = true;
        if (mounted) Navigator.pop(context, raw.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle.isNotEmpty) ...[
              Text(widget.subtitle, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            if (_useCamera && _supportsCamera && _controller != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 240,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller!,
                        onDetect: _onBarcodeDetect,
                        errorBuilder: (ctx, err) {
                          return Container(
                            color: Colors.black87,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.videocam_off_outlined,
                                  color: Colors.white70,
                                  size: 36,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.tr(
                                    'Kamera açılamadı (${err.errorCode.name}). Görsel seçerek tarayabilirsiniz.',
                                    'Camera unavailable (${err.errorCode.name}). Pick an image instead.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Center(
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.indigoAccent.withValues(alpha: 0.85),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.image_search_rounded,
                      size: 44,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.tr(
                        'Ekran görüntüsü veya QR kod görseli seçerek otomatik çözebilirsiniz.',
                        'Pick a screenshot or QR image file to decode it automatically.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (_supportsCamera)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _useCamera = !_useCamera;
                          if (_useCamera) {
                            _initCamera();
                          } else {
                            _controller?.dispose();
                            _controller = null;
                          }
                        });
                      },
                      icon: Icon(
                        _useCamera ? Icons.stop_circle_outlined : Icons.camera_alt_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _useCamera
                            ? l10n.tr('Kamerayı Kapat', 'Stop Camera')
                            : l10n.tr('Kamera ile Tara', 'Use Camera'),
                      ),
                    ),
                  ),
                if (_supportsCamera) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isDecodingFile ? null : _pickImageFile,
                    icon: _isDecodingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(l10n.tr('Görsel Seç', 'Pick Image')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
