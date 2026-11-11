import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/sync_conflict.dart';
import '../models/vault_item.dart';
import '../providers/vault_provider.dart';

class ConflictsScreen extends StatelessWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final vault = context.watch<VaultProvider>();
    final conflicts = vault.conflicts;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    Widget buildVersionCard(
      String label,
      Color accent,
      VaultItem item,
    ) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  fmt.format(item.clientUpdatedAt.toLocal()),
                  style: TextStyle(fontSize: 11, color: theme.hintColor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (item.username.isNotEmpty)
              Text(
                '${l10n.tr("Kullanıcı", "User")}: ${item.username}',
                style: const TextStyle(fontSize: 12),
              ),
            if (item.isDeleted)
              Text(
                l10n.tr('(Silinmiş sürüm)', '(Deleted)'),
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            if (item.content.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflictsTitle)),
      body: conflicts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr(
                      'Bekleyen senkronizasyon çakışması yok.',
                      'No pending sync conflicts.',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: conflicts.length,
                  itemBuilder: (ctx, idx) {
                    final conflict = conflicts[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.merge_type,
                                  color: Colors.orangeAccent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.tr(
                                      'İki cihazda aynı anda değişiklik yapıldı',
                                      'Concurrent edits detected',
                                    ),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            buildVersionCard(
                              l10n.tr('Bu Cihazdaki Sürüm', 'Local Version'),
                              Colors.indigoAccent,
                              conflict.localItem,
                            ),
                            const SizedBox(height: 10),
                            buildVersionCard(
                              l10n.tr('Buluttaki Sürüm', 'Cloud Version'),
                              Colors.teal,
                              conflict.remoteItem,
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => vault.resolveConflict(
                                    conflict,
                                    ConflictResolutionChoice.keepLocal,
                                  ),
                                  child: Text(
                                    l10n.tr('Bu Cihazdakini Tut', 'Keep Local'),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => vault.resolveConflict(
                                    conflict,
                                    ConflictResolutionChoice.keepRemote,
                                  ),
                                  child: Text(
                                    l10n.tr('Buluttakini Al', 'Keep Cloud'),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: () => vault.resolveConflict(
                                    conflict,
                                    ConflictResolutionChoice.keepBothAsCopy,
                                  ),
                                  icon: const Icon(Icons.copy_all, size: 18),
                                  label: Text(
                                    l10n.tr(
                                      'İkisini de Sakla (Kopya)',
                                      'Keep Both',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
