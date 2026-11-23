import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';

class PendingCaptureDialog extends StatefulWidget {
  final Map<String, dynamic> captured;
  final VaultItem? existingItem;
  final bool isBottomSheet;

  const PendingCaptureDialog({
    super.key,
    required this.captured,
    this.existingItem,
    this.isBottomSheet = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> captured,
    VaultItem? existingItem,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: PendingCaptureDialog(
            captured: captured,
            existingItem: existingItem,
            isBottomSheet: true,
          ),
        ),
      );
    } else {
      return showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: PendingCaptureDialog(
              captured: captured,
              existingItem: existingItem,
              isBottomSheet: false,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<PendingCaptureDialog> createState() => _PendingCaptureDialogState();
}

class _PendingCaptureDialogState extends State<PendingCaptureDialog> {
  late final TextEditingController _titleController;
  bool _revealPassword = false;
  bool _revealPreviousPassword = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final defaultTitle = widget.existingItem?.title ??
        (widget.captured['title'] as String?)?.trim() ??
        (widget.captured['website'] as String?)?.trim() ??
        'New Login';
    _titleController = TextEditingController(
      text: defaultTitle.isNotEmpty ? defaultTitle : 'New Login',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label, AppLocalizations l10n) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label ${l10n.copied.toLowerCase()}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleConfirm({required bool updateExisting}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final vault = context.read<VaultProvider>();
      await vault.processPendingAutofillCapture(
        captured: widget.captured,
        updateExisting: updateExisting,
        existingItem: widget.existingItem,
        customTitle: _titleController.text.trim(),
      );
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isUpdate = widget.existingItem != null;

    final capturedUsername = (widget.captured['username'] as String? ?? '').trim();
    final capturedPassword = (widget.captured['password'] as String? ?? '').trim();
    final capturedWebsite = (widget.captured['website'] as String? ?? '').trim();
    final capturedPackage = (widget.captured['packageName'] as String? ?? '').trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isBottomSheet) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
          // Header
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isUpdate ? Icons.published_with_changes_rounded : Icons.shield_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUpdate
                          ? l10n.tr('Mevcut Parolayı Güncelle', 'Update Existing Password')
                          : l10n.tr('Yeni Hesap Kaydet', 'Save New Login'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      capturedWebsite.isNotEmpty
                          ? capturedWebsite
                          : (capturedPackage.isNotEmpty ? capturedPackage : 'MultiPad'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Editable Title Field
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l10n.tr('Başlık', 'Title'),
              prefixIcon: const Icon(Icons.label_outline_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Service / Domain Chip
          if (capturedWebsite.isNotEmpty || capturedPackage.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (capturedWebsite.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.language_rounded, size: 16),
                    label: Text(capturedWebsite),
                    visualDensity: VisualDensity.compact,
                  ),
                if (capturedPackage.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.android_rounded, size: 16),
                    label: Text(capturedPackage),
                    visualDensity: VisualDensity.compact,
                  ),
                if (isUpdate)
                  Chip(
                    backgroundColor: theme.colorScheme.errorContainer.withOpacity(0.6),
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    label: Text(
                      l10n.tr('Parola Değişti', 'Password Changed'),
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Username Field
          if (capturedUsername.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('Kullanıcı Adı', 'Username'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          capturedUsername,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.copy,
                    onPressed: () => _copyToClipboard(
                      capturedUsername,
                      l10n.tr('Kullanıcı adı', 'Username'),
                      l10n,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Password Section
          if (isUpdate) ...[
            // Previous Password
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock_outlined,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('Önceki Parola', 'Previous Password'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _revealPreviousPassword
                              ? widget.existingItem!.password
                              : '••••••••',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: _revealPreviousPassword ? null : 'monospace',
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _revealPreviousPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _revealPreviousPassword = !_revealPreviousPassword;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // New Captured Password
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_reset_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('Yeni Parola', 'New Password'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _revealPassword ? capturedPassword : '••••••••',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: _revealPassword ? null : 'monospace',
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _revealPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _revealPassword = !_revealPassword;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.copy,
                    onPressed: () => _copyToClipboard(
                      capturedPassword,
                      l10n.tr('Parola', 'Password'),
                      l10n,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Single Password View
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('Parola', 'Password'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _revealPassword ? capturedPassword : '••••••••',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: _revealPassword ? null : 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _revealPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _revealPassword = !_revealPassword;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: l10n.copy,
                    onPressed: () => _copyToClipboard(
                      capturedPassword,
                      l10n.tr('Parola', 'Password'),
                      l10n,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Action Buttons
          if (isUpdate) ...[
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _handleConfirm(updateExisting: true),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(l10n.tr('Parolayı Güncelle', 'Update Password')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : () => _handleConfirm(updateExisting: false),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text(l10n.tr('Yeni Olarak Kaydet', 'Save as New Item')),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
              child: Text(
                l10n.tr('Yoksay', 'Ignore'),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _handleConfirm(updateExisting: false),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(l10n.tr('Kasaya Kaydet', 'Save to Vault')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
              child: Text(
                l10n.tr('Yoksay', 'Ignore'),
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
