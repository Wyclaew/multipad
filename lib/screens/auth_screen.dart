import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegistering = false;
  bool _isConfiguringSupabase = false;

  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserEmail != null) {
        _emailController.text = auth.currentUserEmail!;
      }
    });
  }

  @override
  void dispose() {
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    setState(() => _isLoading = false);

    if (success) {
      setState(() => _isConfiguringSupabase = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase başarıyla bağlandı!')),
        );
      }
    }
  }

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-posta ve Ana Şifre alanları zorunludur.')),
      );
      return;
    }

    if (_isRegistering) {
      if (password.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ana şifre en az 8 karakter olmalıdır.')),
        );
        return;
      }
      if (password != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifreler birbiriyle eşleşmiyor.')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    bool success = false;

    if (_isRegistering) {
      success = await auth.register(email: email, masterPassword: password);
    } else {
      success = await auth.login(email: email, masterPassword: password);
    }

    setState(() => _isLoading = false);

    if (!success && mounted && auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: _isConfiguringSupabase
                    ? _buildSupabaseConfigView(auth, theme)
                    : _buildAuthView(auth, theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupabaseConfigView(AuthProvider auth, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_sync_outlined, size: 48, color: Colors.blueAccent),
        const SizedBox(height: 12),
        const Text(
          'MultiPad Bulut Bağlantısı',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Cihazlar arası anlık şifreli senkronizasyon için Supabase proje bilgilerinizi girin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _supabaseUrlController,
          decoration: const InputDecoration(
            labelText: 'Supabase Project URL',
            hintText: 'https://xxxx.supabase.co',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _supabaseKeyController,
          decoration: const InputDecoration(
            labelText: 'Supabase Anon Public Key',
            hintText: 'eyJhbGciOiJIUzI1NiIsIn...',
            prefixIcon: Icon(Icons.vpn_key_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _isLoading ? null : _handleSupabaseConfig,
          icon: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Kaydet ve Bağlan', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _isConfiguringSupabase = false),
          child: const Text('Geri Dön / Yerel Kasa ile Devam Et'),
        ),
      ],
    );
  }

  Widget _buildAuthView(AuthProvider auth, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App Logo & Header
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_rounded, size: 32, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MultiPad',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
                Text(
                  'Sıfır-Bilgi Şifreli Kasa',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Biometric Quick Unlock (if available and enabled)
        if (auth.canUseBiometrics && auth.isBiometricEnabled && !_isRegistering) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Colors.blueAccent, width: 1.5),
            ),
            icon: const Icon(Icons.fingerprint_rounded, size: 28, color: Colors.blueAccent),
            label: const Text(
              'Touch ID / Parmak İzi ile Aç',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onPressed: _isLoading ? null : () => auth.unlockWithBiometrics(),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('veya Ana Şifre ile', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Segmented Tab for Login vs Register
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Giriş Yap')),
            ButtonSegment(value: true, label: Text('Yeni Kasa Oluştur')),
          ],
          selected: {_isRegistering},
          onSelectionChanged: (val) {
            setState(() {
              _isRegistering = val.first;
              _passwordController.clear();
              _confirmPasswordController.clear();
            });
          },
        ),

        const SizedBox(height: 20),

        // Email Field
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-posta Adresi',
            prefixIcon: Icon(Icons.alternate_email),
            border: OutlineInputBorder(),
          ),
        ),

        const SizedBox(height: 14),

        // Master Password Field
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Ana Şifre (Master Password)',
            prefixIcon: const Icon(Icons.key_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),

        if (_isRegistering) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscurePassword,
            decoration: const InputDecoration(
              labelText: 'Ana Şifre Tekrar',
              prefixIcon: Icon(Icons.lock_reset),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ana şifreniz cihazınızdan ASLA çıkmaz. Şifrenizi unutursanız verilerinizi kurtarmanın hiçbir yolu yoktur!',
                    style: TextStyle(fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 22),

        // Submit Button
        FilledButton(
          onPressed: _isLoading ? null : _handleSubmit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.all(15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  _isRegistering ? 'Güvenli Kasayı Başlat' : 'Kasanın Kilidini Aç',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),

        const SizedBox(height: 14),

        // Supabase Settings link
        TextButton.icon(
          icon: const Icon(Icons.cloud_outlined, size: 16),
          label: const Text('Bulut Senkronizasyon Ayarları', style: TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _isConfiguringSupabase = true),
        ),
      ],
    );
  }
}
