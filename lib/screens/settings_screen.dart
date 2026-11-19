import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';
import '../services/clipboard_service.dart';
import '../services/native_bridge_service.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../widgets/easter_egg_dialog.dart';
import 'backup_screen.dart';
import 'conflicts_screen.dart';
import 'device_pairing_screen.dart';
import 'import_screen.dart';
import 'security_logs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;
  bool _checkingUpdate = false;
  List<Factor>? _mfaFactors;
  bool _loadingMfa = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMfaFactors());
  }

  Future<void> _loadMfaFactors() async {
    if (!SupabaseService.isInitialized || SupabaseService.currentUser == null) {
      return;
    }
    setState(() => _loadingMfa = true);
    try {
      final factors = await context.read<AuthProvider>().listAllMfaFactors();
      if (!mounted) return;
      setState(() {
        _mfaFactors = factors;
        _loadingMfa = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMfa = false);
    }
  }

  void _handleVersionTap() {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      showDialog<void>(
        context: context,
        builder: (_) => const EasterEggDialog(),
      );
    }
  }

  Future<void> _showChoiceDialog<T>({
    required String title,
    required T currentValue,
    required List<({T value, String label, String? subtitle})> options,
    required Future<void> Function(T chosen) onSelected,
  }) async {
    final chosen = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: options
            .map(
              (o) {
                final selected = o.value == currentValue;
                return ListTile(
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? Theme.of(ctx).colorScheme.primary : null,
                  ),
                  title: Text(o.label),
                  subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                  onTap: () => Navigator.of(ctx).pop(o.value),
                );
              },
            )
            .toList(),
      ),
    );
    if (chosen != null) {
      await onSelected(chosen);
    }
  }

  Future<void> _openQuickPinDialog(AuthProvider auth) async {
    final l10n = context.l10n;
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? localErr;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            auth.isQuickPinEnabled
                ? l10n.tr('Hızlı PIN Değiştir', 'Change Quick PIN')
                : l10n.tr('Hızlı PIN Oluştur', 'Set Up Quick PIN'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tr(
                  '4–12 haneli sayısal PIN belirleyin. 3 hatalı denemede PIN sıfırlanır ve ana parola istenir.',
                  'Choose a 4–12 digit numeric PIN. After 3 failed attempts, PIN is cleared and Master Password is required.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: l10n.tr('Yeni PIN (4–12 rakam)', 'New PIN (4–12 digits)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: l10n.tr('PIN Tekrar', 'Confirm PIN'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (localErr != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    localErr!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            if (auth.isQuickPinEnabled)
              TextButton(
                onPressed: () async {
                  await auth.disableQuickPin();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.tr('Hızlı PIN devre dışı bırakıldı.', 'Quick PIN disabled.'),
                      ),
                    ),
                  );
                },
                child: Text(
                  l10n.tr('Kaldır', 'Disable'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                final conf = confirmCtrl.text.trim();
                if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
                  setDlg(() {
                    localErr = l10n.tr(
                      'PIN 4 ile 12 arasında yalnızca rakamlardan oluşmalıdır.',
                      'PIN must be 4–12 digits only.',
                    );
                  });
                  return;
                }
                if (pin != conf) {
                  setDlg(() {
                    localErr = l10n.tr('PIN değerleri eşleşmiyor.', 'PINs do not match.');
                  });
                  return;
                }
                final ok = await auth.enableQuickPin(pin);
                if (!ctx.mounted) return;
                if (ok) {
                  Navigator.of(ctx).pop(true);
                } else {
                  setDlg(() => localErr = auth.errorMessage);
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );

    pinCtrl.dispose();
    confirmCtrl.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('Hızlı PIN etkinleştirildi.', 'Quick PIN enabled.')),
        ),
      );
    }
  }

  Future<void> _openUpgradeArgon2idDialog(
    AuthProvider auth,
    VaultProvider vault,
  ) async {
    final l10n = context.l10n;
    final passCtrl = TextEditingController();
    String? err;
    bool running = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(l10n.tr("Argon2id'ye Yükselt", 'Upgrade to Argon2id')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tr(
                  'Kasanız Argon2id anahtar türetme ile yeniden şifrelenecek. Mevcut ana parolanızı doğrulayın.',
                  'Your vault will be re-encrypted using Argon2id key derivation. Enter your current master password.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                enabled: !running,
                decoration: InputDecoration(
                  labelText: l10n.tr('Mevcut Ana Parola', 'Current Master Password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(
                  err!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: running ? null : () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: running
                  ? null
                  : () async {
                      setDlg(() {
                        running = true;
                        err = null;
                      });
                      final success = await auth.upgradeToArgon2id(
                        currentPassword: passCtrl.text,
                        onReEncryptVault: vault.reEncryptAllWithNewKey,
                      );
                      if (!ctx.mounted) return;
                      if (success) {
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDlg(() {
                          running = false;
                          err = auth.errorMessage ?? l10n.tr('İşlem başarısız.', 'Failed.');
                        });
                      }
                    },
              child: running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.tr('Yükselt', 'Upgrade')),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              'Argon2id geçişi ve kasa yeniden şifreleme tamamlandı.',
              'Upgraded to Argon2id and re-encrypted vault.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openChangeMasterPasswordDialog(
    AuthProvider auth,
    VaultProvider vault,
  ) async {
    final l10n = context.l10n;
    final currCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    bool useArgon = auth.isArgon2idActive || auth.preferArgon2id;
    bool running = false;
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(l10n.tr('Ana Parolayı Değiştir', 'Change Master Password')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currCtrl,
                    obscureText: true,
                    enabled: !running,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Mevcut Ana Parola', 'Current Master Password'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newCtrl,
                    obscureText: true,
                    enabled: !running,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Yeni Ana Parola (en az 8 karakter)', 'New Master Password (min 8 chars)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confCtrl,
                    obscureText: true,
                    enabled: !running,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Yeni Ana Parola Tekrar', 'Confirm New Master Password'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.tr('Argon2id Kullan', 'Use Argon2id')),
                    value: useArgon,
                    onChanged: running ? null : (v) => setDlg(() => useArgon = v),
                  ),
                  if (err != null)
                    Text(
                      err!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: running ? null : () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: running
                  ? null
                  : () async {
                      if (newCtrl.text != confCtrl.text) {
                        setDlg(() {
                          err = l10n.tr('Yeni parolalar eşleşmiyor.', 'New passwords do not match.');
                        });
                        return;
                      }
                      setDlg(() {
                        running = true;
                        err = null;
                      });
                      final success = await auth.changeMasterPassword(
                        currentPassword: currCtrl.text,
                        newPassword: newCtrl.text,
                        onReEncryptVault: vault.reEncryptAllWithNewKey,
                        forceArgon2id: useArgon,
                      );
                      if (!ctx.mounted) return;
                      if (success) {
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDlg(() {
                          running = false;
                          err = auth.errorMessage ?? l10n.tr('Değiştirilemedi.', 'Update failed.');
                        });
                      }
                    },
              child: running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    currCtrl.dispose();
    newCtrl.dispose();
    confCtrl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              'Ana parola değiştirildi ve kasa yeniden şifrelendi.',
              'Master password changed and vault re-encrypted.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDuressDialog(AuthProvider auth) async {
    final l10n = context.l10n;
    final passCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    String? err;
    bool running = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            l10n.tr('Sahte / Panik Parolası (Duress)', 'Duress / Panic Password'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tr(
                  'Kilit ekranında bu parola girildiğinde gerçek verileriniz gizlenir ve yalnızca zararsız örnek notlar içeren sahte bir kasa açılır.',
                  'Entering this password on the lock screen hides your real vault and opens a decoy vault with harmless sample notes.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('Panik Parolası (min 6 karakter)', 'Duress Password (min 6 chars)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.tr('Parola Tekrar', 'Confirm Password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(
                  err!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            if (auth.isDuressEnabled)
              TextButton(
                onPressed: running
                    ? null
                    : () async {
                        await auth.disableDuressPassword();
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop(false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.tr('Panik parolası kaldırıldı.', 'Duress password disabled.'),
                            ),
                          ),
                        );
                      },
                child: Text(
                  l10n.tr('Kaldır', 'Disable'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton(
              onPressed: running ? null : () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: running
                  ? null
                  : () async {
                      if (passCtrl.text != confCtrl.text) {
                        setDlg(() => err = l10n.tr('Parolalar eşleşmiyor.', 'Passwords do not match.'));
                        return;
                      }
                      setDlg(() {
                        running = true;
                        err = null;
                      });
                      final ok = await auth.configureDuressPassword(passCtrl.text);
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDlg(() {
                          running = false;
                          err = auth.errorMessage;
                        });
                      }
                    },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();
    confCtrl.dispose();

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr('Sahte/Panik parolası ayarlandı.', 'Duress password configured.'),
          ),
        ),
      );
    }
  }

  Future<void> _openMfaDialog(AuthProvider auth) async {
    final l10n = context.l10n;
    await _loadMfaFactors();
    if (!mounted) return;

    final verifiedFactors = (_mfaFactors ?? const <Factor>[])
        .where((f) => f.status == FactorStatus.verified)
        .toList();

    if (verifiedFactors.isNotEmpty) {
      final confirmDisable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.mfaTitle),
          content: Text(
            l10n.tr(
              'Hesabınızda aktif TOTP iki adımlı doğrulama (${verifiedFactors.first.friendlyName ?? 'Authenticator'}) bulunuyor. Kaldırmak istiyor musunuz?',
              'Your account has active TOTP 2FA (${verifiedFactors.first.friendlyName ?? 'Authenticator'}). Remove it?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.close),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.tr('2FA Devre Dışı Bırak', 'Disable 2FA')),
            ),
          ],
        ),
      );
      if (confirmDisable == true) {
        final ok = await auth.disableMfa(verifiedFactors.first.id);
        await _loadMfaFactors();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? l10n.tr('Hesap 2FA kaldırıldı.', 'Account 2FA disabled.')
                  : (auth.errorMessage ?? 'Error'),
            ),
          ),
        );
      }
      return;
    }

    try {
      final enroll = await auth.startTotpMfaEnrollment();
      final uri = enroll.totp?.uri ?? '';
      final secret = enroll.totp?.secret ?? '';
      if (!mounted) return;

      final codeCtrl = TextEditingController();
      String? err;
      bool verifying = false;

      final enrolled = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: Text(l10n.tr('2FA Authenticator Kurulumu', 'Set Up 2FA Authenticator')),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.tr(
                        'Bu QR kodu doğrulama uygulamanızla (Google Authenticator, Ente Auth, vb.) tarayın ve 6 haneli kodu girin.',
                        'Scan this QR code with your authenticator app and enter the 6-digit code.',
                      ),
                      style: Theme.of(ctx).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (uri.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: uri,
                          version: QrVersions.auto,
                          size: 180,
                        ),
                      ),
                    if (secret.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        secret,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => ClipboardService.copySecurely(
                          secret,
                          timeoutSeconds: 60,
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(l10n.tr('Gizli Anahtarı Kopyala', 'Copy Secret Key')),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: l10n.tr('6 Haneli Doğrulama Kodu', '6-Digit Code'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (err != null)
                      Text(
                        err!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: verifying ? null : () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: verifying
                    ? null
                    : () async {
                        setDlg(() {
                          verifying = true;
                          err = null;
                        });
                        final ok = await auth.confirmTotpMfaEnrollment(
                          factorId: enroll.id,
                          code: codeCtrl.text,
                        );
                        if (!ctx.mounted) return;
                        if (ok) {
                          Navigator.of(ctx).pop(true);
                        } else {
                          setDlg(() {
                            verifying = false;
                            err = auth.errorMessage ?? l10n.tr('Kod hatalı.', 'Invalid code.');
                          });
                        }
                      },
                child: verifying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.confirm),
              ),
            ],
          ),
        ),
      );
      codeCtrl.dispose();
      await _loadMfaFactors();
      if (enrolled == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.tr('Hesap seviyesi 2FA etkinleştirildi.', 'Account 2FA enabled.')),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _openCloudConnectDialog(AuthProvider auth, VaultProvider vault) async {
    final l10n = context.l10n;
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: auth.currentUserEmail ?? '');
    String? err;
    bool busy = false;

    final connected = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(l10n.tr('Supabase Bulut Bağlantısı', 'Supabase Cloud Sync')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Supabase Project URL',
                      hintText: 'https://xxxx.supabase.co',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Supabase Anon Key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Hesap E-postası (İsteğe Bağlı)', 'Account Email (Optional)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      err!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDlg(() {
                        busy = true;
                        err = null;
                      });
                      final ok = await auth.connectCloudWhileUnlocked(
                        url: urlCtrl.text.trim(),
                        anonKey: keyCtrl.text.trim(),
                        accountEmail: emailCtrl.text.trim().isEmpty
                            ? null
                            : emailCtrl.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      if (ok) {
                        await vault.loadVault();
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDlg(() {
                          busy = false;
                          err = auth.errorMessage;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.tr('Bağlan ve Eşitle', 'Connect & Sync')),
            ),
          ],
        ),
      ),
    );
    urlCtrl.dispose();
    keyCtrl.dispose();
    emailCtrl.dispose();

    if (connected == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('Bulut senkronizasyonu bağlandı.', 'Cloud sync connected.')),
        ),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    final l10n = context.l10n;
    setState(() => _checkingUpdate = true);
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    if (info == null) {
      final errorMsg = UpdateService.lastErrorMessage ??
          l10n.tr(
            'Güncelleme sunucusuna ulaşılamadı.',
            'Could not reach update server.',
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!info.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tr(
              'Uygulama güncel (${info.currentVersion}).',
              'MultiPad is up to date (${info.currentVersion}).',
            ),
          ),
        ),
      );
      return;
    }

    final asset = info.platformAsset;
    double progress = 0;
    String? statusMsg;
    bool downloading = false;
    String? err;

    await showDialog<void>(
      context: context,
      barrierDismissible: !downloading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            l10n.tr(
              'Yeni Sürüm Mevcut: ${info.latestVersion}',
              'Update Available: ${info.latestVersion}',
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tr(
                      'Mevcut sürüm: ${info.currentVersion}',
                      'Current version: ${info.currentVersion}',
                    ),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (asset != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          asset.expectedSha256 != null
                              ? Icons.verified_user
                              : Icons.info_outline,
                          size: 16,
                          color: asset.expectedSha256 != null
                              ? Colors.green
                              : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            asset.expectedSha256 != null
                                ? l10n.tr(
                                    '${asset.name} • SHA-256 doğrulama mevcut',
                                    '${asset.name} • SHA-256 verification available',
                                  )
                                : asset.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (info.releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          info.releaseNotes,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  if (downloading || statusMsg != null) ...[
                    const SizedBox(height: 14),
                    if (downloading)
                      LinearProgressIndicator(value: progress > 0 ? progress : null),
                    if (downloading) const SizedBox(height: 6),
                    Text(
                      statusMsg ?? '${(progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: !downloading && progress >= 1.0 ? Colors.green : null,
                        fontWeight: !downloading && progress >= 1.0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      err!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: downloading ? null : () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(info.htmlUrl);
                if (uri != null) {
                  final auth = context.read<AuthProvider>();
                  await auth.runWithoutAutoLockUntilResumed(
                    () => launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                }
              },
              child: Text(l10n.tr('GitHub Sayfası', 'GitHub Release')),
            ),
            if (asset != null)
              FilledButton.icon(
                onPressed: downloading
                    ? null
                    : () async {
                        setDlg(() {
                          downloading = true;
                          progress = 0;
                          err = null;
                        });
                        try {
                          final auth = context.read<AuthProvider>();
                          final resultMsg = await auth.runWithoutAutoLockUntilResumed(
                            () => UpdateService.downloadAndInstall(
                              asset,
                              onProgress: (p) {
                                if (ctx.mounted) setDlg(() => progress = p);
                              },
                              onStatus: (s) {
                                if (ctx.mounted) setDlg(() => statusMsg = s);
                              },
                            ),
                          );
                          if (!ctx.mounted) return;
                          setDlg(() {
                            downloading = false;
                            statusMsg = resultMsg;
                            progress = 1.0;
                          });
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDlg(() {
                            downloading = false;
                            err = e.toString();
                          });
                        }
                      },
                icon: const Icon(Icons.system_update_alt),
                label: Text(l10n.tr('İndir & Yükle', 'Download & Install')),
              ),
          ],
        ),
      ),
    );
  }

  String _autoLockLabel(AppLocalizations l10n, int minutes) {
    if (minutes <= 0) return l10n.tr('Kapalı', 'Off');
    return l10n.tr('$minutes dakika', '$minutes minute(s)');
  }

  String _clipboardLabel(AppLocalizations l10n, int seconds) {
    if (seconds <= 0) return l10n.tr('Temizleme Kapalı', 'Auto-clear Off');
    return l10n.tr('$seconds saniye', '$seconds seconds');
  }

  String _themeLabel(AppLocalizations l10n, AppThemePreference pref) {
    switch (pref) {
      case AppThemePreference.system:
        return l10n.tr('Sistem Varsayılanı', 'System Default');
      case AppThemePreference.light:
        return l10n.tr('Açık Tema', 'Light');
      case AppThemePreference.dark:
        return l10n.tr('Koyu Tema', 'Dark');
      case AppThemePreference.amoled:
        return l10n.tr('AMOLED Saf Siyah', 'AMOLED Pure Black');
    }
  }

  String _localeLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'tr':
        return 'Türkçe';
      case 'en':
        return 'English';
      default:
        return l10n.tr('Sistem Dili', 'System Language');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final vault = context.watch<VaultProvider>();
    final settings = context.watch<SettingsProvider>();

    final verifiedMfaCount = (_mfaFactors ?? const <Factor>[])
        .where((f) => f.status == FactorStatus.verified)
        .length;

    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final isMacOS = !kIsWeb && Platform.isMacOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final isCloudConnected =
        SupabaseService.isInitialized && SupabaseService.currentUser != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _SectionHeader(l10n.secSecurity),

          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.tr('Otomatik Kilit Süresi', 'Auto-Lock Timeout')),
            subtitle: Text(_autoLockLabel(l10n, settings.autoLockMinutes)),
            onTap: () => _showChoiceDialog<int>(
              title: l10n.tr('Hareketsizlik Sonrası Kilitle', 'Lock After Inactivity'),
              currentValue: settings.autoLockMinutes,
              options: [
                (value: 1, label: l10n.tr('1 dakika', '1 minute'), subtitle: null),
                (value: 5, label: l10n.tr('5 dakika', '5 minutes'), subtitle: null),
                (value: 15, label: l10n.tr('15 dakika', '15 minutes'), subtitle: null),
                (value: 0, label: l10n.tr('Kapalı', 'Off'), subtitle: null),
              ],
              onSelected: settings.setAutoLockMinutes,
            ),
          ),

          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(
              isMacOS
                  ? l10n.tr(
                      'Pencere Küçültüldüğünde / Gizlendiğinde Kilitle',
                      'Lock when Window Minimized or Hidden',
                    )
                  : l10n.tr('Arka Plana Alınca Kilitle', 'Lock on Background'),
            ),
            subtitle: Text(
              isMacOS
                  ? l10n.tr(
                      'Pencere simge durumuna küçültüldüğünde veya gizlendiğinde kasayı anında kilitle',
                      'Immediately lock the vault when minimized or moved to background',
                    )
                  : l10n.tr(
                      'Uygulama simge durumuna küçültülünce kasayı kilitle',
                      'Lock vault when app leaves foreground',
                    ),
            ),
            value: settings.lockOnBackground,
            onChanged: settings.setLockOnBackground,
          ),

          if (isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.screenshot_monitor_outlined),
              title: Text(
                l10n.tr('Ekran Görüntüsü Koruması (FLAG_SECURE)', 'Screen Capture Protection (FLAG_SECURE)'),
              ),
              subtitle: Text(
                l10n.tr(
                  'Son uygulamalar önizlemesini ve ekran görüntüsünü engeller',
                  'Blocks screenshots and Android Recents preview',
                ),
              ),
              value: settings.flagSecureEnabled,
              onChanged: settings.setFlagSecureEnabled,
            ),

          ListTile(
            leading: const Icon(Icons.content_paste_off_outlined),
            title: Text(l10n.tr('Pano Otomatik Temizleme', 'Clipboard Auto-Clear')),
            subtitle: Text(_clipboardLabel(l10n, settings.clipboardTimeoutSeconds)),
            onTap: () => _showChoiceDialog<int>(
              title: l10n.tr('Pano Temizleme Süresi', 'Clipboard Clear Timeout'),
              currentValue: settings.clipboardTimeoutSeconds,
              options: [
                (value: 10, label: l10n.tr('10 saniye', '10 seconds'), subtitle: null),
                (value: 30, label: l10n.tr('30 saniye', '30 seconds'), subtitle: null),
                (value: 60, label: l10n.tr('1 dakika', '1 minute'), subtitle: null),
                (value: 0, label: l10n.tr('Kapalı', 'Off'), subtitle: null),
              ],
              onSelected: settings.setClipboardTimeoutSeconds,
            ),
          ),

          if (auth.canUseBiometrics)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: Text(l10n.tr('Biyometrik Kilit Açma', 'Biometric Unlock')),
              subtitle: auth.isBiometricTemporarilyDisabled
                  ? Text(
                      l10n.tr(
                        'Üst üste hatalı deneme nedeniyle geçici devre dışı',
                        'Temporarily disabled due to failed attempts',
                      ),
                      style: const TextStyle(color: Colors.orangeAccent),
                    )
                  : null,
              value: auth.isBiometricEnabled,
              onChanged: (v) async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await auth.toggleBiometrics(v);
                if (!ok && mounted && auth.errorMessage != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(auth.errorMessage!)),
                  );
                }
              },
            ),

          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(l10n.quickPin),
            subtitle: Text(
              auth.isQuickPinEnabled
                  ? l10n.tr('Aktif (Değiştirmek için dokunun)', 'Enabled (Tap to manage)')
                  : l10n.tr('Hızlı kilitleme için ikincil PIN ayarlayın', 'Set secondary PIN for fast unlock'),
            ),
            onTap: () => _openQuickPinDialog(auth),
          ),

          if (!auth.isDuressMode) ...[
            ListTile(
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: Text(l10n.tr('Anahtar Türetme (KDF)', 'Key Derivation (KDF)')),
              subtitle: Text(
                auth.isArgon2idActive
                    ? 'Argon2id (Bellek-sert / Aktif)'
                    : 'PBKDF2-HMAC-SHA256 (Argon2id yükseltmesi mevcut)',
              ),
              trailing: auth.isArgon2idActive
                  ? const Icon(Icons.verified, color: Colors.green)
                  : TextButton(
                      onPressed: () => _openUpgradeArgon2idDialog(auth, vault),
                      child: Text(l10n.tr("Argon2id'ye Geç", 'Upgrade')),
                    ),
              onTap: auth.isArgon2idActive
                  ? null
                  : () => _openUpgradeArgon2idDialog(auth, vault),
            ),

            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.tr('Ana Parolayı Değiştir', 'Change Master Password')),
              subtitle: Text(
                l10n.tr(
                  'Tüm kasayı yeni anahtarla yeniden şifreler',
                  'Re-encrypts entire vault with a new key',
                ),
              ),
              onTap: () => _openChangeMasterPasswordDialog(auth, vault),
            ),

            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(
                l10n.tr('Sahte / Panik Parolası (Duress)', 'Duress / Panic Password'),
              ),
              subtitle: Text(
                auth.isDuressEnabled
                    ? l10n.tr('Aktif (Panik kasası hazır)', 'Enabled (Decoy vault ready)')
                    : l10n.tr('Acil durumlar için ikinci zararsız kasa şifresi', 'Secondary password for decoy vault'),
              ),
              onTap: () => _openDuressDialog(auth),
            ),
          ],

          ListTile(
            leading: const Icon(Icons.av_timer_outlined),
            title: Text(l10n.tr('2FA Yeniden İsteme Sıklığı', '2FA Re-Prompt Interval')),
            subtitle: Text(
              l10n.tr(
                '${settings.twoFactorRepromptDays} gün',
                '${settings.twoFactorRepromptDays} days',
              ),
            ),
            onTap: () => _showChoiceDialog<int>(
              title: l10n.tr('2FA Sıklığı Seçin', 'Select 2FA Interval'),
              currentValue: settings.twoFactorRepromptDays,
              options: [
                (value: 30, label: l10n.tr('30 gün', '30 days'), subtitle: null),
                (value: 60, label: l10n.tr('60 gün', '60 days'), subtitle: null),
                (value: 90, label: l10n.tr('90 gün', '90 days'), subtitle: null),
              ],
              onSelected: settings.setTwoFactorRepromptDays,
            ),
          ),

          if (isCloudConnected) ...[
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(l10n.tr('Hesap Seviyesi 2FA (TOTP)', 'Account-Level 2FA (TOTP)')),
              subtitle: _loadingMfa
                  ? Text(l10n.tr('Kontrol ediliyor...', 'Checking...'))
                  : Text(
                      verifiedMfaCount > 0
                          ? l10n.tr('Etkin ($verifiedMfaCount doğrulayıcı)', 'Enabled ($verifiedMfaCount factor)')
                          : l10n.tr('Kapalı — giriş için önerilir', 'Disabled — recommended'),
                    ),
              trailing: Icon(
                verifiedMfaCount > 0 ? Icons.check_circle : Icons.chevron_right,
                color: verifiedMfaCount > 0 ? Colors.green : null,
              ),
              onTap: () => _openMfaDialog(auth),
            ),
            ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: Text(
                l10n.tr('Diğer Tüm Cihazlardan Çıkış Yap', 'Sign Out All Other Devices'),
              ),
              subtitle: Text(
                l10n.tr(
                  'Bu cihaz hariç aktif Supabase oturumlarını iptal eder',
                  'Revokes all other cloud sessions except this device',
                ),
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await auth.signOutOtherDevices();
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? l10n.tr('Diğer cihaz oturumları kapatıldı.', 'Signed out other devices.')
                          : (auth.errorMessage ?? 'Error'),
                    ),
                  ),
                );
              },
            ),
          ],

          ListTile(
            leading: const Icon(Icons.update_disabled_outlined),
            title: Text(l10n.tr('Parola Eskime Uyarısı', 'Password Age Warning')),
            subtitle: Text(
              settings.globalExpiryDays <= 0
                  ? l10n.tr('Kapalı', 'Off')
                  : l10n.tr('${settings.globalExpiryDays} gün', '${settings.globalExpiryDays} days'),
            ),
            onTap: () => _showChoiceDialog<int>(
              title: l10n.tr('Parola Yenileme Hatırlatma Süresi', 'Password Expiry Warning'),
              currentValue: settings.globalExpiryDays,
              options: [
                (value: 90, label: l10n.tr('90 gün', '90 days'), subtitle: null),
                (value: 180, label: l10n.tr('180 gün', '180 days'), subtitle: null),
                (value: 365, label: l10n.tr('365 gün', '365 days'), subtitle: null),
                (value: 0, label: l10n.tr('Kapalı', 'Off'), subtitle: null),
              ],
              onSelected: (days) async {
                await settings.setGlobalExpiryDays(days);
                await auth.setGlobalPasswordExpiryDays(days);
              },
            ),
          ),

          ListTile(
            leading: const Icon(Icons.history_edu_outlined),
            title: Text(l10n.securityLogs),
            subtitle: Text(
              l10n.tr(
                'Başarısız giriş ve güvenlik olaylarının şifreli kaydı',
                'Encrypted log of failed attempts & security events',
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityLogsScreen()),
            ),
          ),

          const Divider(),
          _SectionHeader(l10n.secAppearance),

          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.tr('Tema Modu', 'Theme Mode')),
            subtitle: Text(_themeLabel(l10n, settings.themePreference)),
            onTap: () => _showChoiceDialog<AppThemePreference>(
              title: l10n.tr('Tema Seçin', 'Select Theme'),
              currentValue: settings.themePreference,
              options: [
                (value: AppThemePreference.system, label: l10n.tr('Sistem Varsayılanı', 'System Default'), subtitle: null),
                (value: AppThemePreference.light, label: l10n.tr('Açık Tema', 'Light'), subtitle: null),
                (value: AppThemePreference.dark, label: l10n.tr('Koyu Tema', 'Dark'), subtitle: null),
                (value: AppThemePreference.amoled, label: l10n.tr('AMOLED Saf Siyah', 'AMOLED Pure Black'), subtitle: l10n.tr('OLED ekranlar için #000000 arka plan', 'Pure #000000 background for OLED')),
              ],
              onSelected: settings.setThemePreference,
            ),
          ),

          ListTile(
            leading: const Icon(Icons.format_size_outlined),
            title: Text(l10n.tr('Yazı Boyutu', 'Font Size')),
            subtitle: Slider(
              value: settings.fontScale,
              min: 0.85,
              max: 1.30,
              divisions: 9,
              label: '${(settings.fontScale * 100).round()}%',
              onChanged: (v) => settings.setFontScale(v),
            ),
            trailing: Text('${(settings.fontScale * 100).round()}%'),
          ),

          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l10n.tr('Uygulama Dili', 'App Language')),
            subtitle: Text(_localeLabel(l10n, settings.localeCode)),
            onTap: () => _showChoiceDialog<String>(
              title: l10n.tr('Dil Seçin', 'Select Language'),
              currentValue: settings.localeCode,
              options: [
                (value: 'system', label: l10n.tr('Sistem Dili', 'System Language'), subtitle: null),
                (value: 'tr', label: 'Türkçe', subtitle: null),
                (value: 'en', label: 'English', subtitle: null),
              ],
              onSelected: settings.setLocaleCode,
            ),
          ),

          if (isDesktop || isAndroid) ...[
            const Divider(),
            _SectionHeader(l10n.secPlatform),
          ],

          if (isDesktop) ...[
            SwitchListTile(
              secondary: const Icon(Icons.dock_outlined),
              title: Text(
                Platform.isMacOS
                    ? l10n.tr('Menü Çubuğunda Çalıştır', 'Keep in Menu Bar')
                    : l10n.tr('Sistem Tepsisinde Çalıştır', 'Minimize to System Tray'),
              ),
              subtitle: Text(
                l10n.tr(
                  'Pencere kapatıldığında arka planda açık kalır',
                  'Keeps app running in tray when window is closed',
                ),
              ),
              value: settings.trayEnabled,
              onChanged: settings.setTrayEnabled,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.keyboard_command_key_rounded),
              title: Text(
                l10n.tr('Global Hızlı Arama Kısayolu', 'Global Quick Search Hotkey'),
              ),
              subtitle: Text(
                Platform.isMacOS ? 'Cmd + Shift + Space' : 'Ctrl + Shift + Space',
              ),
              value: settings.globalHotkeyEnabled,
              onChanged: settings.setGlobalHotkeyEnabled,
            ),
          ],

          if (isAndroid) ...[
            SwitchListTile(
              secondary: const Icon(Icons.auto_fix_high_outlined),
              title: Text(l10n.tr('Android Otomatik Doldurma İndeksi', 'Android Autofill Service Index')),
              subtitle: Text(
                l10n.tr(
                  'Chrome ve diğer uygulamalarda parola/TOTP önerisi için şifreli önbellek tutar',
                  'Keeps Keystore-encrypted cache for Chrome & app autofill',
                ),
              ),
              value: settings.autofillEnabled,
              onChanged: (v) async {
                await settings.setAutofillEnabled(v);
                await vault.syncAutofillIndex(v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(
                l10n.tr('Android Otomatik Doldurma Servisini Seç', 'Open Android Autofill Settings'),
              ),
              subtitle: Text(
                l10n.tr(
                  'Sistem ayarlarında MultiPad\'i varsayılan sağlayıcı yapın',
                  'Set MultiPad as your system autofill service',
                ),
              ),
              onTap: () {
                final auth = context.read<AuthProvider>();
                auth.runWithoutAutoLockUntilResumed(
                  NativeBridgeService.openAndroidAutofillSettings,
                );
              },
            ),
          ],

          const Divider(),
          _SectionHeader(l10n.secData),

          if (vault.hasConflicts)
            ListTile(
              leading: const Icon(Icons.merge_type, color: Colors.orangeAccent),
              title: Text('${l10n.conflictsTitle} (${vault.conflicts.length})'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConflictsScreen()),
              ),
            ),

          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(l10n.importPasswords),
            subtitle: Text(
              l10n.tr(
                'Chrome, Edge, Bitwarden veya KeePass içe aktarımı',
                'Import from Chrome, Edge, Bitwarden or KeePass',
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.backup),
            subtitle: Text(
              l10n.tr(
                'Argon2id + AES-GCM şifreli taşınabilir yedek dosyası',
                'Argon2id + AES-GCM encrypted portable backup',
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(l10n.devicePairing),
            subtitle: Text(
              l10n.tr(
                'Aynı ağda veya aktarım koduyla başka cihaza kurulum gönder',
                'Transfer vault credentials to another device via LAN or code',
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const DevicePairingScreen(initialRole: PairingRole.send),
              ),
            ),
          ),

          if (!auth.isDuressMode)
            ListTile(
              leading: Icon(
                isCloudConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: isCloudConnected ? Colors.green : null,
              ),
              title: Text(l10n.tr('Bulut Senkronizasyonu (Supabase)', 'Cloud Sync (Supabase)')),
              subtitle: Text(
                isCloudConnected
                    ? (auth.currentUserEmail ?? SupabaseService.currentUser?.email ?? 'Connected')
                    : l10n.tr('Bağlı değil — bağlamak için dokunun', 'Not connected — tap to connect'),
              ),
              onTap: () => isCloudConnected
                  ? vault.loadVault()
                  : _openCloudConnectDialog(auth, vault),
            ),

          ListTile(
            leading: _checkingUpdate
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_outlined),
            title: Text(l10n.tr('Güncellemeleri Denetle', 'Check for Updates')),
            subtitle: Text('MultiPad v${AppConstants.appVersion}'),
            onTap: _checkingUpdate ? null : _checkForUpdates,
          ),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.tr('Sürüm Bilgisi', 'Version')),
            subtitle: Text(
              'v${AppConstants.appVersion} (Build ${AppConstants.buildNumber})',
            ),
            onTap: _handleVersionTap,
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.lockVault),
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              auth.lockVault(reason: 'settings_lock');
            },
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              l10n.logout,
              style: const TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              final navigator = Navigator.of(context);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(l10n.logout),
                  content: Text(
                    l10n.tr(
                      'Bu cihazdaki oturum kapatılacak ve önbellek temizlenecek. Devam edilsin mi?',
                      'Sign out and clear active session on this device?',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(l10n.logout),
                    ),
                  ],
                ),
              );
              if (ok == true && mounted) {
                navigator.popUntil((r) => r.isFirst);
                await auth.logout();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0.9,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
