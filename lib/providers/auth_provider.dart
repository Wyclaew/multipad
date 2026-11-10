import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/offline_storage_service.dart';
import '../services/pairing_service.dart';
import '../services/supabase_service.dart';
import 'vault_provider.dart';

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
  int _globalPasswordExpiryDays = 90; // Default 90 days (0 = disabled)
  String? _errorMessage;

  VaultLockStatus get status => _status;
  bool get isUnlocked => _status == VaultLockStatus.unlocked && _masterKey != null;
  List<int>? get masterKey => _masterKey;
  String? get currentUserEmail => _currentUserEmail;
  bool get canUseBiometrics => _canUseBiometrics;
  bool get isBiometricEnabled => _isBiometricEnabled;
  int get globalPasswordExpiryDays => _globalPasswordExpiryDays;
  String? get errorMessage => _errorMessage;

  CryptoService get cryptoService => _cryptoService;
  SupabaseService get supabaseService => _supabaseService;

  /// Initial app startup check
  Future<void> checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.keySupabaseUrl) ?? AppConstants.defaultSupabaseUrl;
    final anonKey = prefs.getString(AppConstants.keySupabaseAnonKey) ?? AppConstants.defaultSupabaseAnonKey;

    _globalPasswordExpiryDays = prefs.getInt(AppConstants.keyGlobalPasswordExpiryDays) ?? 90;

    if (url.trim().isEmpty || anonKey.trim().isEmpty) {
      _status = VaultLockStatus.lockedWithPass;
      _currentUserEmail = prefs.getString(AppConstants.keyCachedEmail) ?? 'Yerel Kasa Kullanıcısı';
      _canUseBiometrics = await _biometricService.canCheckBiometrics();
      _isBiometricEnabled = await _biometricService.isBiometricUnlockEnabled();
      notifyListeners();

      if (_isBiometricEnabled && _canUseBiometrics) {
        await unlockWithBiometrics();
      }
      return;
    }

    final initialized = await SupabaseService.initialize();
    if (!initialized) {
      _status = VaultLockStatus.lockedWithPass;
      _currentUserEmail = prefs.getString(AppConstants.keyCachedEmail);
      _canUseBiometrics = await _biometricService.canCheckBiometrics();
      _isBiometricEnabled = await _biometricService.isBiometricUnlockEnabled();
      notifyListeners();
      return;
    }

    _currentUserEmail = prefs.getString(AppConstants.keyCachedEmail);
    _canUseBiometrics = await _biometricService.canCheckBiometrics();
    _isBiometricEnabled = await _biometricService.isBiometricUnlockEnabled();

    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();

    if (_isBiometricEnabled && _canUseBiometrics) {
      await unlockWithBiometrics();
    }
  }

  /// Change global password expiry days (0 = disabled, 30, 60, 90, 180, 365)
  Future<void> setGlobalPasswordExpiryDays(int days) async {
    _globalPasswordExpiryDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyGlobalPasswordExpiryDays, days);
    notifyListeners();
  }

  /// Configure or update Supabase credentials
  Future<bool> configureSupabase(String url, String anonKey) async {
    _errorMessage = null;
    final success = await SupabaseService.initialize(customUrl: url, customAnonKey: anonKey);
    if (success) {
      if (_status == VaultLockStatus.needsSetup) {
        _status = VaultLockStatus.lockedWithPass;
      }
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Supabase bağlantısı başarısız oldu. URL ve API Anahtarını kontrol edin.';
      notifyListeners();
      return false;
    }
  }

  /// Connects Supabase while already unlocked in local-only mode and auto-syncs vault
  Future<bool> connectCloudWhileUnlocked({
    required String url,
    required String anonKey,
    required VaultProvider vault,
  }) async {
    _errorMessage = null;
    if (_masterKey == null) {
      _errorMessage = 'Önce kasanın kilidini açın.';
      return false;
    }

    final initialized = await SupabaseService.initialize(customUrl: url, customAnonKey: anonKey);
    if (!initialized) {
      _errorMessage = 'Supabase bağlantısı başarısız oldu. URL ve API Anahtarını kontrol edin.';
      notifyListeners();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = (_currentUserEmail ?? prefs.getString(AppConstants.keyCachedEmail) ?? '').trim().toLowerCase();
    String? salt = prefs.getString(AppConstants.keyMasterSalt);

    if (email.isEmpty || !email.contains('@')) {
      _errorMessage = 'Bulut hesabı oluşturmak için geçerli bir e-posta ile giriş yapmış olmalısınız.';
      notifyListeners();
      return false;
    }

    if (salt == null) {
      _errorMessage = 'Yerel kasa tuzu bulunamadı.';
      notifyListeners();
      return false;
    }

    final authPassword = _cryptoService.deriveAuthPassword(_masterKey!);

    try {
      await _supabaseService.signIn(email: email, authPassword: authPassword);
    } catch (_) {
      try {
        await _supabaseService.signUp(
          email: email,
          authPassword: authPassword,
          masterSalt: salt,
        );
      } catch (e) {
        _errorMessage = 'Bulut oturumu açılamadı: $e';
        notifyListeners();
        return false;
      }
    }

    await vault.loadVault();
    notifyListeners();
    return true;
  }

  /// Sign up a new user with Master Password
  Future<bool> register({required String email, required String masterPassword}) async {
    _errorMessage = null;
    final cleanEmail = email.trim().toLowerCase();

    try {
      final salt = _cryptoService.generateSalt();
      final derivedKey = await _cryptoService.deriveMasterKey(masterPassword, salt);
      final authPassword = _cryptoService.deriveAuthPassword(derivedKey);

      if (SupabaseService.isInitialized) {
        await _supabaseService.signUp(
          email: cleanEmail,
          authPassword: authPassword,
          masterSalt: salt,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyMasterSalt, salt);
      await prefs.setString(AppConstants.keyCachedEmail, cleanEmail);

      _masterKey = derivedKey;
      _currentUserEmail = cleanEmail;
      _canUseBiometrics = await _biometricService.canCheckBiometrics();
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
    final cleanEmail = email.trim().toLowerCase();

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedEmail = prefs.getString(AppConstants.keyCachedEmail)?.trim().toLowerCase();
      String? salt = (cachedEmail == cleanEmail) ? prefs.getString(AppConstants.keyMasterSalt) : null;

      if (salt == null && SupabaseService.isInitialized) {
        salt = await _supabaseService.fetchUserMasterSalt(cleanEmail);
      }

      if (salt == null) {
        // Fallback if single-user offline mode and cachedEmail wasn't set cleanly
        if (!SupabaseService.isInitialized && prefs.getString(AppConstants.keyMasterSalt) != null && cachedEmail == null) {
          salt = prefs.getString(AppConstants.keyMasterSalt);
        }
      }

      if (salt == null) {
        if (SupabaseService.isInitialized) {
          throw Exception('Bu e-posta adresine ait bir hesap bulunamadı. Lütfen kontrol edin veya yeni kasa oluşturun.');
        } else {
          throw Exception('Cihazda kayıtlı yerel kasa bulunamadı. Lütfen önce "Yeni Kasa Oluştur" veya "Başka Cihazdan Aktar" seçeneğini kullanın.');
        }
      }

      final derivedKey = await _cryptoService.deriveMasterKey(masterPassword, salt);
      final authPassword = _cryptoService.deriveAuthPassword(derivedKey);

      if (SupabaseService.isInitialized) {
        await _supabaseService.signIn(
          email: cleanEmail,
          authPassword: authPassword,
        );
      }

      await prefs.setString(AppConstants.keyMasterSalt, salt);
      await prefs.setString(AppConstants.keyCachedEmail, cleanEmail);

      _masterKey = derivedKey;
      _currentUserEmail = cleanEmail;
      _canUseBiometrics = await _biometricService.canCheckBiometrics();
      _status = VaultLockStatus.unlocked;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Giriş hatası: ${e.toString().replaceAll('Exception: ', '')}';
      notifyListeners();
      return false;
    }
  }

  /// Builds an encrypted pairing payload to transfer account, Supabase config, and optionally unlocked key
  Future<PairingPayload> buildPairingPayload({required bool includeUnlockedKey}) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.keySupabaseUrl) ?? AppConstants.defaultSupabaseUrl;
    final anonKey = prefs.getString(AppConstants.keySupabaseAnonKey) ?? AppConstants.defaultSupabaseAnonKey;
    final salt = prefs.getString(AppConstants.keyMasterSalt) ?? '';
    final email = _currentUserEmail ?? prefs.getString(AppConstants.keyCachedEmail) ?? '';
    final localItems = await OfflineStorageService.loadLocalItems();

    return PairingPayload(
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
      email: email,
      masterSalt: salt,
      masterKeyBase64: (includeUnlockedKey && _masterKey != null) ? base64Encode(_masterKey!) : null,
      offlineItems: localItems,
    );
  }

  /// Completes setup on a newly paired device (configures Supabase, signs in automatically, syncs items)
  Future<bool> completePairingSetup(PairingPayload payload) async {
    _errorMessage = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanEmail = payload.email.trim().toLowerCase();

      if (payload.masterSalt.isNotEmpty) {
        await prefs.setString(AppConstants.keyMasterSalt, payload.masterSalt);
      }
      if (cleanEmail.isNotEmpty) {
        await prefs.setString(AppConstants.keyCachedEmail, cleanEmail);
        _currentUserEmail = cleanEmail;
      }

      // 1. Configure & initialize Supabase automatically
      if (payload.supabaseUrl.trim().isNotEmpty && payload.supabaseAnonKey.trim().isNotEmpty) {
        await SupabaseService.initialize(
          customUrl: payload.supabaseUrl.trim(),
          customAnonKey: payload.supabaseAnonKey.trim(),
        );
      }

      // 2. Import encrypted offline items locally
      for (final rawItem in payload.offlineItems) {
        await OfflineStorageService.upsertLocalItem(rawItem);
      }

      _canUseBiometrics = await _biometricService.canCheckBiometrics();

      // 3. If unlocked masterKey was transferred, auto-sign into Supabase & unlock vault directly!
      if (payload.masterKeyBase64 != null && payload.masterKeyBase64!.isNotEmpty) {
        final receivedKey = base64Decode(payload.masterKeyBase64!);

        if (SupabaseService.isInitialized && cleanEmail.isNotEmpty) {
          final authPassword = _cryptoService.deriveAuthPassword(receivedKey);
          try {
            await _supabaseService.signIn(
              email: cleanEmail,
              authPassword: authPassword,
            );
          } catch (signInErr) {
            debugPrint('Pairing auto sign-in warning (continuing with local vault): $signInErr');
          }
        }

        CryptoService.wipe(_masterKey);
        _masterKey = receivedKey;
        _status = VaultLockStatus.unlocked;
      } else {
        _status = VaultLockStatus.lockedWithPass;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Cihaz eşleştirme uygulanırken hata oluştu: $e';
      notifyListeners();
      return false;
    }
  }

  /// Atomically change the master password and re-encrypt the entire vault
  Future<bool> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    required VaultProvider vault,
  }) async {
    _errorMessage = null;
    if (_masterKey == null) {
      _errorMessage = 'Kasa açık değil.';
      notifyListeners();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentSalt = prefs.getString(AppConstants.keyMasterSalt);
    if (currentSalt == null) {
      _errorMessage = 'Mevcut kasa tuzu bulunamadı.';
      notifyListeners();
      return false;
    }

    // 1. Verify current password
    final testCurrentKey = await _cryptoService.deriveMasterKey(currentPassword, currentSalt);
    final isCurrentMatch = CryptoService.constantTimeEquals(testCurrentKey, _masterKey!);
    CryptoService.wipe(testCurrentKey);

    if (!isCurrentMatch) {
      _errorMessage = 'Mevcut ana şifre hatalı!';
      notifyListeners();
      return false;
    }

    // 2. Derive new keys with fresh random salt
    final newSalt = _cryptoService.generateSalt();
    final newMasterKey = await _cryptoService.deriveMasterKey(newPassword, newSalt);
    final newAuthPassword = _cryptoService.deriveAuthPassword(newMasterKey);

    try {
      // 3. Re-encrypt all vault items in memory and storage
      await vault.reEncryptAllWithNewKey(newMasterKey);

      // 4. Update Supabase if connected
      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        await _supabaseService.updateMasterSaltAndAuthPassword(
          newMasterSalt: newSalt,
          newAuthPassword: newAuthPassword,
        );
      }

      // 5. Update local salt
      await prefs.setString(AppConstants.keyMasterSalt, newSalt);

      // 6. Update Hardware Biometrics if enabled
      if (_isBiometricEnabled) {
        try {
          await _biometricService.enableBiometrics(newMasterKey);
        } catch (e) {
          debugPrint('Biometric key rotation warning: $e');
        }
      }

      // 7. Update in-memory master key and wipe old key
      CryptoService.wipe(_masterKey);
      _masterKey = newMasterKey;
      notifyListeners();
      return true;
    } catch (e) {
      CryptoService.wipe(newMasterKey);
      _errorMessage = 'Şifre güncelleme hatası: $e';
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
  Future<bool> toggleBiometrics(bool enable) async {
    _errorMessage = null;
    if (_masterKey == null) return false;
    try {
      if (enable) {
        final authenticated = await _biometricService.authenticate(
          reason: 'Parmak İzi / Touch ID ile girişi aktifleştirmek için doğrulayın',
        );
        if (authenticated) {
          await _biometricService.enableBiometrics(_masterKey!);
          _isBiometricEnabled = true;
          notifyListeners();
          return true;
        }
        return false;
      } else {
        await _biometricService.disableBiometrics();
        _isBiometricEnabled = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _errorMessage = 'Biyometrik ayar değiştirilemedi: $e';
      notifyListeners();
      return false;
    }
  }

  /// Lock Vault (wipes master encryption key from RAM immediately)
  void lockVault() {
    if (_masterKey != null) {
      CryptoService.wipe(_masterKey);
      _masterKey = null;
    }
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }

  /// Logout completely
  Future<void> logout() async {
    lockVault();
    await _biometricService.disableBiometrics();
    _isBiometricEnabled = false;

    if (SupabaseService.isInitialized) {
      await _supabaseService.signOut();
    }
    _currentUserEmail = null;
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }
}
