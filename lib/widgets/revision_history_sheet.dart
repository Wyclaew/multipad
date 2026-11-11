import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/vault_item.dart';

class RevisionHistorySheet extends StatefulWidget {
  final VaultItem item;
  final ValueChanged<VaultItemRevision> onRestore;

  const RevisionHistorySheet({
    super.key,
    required this.item,
    required this.onRestore,
  });

  static Future<void> show(
    BuildContext context, {
    required VaultItem item,
    required ValueChanged<VaultItemRevision> onRestore,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RevisionHistorySheet(item: item, onRestore: onRestore),
    );
  }

  @override
  State<RevisionHistorySheet> createState() => _RevisionHistorySheetState();
}

class _RevisionHistorySheetState extends State<RevisionHistorySheet> {
  final Set<String> _revealedPasswords = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final revisions = widget.item.revisions;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.indigoAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tr(
                      'Sürüm Geçmişi (${revisions.length})',
                      'Version History (${revisions.length})',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            if (revisions.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    l10n.tr(
                      'Bu öğe henüz değiştirilmemiş; değişiklik yapıldığında önceki sürümler burada saklanır.',
                      'No previous revisions yet. Edits are automatically snapshotted here.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: revisions.length,
                  itemBuilder: (ctx, index) {
                    final rev = revisions[index];
                    final revealPass = _revealedPasswords.contains(rev.id);
                    final titleChanged = rev.title != widget.item.title;
                    final contentChanged = rev.content != widget.item.content;
                    final passChanged =
                        rev.password.isNotEmpty &&
                        rev.password != widget.item.password;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fmt.format(rev.savedAt.toLocal()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (rev.summary.isNotEmpty)
                                  Chip(
                                    label: Text(
                                      rev.summary,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${l10n.tr("Başlık", "Title")}: ${rev.title}'
                              '${titleChanged ? " (${l10n.tr("değişti", "changed")})" : ""}',
                              style: TextStyle(
                                fontSize: 12,
                                color: titleChanged ? Colors.amber : null,
                              ),
                            ),
                            if (rev.password.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${l10n.tr("Parola", "Password")}: ${revealPass ? rev.password : "••••••••"}',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: passChanged ? Colors.amber : null,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      revealPass
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (revealPass) {
                                          _revealedPasswords.remove(rev.id);
                                        } else {
                                          _revealedPasswords.add(rev.id);
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                            if (rev.content.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  rev.content,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: contentChanged
                                        ? theme.colorScheme.onSurface
                                        : theme.hintColor,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onRestore(rev);
                                },
                                icon: const Icon(Icons.restore, size: 16),
                                label: Text(
                                  l10n.tr(
                                    'Bu Sürüme Geri Dön',
                                    'Restore This Version',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
