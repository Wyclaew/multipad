import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/native_bridge_service.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({
    super.key,
    required this.info,
  });

  /// Displays the standalone responsive UpdateDialog.
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String? _statusMessage;
  String? _errorMessage;
  bool _isReadyToInstall = false;
  bool _permissionRequired = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final asset = widget.info.platformAsset;
    if (asset == null) return;

    setState(() {
      _downloading = true;
      _progress = 0.0;
      _errorMessage = null;
      _permissionRequired = false;
      _statusMessage = context.l10n.tr('İndirme hazırlanıyor...', 'Preparing download...');
    });

    try {
      Future<String> action() {
        return UpdateService.downloadAndInstall(
          asset,
          inPlace: true,
          installImmediately: false,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onStatus: (s) {
            if (mounted) setState(() => _statusMessage = s);
          },
        );
      }

      try {
        final auth = context.read<AuthProvider?>();
        if (auth != null) {
          await auth.runWithoutAutoLockUntilResumed(action);
        } else {
          await action();
        }
      } catch (_) {
        await action();
      }

      if (!mounted) return;
      setState(() {
        _downloading = false;
        _isReadyToInstall = true;
        _progress = 1.0;
        _statusMessage = context.l10n.tr(
          'Güncelleme hazırlandı. Kuruluma geçebilirsiniz.',
          'Update prepared. Ready to install.',
        );
      });
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      final isPerm = errStr.contains('PERMISSION_REQUIRED') ||
          (e is PlatformException && e.code == 'PERMISSION_REQUIRED');
      setState(() {
        _downloading = false;
        _errorMessage = errStr;
        _permissionRequired = isPerm;
      });
    }
  }

  Future<void> _triggerInstall() async {
    final asset = widget.info.platformAsset;
    if (asset == null) return;

    setState(() {
      _errorMessage = null;
      _permissionRequired = false;
      _statusMessage = context.l10n.tr('Kurulum başlatılıyor...', 'Starting installation...');
    });

    try {
      Future<String> action() {
        return UpdateService.downloadAndInstall(
          asset,
          inPlace: true,
          installImmediately: true,
          onStatus: (s) {
            if (mounted) setState(() => _statusMessage = s);
          },
        );
      }

      String resultMsg;
      try {
        final auth = context.read<AuthProvider?>();
        if (auth != null) {
          resultMsg = await auth.runWithoutAutoLockUntilResumed(action);
        } else {
          resultMsg = await action();
        }
      } catch (_) {
        resultMsg = await action();
      }

      if (!mounted) return;
      setState(() {
        _statusMessage = resultMsg;
      });
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      final isPerm = errStr.contains('PERMISSION_REQUIRED') ||
          (e is PlatformException && e.code == 'PERMISSION_REQUIRED');
      setState(() {
        _errorMessage = errStr;
        _permissionRequired = isPerm;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final asset = widget.info.platformAsset;
    final hasExpectedSha =
        asset?.expectedSha256 != null && asset!.expectedSha256!.isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              l10n.tr('Yeni Sürüm Mevcut', 'Update Available'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Version Transition Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.info.currentVersion,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.info.latestVersion,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              if (asset != null) ...[
                const SizedBox(height: 12),
                // File Size & SHA-256 Badge Row
                Row(
                  children: [
                    if (asset.size > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_present_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(asset.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasExpectedSha
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasExpectedSha
                                ? Colors.green.withValues(alpha: 0.4)
                                : Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasExpectedSha
                                  ? Icons.verified_user_rounded
                                  : Icons.info_outline_rounded,
                              size: 14,
                              color: hasExpectedSha
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                hasExpectedSha
                                    ? l10n.tr(
                                        'SHA-256 Doğrulandı',
                                        'SHA-256 Verified',
                                      )
                                    : l10n.tr(
                                        'SHA-256 Özeti Yok',
                                        'No SHA-256 Digest',
                                      ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: hasExpectedSha
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Release Notes Container
              if (widget.info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: SelectableText(
                        widget.info.releaseNotes,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                      ),
                    ),
                  ),
                ),
              ],

              // Download / Installation Progress Bar & Status
              if (_downloading || _progress > 0) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _statusMessage ??
                            l10n.tr('İndiriliyor...', 'Downloading...'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isReadyToInstall
                              ? Colors.green
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: _isReadyToInstall
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_downloading && _progress > 0)
                      Text(
                        '${(_progress * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],

              // Android Unknown Sources Permission Banner
              if (_permissionRequired) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.security_update_warning_rounded,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.tr(
                                'Yükleme İzni Gerekli',
                                'Install Permission Required',
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.tr(
                          'MultiPad güncellemelerinin yüklenebilmesi için "Bilinmeyen uygulamaları yükle" iznini etkinleştirmeniz gerekmektedir. İzni verdikten sonra tekrar deneyin.',
                          'To install MultiPad updates, please allow "Install unknown apps" in Settings. Once granted, retry installation.',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              await NativeBridgeService.openAndroidAutofillSettings();
                            },
                            child: Text(
                              l10n.tr('Ayarları Aç', 'Open Settings'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _triggerInstall,
                            child: Text(
                              l10n.tr('Tekrar Dene', 'Retry'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        TextButton.icon(
          onPressed: () async {
            final uri = Uri.tryParse(widget.info.htmlUrl);
            if (uri != null) {
              try {
                final auth = context.read<AuthProvider?>();
                if (auth != null) {
                  await auth.runWithoutAutoLockUntilResumed(
                    () => launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                } else {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (_) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(l10n.tr('GitHub Sürüm Notları', 'GitHub Release')),
        ),
        if (asset != null)
          FilledButton.icon(
            onPressed: _downloading
                ? null
                : (_isReadyToInstall ? _triggerInstall : _startDownload),
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isReadyToInstall
                        ? (Platform.isAndroid
                            ? Icons.system_update_rounded
                            : Icons.restart_alt_rounded)
                        : Icons.download_rounded,
                  ),
            label: Text(
              _downloading
                  ? l10n.tr('İndiriliyor...', 'Downloading...')
                  : (_isReadyToInstall
                      ? (Platform.isAndroid
                          ? l10n.tr('Yükle', 'Install')
                          : l10n.tr('Yükle ve Yeniden Başlat',
                              'Install & Relaunch'))
                      : l10n.tr('İndir & Hazırla', 'Download & Prepare')),
            ),
          ),
      ],
    );
  }
}
