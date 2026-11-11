import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/security_log_service.dart';

class SecurityLogsScreen extends StatefulWidget {
  const SecurityLogsScreen({super.key});

  @override
  State<SecurityLogsScreen> createState() => _SecurityLogsScreenState();
}

class _SecurityLogsScreenState extends State<SecurityLogsScreen> {
  final SecurityLogService _service = SecurityLogService();
  List<SecurityLogEntry> _logs = [];
  bool _loading = true;
  bool _warningsOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.loadLogs();
    if (mounted) {
      setState(() {
        _logs = list;
        _loading = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Güvenlik Günlüğünü Temizle'),
        content: const Text('Tüm şifreli yerel güvenlik kayıtları silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.clearLogs();
      await _load();
    }
  }

  IconData _iconFor(SecurityEventType t) {
    switch (t) {
      case SecurityEventType.unlockSuccess:
      case SecurityEventType.pinUnlockSuccess:
      case SecurityEventType.biometricSuccess:
        return Icons.lock_open;
      case SecurityEventType.unlockFailed:
      case SecurityEventType.pinUnlockFailed:
      case SecurityEventType.lockoutTriggered:
      case SecurityEventType.biometricDisabledByFailures:
        return Icons.gpp_bad;
      case SecurityEventType.duressUnlocked:
        return Icons.warning_amber;
      case SecurityEventType.vaultLocked:
        return Icons.lock_outline;
      case SecurityEventType.masterPasswordChanged:
      case SecurityEventType.kdfUpgradedToArgon2id:
      case SecurityEventType.mfaChanged:
      case SecurityEventType.otherSessionsSignedOut:
        return Icons.admin_panel_settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final fmt = DateFormat('dd.MM.yyyy HH:mm:ss');
    final visible =
        _warningsOnly ? _logs.where((e) => e.isWarning).toList() : _logs;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.securityLogs),
        actions: [
          FilterChip(
            label: Text(l10n.tr('Uyarılar', 'Warnings')),
            selected: _warningsOnly,
            onSelected: (v) => setState(() => _warningsOnly = v),
          ),
          const SizedBox(width: 8),
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Temizle',
              onPressed: _clearLogs,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
              ? Center(
                  child: Text(
                    l10n.tr(
                      'Henüz güvenlik olayı kaydedilmemiş.',
                      'No security events recorded yet.',
                    ),
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final entry = visible[i];
                        final color = entry.isWarning
                            ? Colors.orangeAccent
                            : Colors.indigoAccent;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.14),
                              child: Icon(_iconFor(entry.type), color: color),
                            ),
                            title: Text(entry.detail),
                            subtitle: Text(
                              fmt.format(entry.timestamp.toLocal()),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                              ),
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
