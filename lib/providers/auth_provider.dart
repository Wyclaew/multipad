import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/supabase_service.dart';

enum VaultLockStatus {
  needsSetup,       // Needs Supabase URL/Key configuration
  lockedWithPass,   // Locked, master password or biometric required
  unlocked,         // Unlocked and ready
}

class AuthProvider with ChangeNotifier {
  final CryptoService _cryptoService = CryptoService();
  final BiometricService _biometricService = BiometricService();
  final SupabaseService _supabaseService = SupabaseService();

  VaultLockStatus _status = VaultLockStatus.needsSetup;
  List<int>? _masterKey;
  String? _currentUserEmail;
  bool _canUseBiometrics = false;
  bool _isBiometricEnabled = false;
  String? _errorMessage;

  VaultLockStatus get status => _status;
  bool get isUnlocked => _status == VaultLockStatus.unlocked && _masterKey != null;
  List<int>? get masterKey => _masterKey;
  String? get currentUserEmail => _currentUserEmail;
  bool get canUseBiometrics => _canUseBiometrics;
  bool get isBiometricEnabled => _isBiometricEnabled;
  String? get errorMessage => _errorMessage;

  CryptoService get cryptoService => _cryptoService;
  SupabaseService get supabaseService => _supabaseService;

  /// Initial app startup check
  Future<void> checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.keySupabaseUrl) ?? AppConstants.defaultSupabaseUrl;
    final anonKey = prefs.getString(AppConstants.keySupabaseAnonKey) ?? AppConstants.defaultSupabaseAnonKey;

    if (url.trim().isEmpty || anonKey.trim().isEmpty) {
      _status = VaultLockStatus.needsSetup;
      notifyListeners();
      return;
    }

    final initialized = await SupabaseService.initialize();
    if (!initialized) {
      _status = VaultLockStatus.needsSetup;
      notifyListeners();
      return;
    }

    _currentUserEmail = prefs.getString(AppConstants.keyCachedEmail);
    _canUseBiometrics = await _biometricService.canCheckBiometrics();
    _isBiometricEnabled = await _biometricService.isBiometricUnlockEnabled();

    // Default to locked state awaiting password or biometric unlock
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();

    // If biometric unlock is enabled, try unlocking immediately
    if (_isBiometricEnabled && _canUseBiometrics) {
      await unlockWithBiometrics();
    }
  }

  /// Configure or update Supabase credentials
  Future<bool> configureSupabase(String url, String anonKey) async {
    _errorMessage = null;
    final success = await SupabaseService.initialize(customUrl: url, customAnonKey: anonKey);
    if (success) {
      _status = VaultLockStatus.lockedWithPass;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Supabase bağlantısı başarısız oldu. URL ve API Anahtarını kontrol edin.';
      notifyListeners();
      return false;
    }
  }

  /// Sign up a new user with Master Password
  Future<bool> register({required String email, required String masterPassword}) async {
    _errorMessage = null;
    try {
      final salt = _cryptoService.generateSalt();
      final derivedKey = await _cryptoService.deriveMasterKey(masterPassword, salt);
      final authPassword = _cryptoService.deriveAuthPassword(derivedKey);

      await _supabaseService.signUp(
        email: email,
        authPassword: authPassword,
        masterSalt: salt,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyMasterSalt, salt);
      await prefs.setString(AppConstants.keyCachedEmail, email);

      _masterKey = derivedKey;
      _currentUserEmail = email;
      _status = VaultLockStatus.unlocked;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Kayıt hatası: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Login with Master Password
  Future<bool> login({required String email, required String masterPassword}) async {
    _errorMessage = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? salt = prefs.getString(AppConstants.keyMasterSalt);

      // If salt not cached locally, fetch from Supabase user_profiles
      salt ??= await _supabaseService.fetchUserMasterSalt(email);

      if (salt == null) {
        // Fallback: derive deterministic salt from email if user profile was created elsewhere
        salt = _cryptoService.generateSalt();
      }

      final derivedKey = await _cryptoService.deriveMasterKey(masterPassword, salt);
      final authPassword = _cryptoService.deriveAuthPassword(derivedKey);

      await _supabaseService.signIn(
        email: email,
        authPassword: authPassword,
      );

      await prefs.setString(AppConstants.keyMasterSalt, salt);
      await prefs.setString(AppConstants.keyCachedEmail, email);

      _masterKey = derivedKey;
      _currentUserEmail = email;
      _status = VaultLockStatus.unlocked;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Giriş hatası: Şifre veya e-posta hatalı. (${e.toString()})';
      notifyListeners();
      return false;
    }
  }

  /// Unlock using Touch ID / Fingerprint / Windows Hello
  Future<bool> unlockWithBiometrics() async {
    _errorMessage = null;
    try {
      final key = await _biometricService.retrieveBiometricMasterKey();
      if (key != null) {
        _masterKey = key;
        _status = VaultLockStatus.unlocked;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = 'Biyometrik kilit açma başarısız: $e';
      notifyListeners();
      return false;
    }
  }

  /// Toggle Biometrics
  Future<void> toggleBiometrics(bool enable) async {
    if (_masterKey == null) return;
    if (enable) {
      final authenticated = await _biometricService.authenticate(
        reason: 'Parmak İzi / Touch ID ile girişi aktifleştirmek için doğrulayın',
      );
      if (authenticated) {
        await _biometricService.enableBiometrics(_masterKey!);
        _isBiometricEnabled = true;
      }
    } else {
      await _biometricService.disableBiometrics();
      _isBiometricEnabled = false;
    }
    notifyListeners();
  }

  /// Lock Vault (wipes master encryption key from RAM immediately)
  void lockVault() {
    if (_masterKey != null) {
      _masterKey!.fillRange(0, _masterKey!.length, 0); // Zero out key memory
      _masterKey = null;
    }
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }

  /// Logout completely
  Future<void> logout() async {
    lockVault();
    await _supabaseService.signOut();
    _currentUserEmail = null;
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }
}
