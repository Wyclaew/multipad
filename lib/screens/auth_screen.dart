import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'device_pairing_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  final _mfaCodeController = TextEditingController();

  bool _isRegistering = false;
  bool _usePinMode = true;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isConfiguringSupabase = false;
  bool _preferArgon2idOnRegister = true;
  Timer? _lockoutTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.currentUserEmail != null && auth.currentUserEmail!.isNotEmpty) {
        _emailController.text = auth.currentUserEmail!;
      }
      _preferArgon2idOnRegister = auth.preferArgon2id;
      _usePinMode = auth.isQuickPinEnabled;
      _syncLockoutTicker(auth);
    });
  }

  void _syncLockoutTicker(AuthProvider auth) {
    if (auth.remainingLockout > Duration.zero) {
      _lockoutTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final a = context.read<AuthProvider>();
        if (a.remainingLockout <= Duration.zero) {
          _lockoutTicker?.cancel();
          _lockoutTicker = null;
        }
        setState(() {});
      });
    } else {
      _lockoutTicker?.cancel();
      _lockoutTicker = null;
    }
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleSupabaseConfig() async {
    final url = _supabaseUrlController.text.trim();
    final key = _supabaseKeyController.text.trim();
    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen Supabase URL ve Anon Key girin.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.configureSupabase(url, key);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      setState(() => _isConfiguringSupabase = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase başarıyla bağlandı!')),
      );
    }
  }

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final auth = context.read<AuthProvider>();

    if (!_isRegistering && auth.isQuickPinEnabled && _usePinMode) {
      final pin = _pinController.text.trim();
      if (pin.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen PIN kodunuzu girin.')),
        );
        return;
      }
      setState(() => _isLoading = true);
      final ok = await auth.unlockWithQuickPin(pin);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!ok && !auth.isQuickPinEnabled) _usePinMode = false;
      });
      _pinController.clear();
      _syncLockoutTicker(auth);
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir e-posta adresi girin.')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ana parola en az 8 karakter olmalıdır.')),
      );
      return;
    }
    if (_isRegistering && password != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Girilen parolalar eşleşmiyor!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    bool success;
    if (_isRegistering) {
      success = await auth.register(
        email: email,
        masterPassword: password,
        useArgon2id: _preferArgon2idOnRegister,
      );
    } else {
      success = await auth.login(email: email, masterPassword: password);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    _syncLockoutTicker(auth);
    if (success) {
      _passwordController.clear();
      _confirmPasswordController.clear();
    }
  }

  Future<void> _handleMfaVerify() async {
    final code = _mfaCodeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6 haneli doğrulama kodunu girin.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyLoginMfa(code);
    if (!mounted) return;
    setState(() => _isLoading = false);
    _syncLockoutTicker(auth);
    if (ok) {
      _mfaCodeController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    Widget content;
    if (_isConfiguringSupabase) {
      content = _buildSupabaseConfigView(auth, theme, l10n);
    } else if (auth.status == VaultLockStatus.mfaRequired) {
      content = _buildMfaView(auth, theme, l10n);
    } else {
      content = _buildAuthView(auth, theme, l10n);
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMfaView(
    AuthProvider auth,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final rem = auth.remainingLockout;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.verified_user, size: 52, color: Colors.indigoAccent),
        const SizedBox(height: 14),
        Text(
          l10n.mfaTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.mfaPrompt,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _mfaCodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            labelText: '2FA Kodu',
            counterText: '',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          onSubmitted: (_) {
            if (!_isLoading) _handleMfaVerify();
          },
        ),
        if (auth.errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: auth.errorMessage!),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _isLoading || rem > Duration.zero ? null : _handleMfaVerify,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open),
          label: Text(
            rem > Duration.zero
                ? '${rem.inSeconds + 1} sn bekleyin'
                : l10n.tr('Doğrula ve Kasayı Aç', 'Verify & Unlock'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading ? null : () => auth.cancelMfaAndLock(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _buildSupabaseConfigView(
    AuthProvider auth,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_sync, size: 48, color: Colors.indigoAccent),
        const SizedBox(height: 16),
        Text(
          'Bulut Bağlantı Ayarı',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Cihazlar arası anlık şifreli senkronizasyon için Supabase proje bilgilerinizi girin.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _supabaseUrlController,
          decoration: const InputDecoration(
            labelText: 'Supabase Project URL',
            hintText: 'https://xxxx.supabase.co',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _supabaseKeyController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Supabase Anon Public Key',
            hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI...',
            prefixIcon: Icon(Icons.key),
          ),
        ),
        const SizedBox(height: 20),
        if (auth.errorMessage != null) ...[
          _ErrorBanner(message: auth.errorMessage!),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _isLoading ? null : _handleSupabaseConfig,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Bağlan ve Kaydet'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _isConfiguringSupabase = false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  Widget _buildAuthView(
    AuthProvider auth,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final remLockout = auth.remainingLockout;
    final isLockedOut = remLockout > Duration.zero;
    final showPinEntry = !_isRegistering && auth.isQuickPinEnabled && _usePinMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.shield_outlined, size: 56, color: Colors.indigoAccent),
        const SizedBox(height: 12),
        Text(
          'MultiPad',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Zero-Knowledge Şifreli Kasa',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),

        if (isLockedOut) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_off_outlined, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Çok fazla hatalı deneme! Güvenlik kilidi bitmesine ${remLockout.inSeconds + 1} sn kaldı.',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (auth.isBiometricTemporarilyDisabled) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.fingerprint, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Üst üste hatalı girişler nedeniyle biyometrik kilit geçici olarak kapatıldı.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (!_isRegistering && auth.canUseBiometricsNow) ...[
          OutlinedButton.icon(
            onPressed: _isLoading
                ? null
                : () async {
                    await auth.unlockWithBiometrics();
                    if (mounted) _syncLockoutTicker(auth);
                  },
            icon: const Icon(Icons.fingerprint, size: 24),
            label: Text(
              l10n.tr(
                'Biyometrik (Touch ID / Parmak İzi) ile Aç',
                'Unlock with Biometrics',
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (!_isRegistering && auth.isQuickPinEnabled) ...[
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.pin_outlined, size: 16),
                label: Text(l10n.quickPin),
              ),
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.password, size: 16),
                label: Text(l10n.tr('Ana Parola', 'Master Password')),
              ),
            ],
            selected: {_usePinMode},
            onSelectionChanged: (s) {
              auth.clearError();
              setState(() => _usePinMode = s.first);
            },
          ),
          const SizedBox(height: 16),
        ],

        if (showPinEntry) ...[
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 12,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            decoration: InputDecoration(
              labelText: l10n.unlockWithPin,
              counterText: '',
              prefixIcon: const Icon(Icons.dialpad),
            ),
            onSubmitted: (_) {
              if (!_isLoading && !isLockedOut) _handleSubmit();
            },
          ),
        ] else ...[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: l10n.tr('E-posta Adresi', 'Email Address'),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onSubmitted: (_) {
              if (!_isRegistering && !_isLoading && !isLockedOut) _handleSubmit();
            },
            decoration: InputDecoration(
              labelText: l10n.tr('Ana Parola (Master Password)', 'Master Password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          if (_isRegistering) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscurePassword,
              onSubmitted: (_) {
                if (!_isLoading) _handleSubmit();
              },
              decoration: InputDecoration(
                labelText: l10n.tr('Ana Parolayı Onayla', 'Confirm Master Password'),
                prefixIcon: const Icon(Icons.lock_reset),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Argon2id Anahtar Türetme',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'GPU/ASIC kaba kuvvet saldırılarına karşı gelişmiş koruma (önerilen).',
                style: TextStyle(fontSize: 11),
              ),
              value: _preferArgon2idOnRegister,
              onChanged: (v) => setState(() => _preferArgon2idOnRegister = v),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Uyarı: Ana parolanız hiçbir sunucuya gönderilmez. Unutursanız verileriniz kurtarılamaz!',
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
            ),
          ],
        ],

        if (auth.errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(message: auth.errorMessage!),
        ],

        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isLoading || isLockedOut ? null : _handleSubmit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _isRegistering
                      ? l10n.register
                      : (showPinEntry ? l10n.unlockWithPin : l10n.login),
                ),
        ),
        const SizedBox(height: 12),

        TextButton(
          onPressed: () {
            auth.clearError();
            setState(() => _isRegistering = !_isRegistering);
          },
          child: Text(
            _isRegistering
                ? 'Zaten hesabınız var mı? Giriş Yapın'
                : 'İlk kez mi kullanıyorsunuz? Yeni Hesap Oluşturun',
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.devices_other, size: 18),
          label: const Text(
            'Başka Cihazdan Aktar / Eşleştir',
            style: TextStyle(fontSize: 13),
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const DevicePairingScreen(initialRole: PairingRole.receive),
              ),
            );
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.settings_ethernet, size: 16),
          label: const Text(
            'Bulut Sunucu Ayarı (Supabase)',
            style: TextStyle(fontSize: 12),
          ),
          onPressed: () => setState(() => _isConfiguringSupabase = true),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
