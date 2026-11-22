import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';
import '../main.dart' show rootNavigatorKey;
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/native_bridge_service.dart';
import '../services/offline_storage_service.dart';
import '../services/pairing_service.dart';
import '../services/security_log_service.dart';
import '../services/supabase_service.dart';
import '../services/totp_ticker_service.dart';

enum VaultLockStatus {
  needsSetup,
  lockedWithPass,
  mfaRequired,
  unlocked,
}

class AuthProvider with ChangeNotifier {
  final CryptoService _cryptoService;
  final SupabaseService _supabaseService;
  final BiometricService _biometricService;
  final SecurityLogService _securityLogService;
  final FlutterSecureStorage _secureStorage;
  final GlobalKey<NavigatorState>? _navigatorKey;

  AuthProvider({
    CryptoService? cryptoService,
    SupabaseService? supabaseService,
    BiometricService? biometricService,
    SecurityLogService? securityLogService,
    FlutterSecureStorage? secureStorage,
    GlobalKey<NavigatorState>? navigatorKey,
  })  : _cryptoService = cryptoService ?? CryptoService(),
        _supabaseService = supabaseService ?? SupabaseService(),
        _biometricService = biometricService ?? BiometricService(),
        _securityLogService = securityLogService ?? SecurityLogService(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              mOptions: MacOsOptions(useDataProtectionKeyChain: false),
            ),
        _navigatorKey = navigatorKey;

  VaultLockStatus _status = VaultLockStatus.needsSetup;
  List<int>? _masterKey;
  String? _currentUserEmail;
  String? _currentSalt;
  bool _canUseBiometrics = false;
  bool _isBiometricEnabled = false;
  bool _biometricDisabledDueToFailures = false;
  bool _isQuickPinEnabled = false;
  bool _isDuressEnabled = false;
  bool _isDuressMode = false;
  bool _preferArgon2id = true;
  bool _hasVerifiedMfa = false;
  DateTime? _twoFactorLastVerified;
  int _twoFactorRepromptDays = 30;
  int _globalPasswordExpiryDays = 90;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  int _autoLockSuppressionDepth = 0;
  int _suppressUntilResumedCount = 0;
  Timer? _resumeGraceTimer;
  Timer? _resumeFallbackTimer;
  String? _errorMessage;

  VaultLockStatus get status => _status;
  CryptoService get cryptoService => _cryptoService;
  bool get isUnlocked =>
      _status == VaultLockStatus.unlocked && _masterKey != null;
  List<int>? get masterKey => _masterKey;
  String? get currentUserEmail => _currentUserEmail;
  String? get currentSalt => _currentSalt;
  bool get canUseBiometrics => _canUseBiometrics;
  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isBiometricTemporarilyDisabled => _biometricDisabledDueToFailures;
  bool get canUseBiometricsNow =>
      _canUseBiometrics &&
      _isBiometricEnabled &&
      !_biometricDisabledDueToFailures &&
      remainingLockout == Duration.zero;
  bool get isQuickPinEnabled => _isQuickPinEnabled;
  bool get isDuressEnabled => _isDuressEnabled;
  bool get isDuressMode => _isDuressMode;
  bool get preferArgon2id => _preferArgon2id;
  bool get isArgon2idActive =>
      _currentSalt != null && CryptoService.isArgon2idSalt(_currentSalt!);
  bool get hasVerifiedMfa => _hasVerifiedMfa;
  DateTime? get twoFactorLastVerified => _twoFactorLastVerified;
  int get twoFactorRepromptDays => _twoFactorRepromptDays;
  int get globalPasswordExpiryDays => _globalPasswordExpiryDays;
  int get failedAttempts => _failedAttempts;
  DateTime? get lockoutUntil => _lockoutUntil;
  bool get isAutoLockSuppressed =>
      _autoLockSuppressionDepth > 0 || _suppressUntilResumedCount > 0;
  String? get errorMessage => _errorMessage;

  bool _isTwoFactorSignatureValid = true;
  bool get isTwoFactorSignatureValid => _isTwoFactorSignatureValid;

  /// Evaluates whether a Two-Factor Authentication prompt is due based on the configured interval.
  bool isTwoFactorPromptDue({DateTime? now, int? intervalDays}) {
    final days = intervalDays ?? _twoFactorRepromptDays;
    if (days <= 0) return true;
    if (_twoFactorLastVerified == null) return true;
    if (!_isTwoFactorSignatureValid) return true; // Tampered signature forces 2FA re-prompt
    final currentTime = now ?? DateTime.now().toUtc();
    final difference = currentTime.difference(_twoFactorLastVerified!);
    if (difference.isNegative) return false; // Clock skew protection
    return difference >= Duration(days: days);
  }

  static const String _keyMfaIntegrityDeviceKey = 'multipad_mfa_integrity_device_key_v1';

  /// Retrieves or generates a 256-bit persistent cryptographically random device key
  /// in FlutterSecureStorage used for signing and verifying 2FA integrity timestamps.
  Future<List<int>> _getOrCreateMfaIntegrityKey() async {
    try {
      final storedB64 = await _secureStorage.read(key: _keyMfaIntegrityDeviceKey);
      if (storedB64 != null && storedB64.isNotEmpty) {
        final decoded = base64Decode(storedB64);
        if (decoded.length >= 32) return decoded;
      }
    } catch (_) {}

    final newKey = _cryptoService.generateRandomBytes(32);
    try {
      await _secureStorage.write(
        key: _keyMfaIntegrityDeviceKey,
        value: base64Encode(newKey),
      );
    } catch (_) {}
    return newKey;
  }

  /// Saves 2FA verification timestamp into FlutterSecureStorage protected by an HMAC-SHA256 signature.
  Future<void> saveTwoFactorVerification(DateTime timestamp) async {
    _twoFactorLastVerified = timestamp.toUtc();
    final iso = _twoFactorLastVerified!.toIso8601String();

    final hmacKey = await _getOrCreateMfaIntegrityKey();
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, hmacKey);
    final signature = base64Encode(
      hmac.convert(utf8.encode('$iso:${_currentUserEmail ?? ""}')).bytes,
    );

    await _secureStorage.write(
      key: AppConstants.keyTwoFactorLastVerifiedIso,
      value: iso,
    );
    await _secureStorage.write(
      key: 'multipad_2fa_hmac_signature_v1',
      value: signature,
    );
    _isTwoFactorSignatureValid = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyTwoFactorLastVerifiedIso, iso);
    notifyListeners();
  }

  /// Verifies integrity of the 2FA verification timestamp using the HMAC-SHA256 signature.
  Future<bool> verifyTwoFactorTimestampIntegrity() async {
    final secureIso = await _secureStorage.read(key: AppConstants.keyTwoFactorLastVerifiedIso);
    final storedSignature = await _secureStorage.read(key: 'multipad_2fa_hmac_signature_v1');

    if (secureIso == null || storedSignature == null) {
      if (_twoFactorLastVerified != null) {
        _isTwoFactorSignatureValid = false;
        _twoFactorLastVerified = null;
        return false;
      }
      _isTwoFactorSignatureValid = true;
      return true;
    }

    if (_twoFactorLastVerified != null &&
        secureIso != _twoFactorLastVerified!.toIso8601String()) {
      _isTwoFactorSignatureValid = false;
      _twoFactorLastVerified = null;
      return false;
    }

    final hmacKey = await _getOrCreateMfaIntegrityKey();
    final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, hmacKey);
    final expectedSignature = base64Encode(
      hmac.convert(utf8.encode('$secureIso:${_currentUserEmail ?? ""}')).bytes,
    );

    _isTwoFactorSignatureValid = CryptoService.constantTimeStringEquals(
      storedSignature,
      expectedSignature,
    );
    if (!_isTwoFactorSignatureValid) {
      _twoFactorLastVerified = null;
    }
    return _isTwoFactorSignatureValid;
  }

  @visibleForTesting
  void setTwoFactorLastVerifiedForTesting(DateTime? timestamp, {bool signatureValid = true}) {
    _twoFactorLastVerified = timestamp;
    _isTwoFactorSignatureValid = signatureValid;
    notifyListeners();
  }

  Duration get remainingLockout {
    if (_lockoutUntil == null) return Duration.zero;
    final rem = _lockoutUntil!.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void beginSuppressAutoLock() {
    _autoLockSuppressionDepth++;
  }

  void endSuppressAutoLock() {
    if (_autoLockSuppressionDepth > 0) {
      _autoLockSuppressionDepth--;
    }
  }

  void beginSuppressAutoLockUntilResumed() {
    _resumeGraceTimer?.cancel();
    _resumeGraceTimer = null;
    _resumeFallbackTimer?.cancel();
    _suppressUntilResumedCount++;
  }

  void endSuppressAutoLockUntilResumed({bool immediate = false}) {
    if (immediate) {
      _resumeGraceTimer?.cancel();
      _resumeGraceTimer = null;
      _resumeFallbackTimer?.cancel();
      _resumeFallbackTimer = null;
      if (_suppressUntilResumedCount > 0) {
        _suppressUntilResumedCount = 0;
        notifyListeners();
      }
      return;
    }
    notifyAppResumed();
  }

  void notifyAppResumed() {
    if (_suppressUntilResumedCount > 0) {
      _resumeFallbackTimer?.cancel();
      _resumeFallbackTimer = null;
      _resumeGraceTimer?.cancel();
      _resumeGraceTimer = Timer(const Duration(milliseconds: 500), () {
        _suppressUntilResumedCount = 0;
        _resumeGraceTimer = null;
        notifyListeners();
      });
    }
  }

  Future<T> runWithoutAutoLock<T>(Future<T> Function() action) async {
    beginSuppressAutoLock();
    try {
      return await action();
    } finally {
      endSuppressAutoLock();
    }
  }

  Future<T> runWithoutAutoLockUntilResumed<T>(
    Future<T> Function() action, {
    Duration fallbackTimeout = const Duration(minutes: 5),
  }) async {
    beginSuppressAutoLockUntilResumed();
    _resumeFallbackTimer?.cancel();
    _resumeFallbackTimer = Timer(fallbackTimeout, () {
      if (_suppressUntilResumedCount > 0) {
        _suppressUntilResumedCount = 0;
        _resumeGraceTimer?.cancel();
        _resumeGraceTimer = null;
        notifyListeners();
      }
    });

    try {
      return await action();
    } catch (_) {
      notifyAppResumed();
      rethrow;
    }
  }

  @visibleForTesting
  void setBiometricsEnabledForTesting(bool enabled) {
    _canUseBiometrics = enabled;
    _isBiometricEnabled = enabled;
    _biometricDisabledDueToFailures = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _resumeGraceTimer?.cancel();
    _resumeFallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSecurityPreferences(SharedPreferences prefs) async {
    _currentUserEmail = prefs.getString(AppConstants.keyCachedEmail);
    _currentSalt = prefs.getString(AppConstants.keyMasterSalt);
    _globalPasswordExpiryDays =
        prefs.getInt(AppConstants.keyGlobalPasswordExpiryDays) ?? 90;
    _preferArgon2id = prefs.getBool(AppConstants.keyPreferArgon2id) ?? true;
    _isQuickPinEnabled = prefs.getBool(AppConstants.keyQuickPinEnabled) ?? false;
    _isDuressEnabled = prefs.getBool(AppConstants.keyDuressEnabled) ?? false;
    _failedAttempts = await _securityLogService.getFailedAttempts();
    _biometricDisabledDueToFailures =
        await _securityLogService.isBiometricTemporarilyDisabled();
    final lockoutIso = prefs.getString(AppConstants.keyLockoutUntilIso);
    _lockoutUntil = lockoutIso != null ? DateTime.tryParse(lockoutIso) : null;
    final lastVerifiedIso = prefs.getString(AppConstants.keyTwoFactorLastVerifiedIso);
    _twoFactorLastVerified = lastVerifiedIso != null ? DateTime.tryParse(lastVerifiedIso) : null;
    _twoFactorRepromptDays = prefs.getInt(AppConstants.keyTwoFactorRepromptDays) ?? 30;

    // Enforce 2FA timestamp integrity verification
    final isSignatureValid = await verifyTwoFactorTimestampIntegrity();
    if (!isSignatureValid) {
      _twoFactorLastVerified = null;
    }
  }

  Future<void> refreshSecurityState() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadSecurityPreferences(prefs);
    notifyListeners();
  }

  Future<void> checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadSecurityPreferences(prefs);

    _canUseBiometrics = await _biometricService.canCheckBiometrics();
    _isBiometricEnabled = await _biometricService.isBiometricUnlockEnabled();

    final hasLocalVault = _currentSalt != null && _currentSalt!.isNotEmpty;

    final hasCustomConfig =
        (prefs.getString(AppConstants.keySupabaseUrl) ?? '').isNotEmpty &&
        (prefs.getString(AppConstants.keySupabaseAnonKey) ?? '').isNotEmpty;
    final hasDefaultConfig =
        AppConstants.defaultSupabaseUrl.isNotEmpty &&
        AppConstants.defaultSupabaseAnonKey.isNotEmpty;

    if (!hasCustomConfig && !hasDefaultConfig) {
      _status = VaultLockStatus.lockedWithPass;
      notifyListeners();
      return;
    }

    final initialized = await SupabaseService.initialize();
    if (initialized) {
      await refreshMfaStatus();
      _status = VaultLockStatus.lockedWithPass;
      notifyListeners();
      return;
    }

    if (hasLocalVault) {
      _status = VaultLockStatus.lockedWithPass;
      notifyListeners();
      return;
    }

    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }

  Future<void> refreshMfaStatus() async {
    if (!SupabaseService.isInitialized || SupabaseService.currentUser == null) {
      _hasVerifiedMfa = false;
      return;
    }
    try {
      final factors = await _supabaseService.listTotpFactors();
      _hasVerifiedMfa = factors.isNotEmpty;
    } catch (_) {
      _hasVerifiedMfa = false;
    }
  }

  Future<void> setGlobalPasswordExpiryDays(int days) async {
    _globalPasswordExpiryDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyGlobalPasswordExpiryDays, days);
    notifyListeners();
  }

  Future<void> setPreferArgon2id(bool prefer) async {
    _preferArgon2id = prefer;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyPreferArgon2id, prefer);
    notifyListeners();
  }

  Future<bool> configureSupabase(String url, String anonKey) async {
    _errorMessage = null;
    final success = await SupabaseService.initialize(
      customUrl: url,
      customAnonKey: anonKey,
    );
    if (success) {
      await refreshMfaStatus();
      if (_status == VaultLockStatus.needsSetup) {
        _status = VaultLockStatus.lockedWithPass;
      }
      notifyListeners();
      return true;
    } else {
      _errorMessage =
          'Supabase bağlantısı başarısız oldu. URL ve API Anahtarını kontrol edin.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> connectCloudWhileUnlocked({
    required String url,
    required String anonKey,
    String? accountEmail,
  }) async {
    _errorMessage = null;
    if (!isUnlocked || _masterKey == null || _isDuressMode) {
      _errorMessage =
          _isDuressMode ? 'Bu işlem mevcut modda kullanılamaz.' : 'Önce kasanın kilidini açın.';
      notifyListeners();
      return false;
    }

    final initialized = await SupabaseService.initialize(
      customUrl: url,
      customAnonKey: anonKey,
    );
    if (!initialized) {
      _errorMessage =
          'Supabase bağlantısı başarısız oldu. URL ve API Anahtarını kontrol edin.';
      notifyListeners();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final email = (accountEmail ?? _currentUserEmail ?? '').trim().toLowerCase();
    final salt = prefs.getString(AppConstants.keyMasterSalt);

    if (email.isEmpty || !email.contains('@')) {
      _errorMessage =
          'Bulut hesabı oluşturmak için geçerli bir e-posta ile giriş yapmış olmalısınız.';
      notifyListeners();
      return false;
    }
    if (salt == null || salt.isEmpty) {
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

    await prefs.setString(AppConstants.keyCachedEmail, email);
    _currentUserEmail = email;
    await refreshMfaStatus();
    notifyListeners();
    return true;
  }

  Future<bool> _checkLockoutBeforeAttempt() async {
    final rem = await _securityLogService.getRemainingLockout();
    final prefs = await SharedPreferences.getInstance();
    await _loadSecurityPreferences(prefs);
    if (rem > Duration.zero) {
      final secs = rem.inSeconds + 1;
      _errorMessage =
          'Çok fazla hatalı deneme yapıldı. Güvenlik için $secs sn bekleyin.';
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _recordFailure(String sourceLabel, String baseError) async {
    final res = await _securityLogService.recordFailedAttempt(
      sourceLabel: sourceLabel,
    );
    final prefs = await SharedPreferences.getInstance();
    await _loadSecurityPreferences(prefs);
    if (res.lockoutDuration > Duration.zero) {
      _errorMessage =
          '$baseError (${res.failedCount}. hata — ${res.lockoutDuration.inSeconds} sn bekleme uygulanıyor.)';
    } else {
      _errorMessage = baseError;
    }
  }

  Future<bool> register({
    required String email,
    required String masterPassword,
    bool? useArgon2id,
  }) async {
    _errorMessage = null;
    try {
      final cleanEmail = email.trim().toLowerCase();
      final effectiveArgon = useArgon2id ?? _preferArgon2id;
      final salt = _cryptoService.generateSalt(
        useArgon2id: effectiveArgon,
      );
      final derivedKey = await _cryptoService.deriveMasterKey(
        masterPassword,
        salt,
      );
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
      await _securityLogService.resetFailedAttempts();
      await _loadSecurityPreferences(prefs);

      _currentUserEmail = cleanEmail;
      _currentSalt = salt;
      _masterKey = derivedKey;
      _isDuressMode = false;
      _status = VaultLockStatus.unlocked;
      await _securityLogService.logEvent(
        SecurityEventType.unlockSuccess,
        'Yeni hesap ve kasa oluşturuldu (${CryptoService.isArgon2idSalt(salt) ? "Argon2id" : "PBKDF2"}).',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Kayıt hatası: ${e.toString().replaceAll("Exception: ", "")}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _verifyLocalMasterKeyAgainstStoredItems(List<int> key) async {
    final localRows = await OfflineStorageService.loadLocalItems();
    if (localRows.isEmpty) {
      return true;
    }
    for (final row in localRows) {
      final ciphertext = row['encrypted_payload'] as String?;
      final iv = row['iv'] as String?;
      final mac = row['mac'] as String?;
      if (ciphertext != null && iv != null && mac != null) {
        try {
          await _cryptoService.decryptData(
            ciphertextBase64: ciphertext,
            ivBase64: iv,
            macBase64: mac,
            masterKey: key,
          );
          return true;
        } catch (_) {
          return false;
        }
      }
    }
    return true;
  }

  Future<bool> login({
    required String email,
    required String masterPassword,
  }) async {
    _errorMessage = null;
    if (await _checkLockoutBeforeAttempt()) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanEmail = email.trim().toLowerCase();
      final cachedEmail = prefs.getString(AppConstants.keyCachedEmail);

      // 1. Check Duress / Panic Password first (for the cached/local account)
      final duressEnabled = prefs.getBool(AppConstants.keyDuressEnabled) ?? false;
      final duressSalt = prefs.getString(AppConstants.keyDuressSalt);
      final duressVerifier = prefs.getString(AppConstants.keyDuressVerifier);
      if (duressEnabled &&
          duressSalt != null &&
          duressVerifier != null &&
          (cachedEmail == null || cachedEmail == cleanEmail)) {
        final candidateDuressKey = await _cryptoService.deriveMasterKey(
          masterPassword,
          duressSalt,
        );
        final candidateVerifier = _cryptoService.deriveDuressVerifier(
          candidateDuressKey,
        );
        if (CryptoService.constantTimeStringEquals(
          candidateVerifier,
          duressVerifier,
        )) {
          _currentUserEmail = cleanEmail;
          _masterKey = candidateDuressKey;
          _isDuressMode = true;
          _status = VaultLockStatus.unlocked;
          await _securityLogService.logEvent(
            SecurityEventType.duressUnlocked,
            'Panik/Sahte kasa parolası ile oturum açıldı.',
            isWarning: true,
          );
          notifyListeners();
          return true;
        }
      }

      // 2. Normal login: locate salt (local cache or Supabase)
      String? salt = (cachedEmail == cleanEmail)
          ? prefs.getString(AppConstants.keyMasterSalt)
          : null;

      bool onlineReachable = false;
      if (salt == null && SupabaseService.isInitialized) {
        try {
          salt = await _supabaseService.fetchUserMasterSalt(cleanEmail);
          onlineReachable = true;
        } catch (e) {
          debugPrint('fetchUserMasterSalt fallback check: $e');
        }
      }

      if (salt == null) {
        if (!SupabaseService.isInitialized &&
            prefs.getString(AppConstants.keyMasterSalt) != null &&
            cachedEmail == null) {
          salt = prefs.getString(AppConstants.keyMasterSalt);
        }
      }

      if (salt == null) {
        await _recordFailure(
          'Ana Parola',
          'Kullanıcı hesabı veya kasa tuzu bulunamadı.',
        );
        notifyListeners();
        return false;
      }

      final derivedKey = await _cryptoService.deriveMasterKey(
        masterPassword,
        salt,
      );
      final authPassword = _cryptoService.deriveAuthPassword(derivedKey);

      if (SupabaseService.isInitialized) {
        try {
          await _supabaseService.signIn(
            email: cleanEmail,
            authPassword: authPassword,
          );
          onlineReachable = true;
        } on AuthException catch (authErr) {
          await _recordFailure(
            'Ana Parola',
            'Giriş başarısız: ${authErr.message}',
          );
          notifyListeners();
          return false;
        } catch (netErr) {
          // Offline network error with matching local cached account: allow offline verify!
          if (cachedEmail == cleanEmail &&
              prefs.getString(AppConstants.keyMasterSalt) != null) {
            final validLocal = await _verifyLocalMasterKeyAgainstStoredItems(
              derivedKey,
            );
            if (!validLocal) {
              await _recordFailure('Ana Parola', 'Ana parola hatalı.');
              notifyListeners();
              return false;
            }
          } else {
            _errorMessage = 'Sunucuya erişilemedi: $netErr';
            notifyListeners();
            return false;
          }
        }
      } else {
        // Pure local mode: verify key if items exist
        final validLocal = await _verifyLocalMasterKeyAgainstStoredItems(
          derivedKey,
        );
        if (!validLocal) {
          await _recordFailure('Ana Parola', 'Ana parola hatalı.');
          notifyListeners();
          return false;
        }
      }

      await prefs.setString(AppConstants.keyMasterSalt, salt);
      await prefs.setString(AppConstants.keyCachedEmail, cleanEmail);
      await _securityLogService.resetFailedAttempts();
      await _loadSecurityPreferences(prefs);

      _currentUserEmail = cleanEmail;
      _currentSalt = salt;
      _masterKey = derivedKey;
      _isDuressMode = false;

      if (onlineReachable &&
          _supabaseService.requiresMfaVerification() &&
          isTwoFactorPromptDue()) {
        _hasVerifiedMfa = true;
        _status = VaultLockStatus.mfaRequired;
      } else {
        if (onlineReachable) {
          await refreshMfaStatus();
        }
        _status = VaultLockStatus.unlocked;
        await _securityLogService.logEvent(
          SecurityEventType.unlockSuccess,
          'Ana parola ile kasa açıldı.',
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      await _recordFailure(
        'Ana Parola',
        'Giriş hatası: ${e.toString().replaceAll("Exception: ", "")}',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyLoginMfa(String code) async {
    _errorMessage = null;
    if (await _checkLockoutBeforeAttempt()) {
      return false;
    }
    try {
      final cleanCode = code.replaceAll(RegExp(r'\s+'), '');
      if (cleanCode.length != 6) {
        _errorMessage = '6 haneli doğrulama kodunu girin.';
        notifyListeners();
        return false;
      }
      final factors = await _supabaseService.listTotpFactors();
      if (factors.isEmpty) {
        _status = VaultLockStatus.unlocked;
        notifyListeners();
        return true;
      }
      await _supabaseService.verifyTotpMfa(
        factorId: factors.first.id,
        code: cleanCode,
      );
      await _securityLogService.resetFailedAttempts();
      await saveTwoFactorVerification(DateTime.now().toUtc());

      _hasVerifiedMfa = true;
      _status = VaultLockStatus.unlocked;
      await _securityLogService.logEvent(
        SecurityEventType.unlockSuccess,
        '2FA TOTP doğrulaması ile kasa açıldı.',
      );
      notifyListeners();
      return true;
    } catch (e) {
      await _recordFailure(
        '2FA Doğrulama',
        '2FA kodu geçersiz veya süresi dolmuş: $e',
      );
      notifyListeners();
      return false;
    }
  }

  void cancelMfaAndLock() {
    final nav = _navigatorKey ?? rootNavigatorKey;
    nav.currentState?.popUntil((route) => route.isFirst);

    CryptoService.wipe(_masterKey);
    _masterKey = null;
    _isDuressMode = false;
    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }

  Future<AuthMFAEnrollResponse> startTotpMfaEnrollment({
    String friendlyName = 'MultiPad Authenticator',
  }) async {
    return await _supabaseService.enrollTotpMfa(friendlyName: friendlyName);
  }

  Future<bool> confirmTotpMfaEnrollment({
    required String factorId,
    required String code,
  }) async {
    _errorMessage = null;
    try {
      final cleanCode = code.replaceAll(RegExp(r'\s+'), '');
      await _supabaseService.verifyTotpMfa(
        factorId: factorId,
        code: cleanCode,
      );
      await refreshMfaStatus();
      await _securityLogService.logEvent(
        SecurityEventType.mfaChanged,
        'Hesap seviyesi TOTP 2FA aktifleştirildi.',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '2FA doğrulama hatası: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> disableMfa(String factorId) async {
    _errorMessage = null;
    try {
      await _supabaseService.unenrollMfa(factorId);
      await refreshMfaStatus();
      await _securityLogService.logEvent(
        SecurityEventType.mfaChanged,
        'Hesap seviyesi TOTP 2FA devre dışı bırakıldı.',
        isWarning: true,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = '2FA kaldırılamadı: $e';
      notifyListeners();
      return false;
    }
  }

  Future<List<Factor>> listAllMfaFactors() async {
    return await _supabaseService.listAllMfaFactors();
  }

  Future<bool> signOutOtherDevices() async {
    _errorMessage = null;
    try {
      await _supabaseService.signOutOtherDevices();
      await _securityLogService.logEvent(
        SecurityEventType.otherSessionsSignedOut,
        'Diğer tüm cihazlardaki aktif oturumlar kapatıldı.',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Diğer oturumlar sonlandırılamadı: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Quick PIN ---

  Future<bool> enableQuickPin(String pin) async {
    _errorMessage = null;
    if (!isUnlocked || _masterKey == null || _isDuressMode) {
      _errorMessage = 'Önce gerçek kasanızı açın.';
      notifyListeners();
      return false;
    }
    final cleanPin = pin.trim();
    if (!RegExp(r'^\d{4,12}$').hasMatch(cleanPin)) {
      _errorMessage = 'PIN 4 ile 12 arasında rakamdan oluşmalıdır.';
      notifyListeners();
      return false;
    }

    try {
      final saltBytes = _cryptoService.generateRandomBytes(16);
      final saltB64 = base64Encode(saltBytes);
      final wrappingKey = await _cryptoService.derivePinWrappingKey(
        cleanPin,
        saltB64,
      );
      try {
        final wrapped = await _cryptoService.encryptData(
          base64Encode(_masterKey!),
          wrappingKey,
        );
        final wrappedJson = jsonEncode(wrapped);
        await _secureStorage.write(
          key: AppConstants.keyQuickPinWrappedMasterKey,
          value: wrappedJson,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.keyQuickPinSalt, saltB64);
        await prefs.setBool(AppConstants.keyQuickPinEnabled, true);
        await prefs.setInt(AppConstants.keyQuickPinFailedAttempts, 0);
        _isQuickPinEnabled = true;
        notifyListeners();
        return true;
      } finally {
        CryptoService.wipe(wrappingKey);
      }
    } catch (e) {
      _errorMessage = 'Hızlı PIN ayarlanamadı: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> disableQuickPin() async {
    await _secureStorage.delete(key: AppConstants.keyQuickPinWrappedMasterKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyQuickPinEnabled, false);
    await prefs.remove(AppConstants.keyQuickPinSalt);
    await prefs.setInt(AppConstants.keyQuickPinFailedAttempts, 0);
    _isQuickPinEnabled = false;
    notifyListeners();
  }

  Future<bool> unlockWithQuickPin(String pin) async {
    _errorMessage = null;
    if (await _checkLockoutBeforeAttempt()) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final saltB64 = prefs.getString(AppConstants.keyQuickPinSalt);
    final wrappedJson = await _secureStorage.read(
      key: AppConstants.keyQuickPinWrappedMasterKey,
    );
    if (!_isQuickPinEnabled ||
        saltB64 == null ||
        wrappedJson == null ||
        wrappedJson.isEmpty) {
      await disableQuickPin();
      _errorMessage = 'Hızlı PIN kullanılamıyor; ana parolanızı girin.';
      notifyListeners();
      return false;
    }

    List<int>? wrappingKey;
    try {
      wrappingKey = await _cryptoService.derivePinWrappingKey(
        pin.trim(),
        saltB64,
      );
      final wrapped = jsonDecode(wrappedJson) as Map<String, dynamic>;
      final masterB64 = await _cryptoService.decryptData(
        ciphertextBase64: wrapped['ciphertext'] as String,
        ivBase64: wrapped['iv'] as String,
        macBase64: wrapped['mac'] as String,
        masterKey: wrappingKey,
      );
      final unlockedKey = base64Decode(masterB64);

      await prefs.setInt(AppConstants.keyQuickPinFailedAttempts, 0);
      await _securityLogService.resetFailedAttempts();
      await _loadSecurityPreferences(prefs);

      _masterKey = unlockedKey;
      _isDuressMode = false;

      if (SupabaseService.isInitialized &&
          SupabaseService.currentUser == null &&
          _currentUserEmail != null &&
          _currentUserEmail!.isNotEmpty) {
        try {
          final authPass = _cryptoService.deriveAuthPassword(unlockedKey);
          await _supabaseService.signIn(
            email: _currentUserEmail!,
            authPassword: authPass,
          );
        } catch (e) {
          debugPrint('Quick PIN silent Supabase reconnect warning: $e');
        }
      }

      if (SupabaseService.isInitialized &&
          _supabaseService.requiresMfaVerification() &&
          isTwoFactorPromptDue()) {
        _status = VaultLockStatus.mfaRequired;
      } else {
        _status = VaultLockStatus.unlocked;
        await _securityLogService.logEvent(
          SecurityEventType.pinUnlockSuccess,
          'Hızlı PIN ile kasa açıldı.',
        );
      }

      notifyListeners();
      return true;
    } catch (_) {
      final pinFails =
          (prefs.getInt(AppConstants.keyQuickPinFailedAttempts) ?? 0) + 1;
      await prefs.setInt(AppConstants.keyQuickPinFailedAttempts, pinFails);
      await _recordFailure('Hızlı PIN', 'Hatalı PIN kodu.');
      if (pinFails >= 3) {
        await disableQuickPin();
        _errorMessage =
            '3 kez hatalı PIN girildi. Güvenlik için Hızlı PIN devre dışı bırakıldı; ana parolanızı girin.';
      }
      notifyListeners();
      return false;
    } finally {
      CryptoService.wipe(wrappingKey);
    }
  }

  // --- Duress / Panic Password ---

  Future<bool> configureDuressPassword(String duressPassword) async {
    _errorMessage = null;
    if (!isUnlocked || _masterKey == null || _isDuressMode) {
      _errorMessage = 'Bu işlem için gerçek kasanızın kilidi açık olmalıdır.';
      notifyListeners();
      return false;
    }
    if (duressPassword.length < 6) {
      _errorMessage = 'Panik parolası en az 6 karakter olmalıdır.';
      notifyListeners();
      return false;
    }

    try {
      // Ensure duress password doesn't match the real master password
      if (_currentSalt != null && _currentSalt!.isNotEmpty) {
        final testReal = await _cryptoService.deriveMasterKey(
          duressPassword,
          _currentSalt!,
        );
        final isSame = CryptoService.constantTimeEquals(testReal, _masterKey!);
        CryptoService.wipe(testReal);
        if (isSame) {
          _errorMessage =
              'Panik parolası gerçek ana parolanızla aynı olamaz.';
          notifyListeners();
          return false;
        }
      }

      final duressSalt = _cryptoService.generateSalt(useArgon2id: true);
      final duressKey = await _cryptoService.deriveMasterKey(
        duressPassword,
        duressSalt,
      );
      final verifier = _cryptoService.deriveDuressVerifier(duressKey);
      CryptoService.wipe(duressKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyDuressSalt, duressSalt);
      await prefs.setString(AppConstants.keyDuressVerifier, verifier);
      await prefs.setBool(AppConstants.keyDuressEnabled, true);
      await prefs.remove(AppConstants.keyDuressEncryptedItems);

      _isDuressEnabled = true;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Panik parolası kaydedilemedi: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> disableDuressPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyDuressEnabled, false);
    await prefs.remove(AppConstants.keyDuressSalt);
    await prefs.remove(AppConstants.keyDuressVerifier);
    await prefs.remove(AppConstants.keyDuressEncryptedItems);
    _isDuressEnabled = false;
    notifyListeners();
  }

  // --- Pairing ---

  Future<PairingPayload> buildPairingPayload({
    required bool includeUnlockedKey,
  }) async {
    if (_isDuressMode) {
      throw Exception('Mevcut modda cihaz eşleştirme yapılamaz.');
    }
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(AppConstants.keyMasterSalt) ?? '';
    final email = _currentUserEmail ??
        prefs.getString(AppConstants.keyCachedEmail) ??
        '';
    final localItems = await OfflineStorageService.loadLocalItems();

    return PairingPayload(
      supabaseUrl: prefs.getString(AppConstants.keySupabaseUrl) ??
          AppConstants.defaultSupabaseUrl,
      supabaseAnonKey: prefs.getString(AppConstants.keySupabaseAnonKey) ??
          AppConstants.defaultSupabaseAnonKey,
      email: email,
      masterSalt: salt,
      masterKeyBase64: (includeUnlockedKey && _masterKey != null)
          ? base64Encode(_masterKey!)
          : null,
      offlineItems: localItems,
    );
  }

  Future<bool> completePairingSetup(PairingPayload payload) async {
    _errorMessage = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cleanEmail = payload.email.trim().toLowerCase();
      final prevSalt = prefs.getString(AppConstants.keyMasterSalt);

      if (payload.masterSalt.isNotEmpty) {
        if (prevSalt != null &&
            prevSalt.isNotEmpty &&
            prevSalt != payload.masterSalt) {
          await OfflineStorageService.clearLocal();
          await NativeBridgeService.clearAutofillIndex();
        }
        await prefs.setString(AppConstants.keyMasterSalt, payload.masterSalt);
        _currentSalt = payload.masterSalt;
      }
      if (cleanEmail.isNotEmpty) {
        await prefs.setString(AppConstants.keyCachedEmail, cleanEmail);
        _currentUserEmail = cleanEmail;
      }

      if (payload.supabaseUrl.trim().isNotEmpty &&
          payload.supabaseAnonKey.trim().isNotEmpty) {
        await SupabaseService.initialize(
          customUrl: payload.supabaseUrl.trim(),
          customAnonKey: payload.supabaseAnonKey.trim(),
        );
      }

      for (final rawItem in payload.offlineItems) {
        await OfflineStorageService.upsertLocalItem(
          rawItem,
          dirty: rawItem['dirty'] == true || rawItem['dirty'] == 1,
          baseHash: rawItem['base_hash']?.toString(),
        );
      }

      await _securityLogService.resetFailedAttempts();
      await _loadSecurityPreferences(prefs);

      if (payload.masterKeyBase64 != null &&
          payload.masterKeyBase64!.isNotEmpty) {
        final receivedKey = base64Decode(payload.masterKeyBase64!);
        CryptoService.wipe(_masterKey);
        _masterKey = receivedKey;
        _isDuressMode = false;

        if (SupabaseService.isInitialized && cleanEmail.isNotEmpty) {
          final authPassword = _cryptoService.deriveAuthPassword(receivedKey);
          try {
            await _supabaseService.signIn(
              email: cleanEmail,
              authPassword: authPassword,
            );
          } catch (signInErr) {
            debugPrint(
              'Pairing auto sign-in warning (continuing with local vault): $signInErr',
            );
          }
        }

        if (SupabaseService.isInitialized &&
            _supabaseService.requiresMfaVerification() &&
            isTwoFactorPromptDue()) {
          _status = VaultLockStatus.mfaRequired;
        } else {
          _status = VaultLockStatus.unlocked;
          await _securityLogService.logEvent(
            SecurityEventType.unlockSuccess,
            'Cihaz eşleştirme ile oturum ve kasa açıldı.',
          );
        }
      } else {
        _status = VaultLockStatus.lockedWithPass;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Eşleştirme uygulama hatası: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Password Change & Argon2id Upgrade ---

  Future<bool> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    required Future<void> Function(List<int> newMasterKey) onReEncryptVault,
    bool forceArgon2id = false,
  }) async {
    _errorMessage = null;
    if (!isUnlocked || _masterKey == null || _isDuressMode) {
      _errorMessage = 'Kasa kilidi açık değil.';
      notifyListeners();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentSalt = prefs.getString(AppConstants.keyMasterSalt);
    if (currentSalt == null || currentSalt.isEmpty) {
      _errorMessage = 'Mevcut şifre tuzu bulunamadı.';
      notifyListeners();
      return false;
    }

    final derivedCheck = await _cryptoService.deriveMasterKey(
      currentPassword,
      currentSalt,
    );
    final matches = CryptoService.constantTimeEquals(derivedCheck, _masterKey!);
    CryptoService.wipe(derivedCheck);
    if (!matches) {
      _errorMessage = 'Mevcut ana parolanız yanlış.';
      notifyListeners();
      return false;
    }

    if (newPassword.length < 8) {
      _errorMessage = 'Yeni ana parola en az 8 karakter olmalıdır.';
      notifyListeners();
      return false;
    }

    final useArgon =
        forceArgon2id || _preferArgon2id || CryptoService.isArgon2idSalt(currentSalt);
    final newSalt = _cryptoService.generateSalt(useArgon2id: useArgon);
    final newMasterKey = await _cryptoService.deriveMasterKey(
      newPassword,
      newSalt,
    );
    final newAuthPassword = _cryptoService.deriveAuthPassword(newMasterKey);

    try {
      await onReEncryptVault(newMasterKey);

      if (SupabaseService.isInitialized && SupabaseService.currentUser != null) {
        await _supabaseService.updateMasterSaltAndAuthPassword(
          newMasterSalt: newSalt,
          newAuthPassword: newAuthPassword,
        );
      }

      if (_isBiometricEnabled) {
        await _biometricService.enableBiometrics(newMasterKey);
      }

      // If Quick PIN is enabled, user should re-enroll or keep synced?
      // We can't recover the PIN without prompting, so safely disable or warn;
      // Wait: if Quick PIN was wrapping the OLD masterKey, decrypting with OLD key won't work anyway without PIN!
      if (_isQuickPinEnabled) {
        await disableQuickPin();
      }

      CryptoService.wipe(_masterKey);
      _masterKey = newMasterKey;
      _currentSalt = newSalt;
      await prefs.setString(AppConstants.keyMasterSalt, newSalt);

      await _securityLogService.logEvent(
        forceArgon2id
            ? SecurityEventType.kdfUpgradedToArgon2id
            : SecurityEventType.masterPasswordChanged,
        forceArgon2id
            ? 'Anahtar türetme Argon2id algoritmasına yükseltildi ve kasa yeniden şifrelendi.'
            : 'Ana parola değiştirildi ve tüm kasa yeniden şifrelendi.',
      );

      notifyListeners();
      return true;
    } catch (e) {
      CryptoService.wipe(newMasterKey);
      _errorMessage = 'Şifre değiştirme hatası: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> upgradeToArgon2id({
    required String currentPassword,
    required Future<void> Function(List<int> newMasterKey) onReEncryptVault,
  }) async {
    await setPreferArgon2id(true);
    return changeMasterPassword(
      currentPassword: currentPassword,
      newPassword: currentPassword,
      onReEncryptVault: onReEncryptVault,
      forceArgon2id: true,
    );
  }

  // --- Biometrics ---

  Future<bool> unlockWithBiometrics({bool isSilentAutoTrigger = false}) async {
    _errorMessage = null;
    if (await _checkLockoutBeforeAttempt()) {
      return false;
    }
    if (_biometricDisabledDueToFailures) {
      if (!isSilentAutoTrigger) {
        _errorMessage =
            'Üst üste hatalı denemeler nedeniyle biyometrik kilit geçici olarak devre dışı. Ana parolanızı girin.';
        notifyListeners();
      }
      return false;
    }

    try {
      final retrievedKey = await runWithoutAutoLock(
        () => _biometricService.retrieveBiometricMasterKey(),
      );
      if (retrievedKey != null) {
        await _securityLogService.resetFailedAttempts();
        final prefs = await SharedPreferences.getInstance();
        await _loadSecurityPreferences(prefs);

        _masterKey = retrievedKey;
        _isDuressMode = false;

        if (SupabaseService.isInitialized &&
            SupabaseService.currentUser == null &&
            _currentUserEmail != null &&
            _currentUserEmail!.isNotEmpty) {
          try {
            final authPass = _cryptoService.deriveAuthPassword(retrievedKey);
            await _supabaseService.signIn(
              email: _currentUserEmail!,
              authPassword: authPass,
            );
          } catch (e) {
            debugPrint('Biometric silent Supabase reconnect warning: $e');
          }
        }

        if (SupabaseService.isInitialized &&
            _supabaseService.requiresMfaVerification() &&
            isTwoFactorPromptDue()) {
          _status = VaultLockStatus.mfaRequired;
        } else {
          _status = VaultLockStatus.unlocked;
          await _securityLogService.logEvent(
            SecurityEventType.biometricSuccess,
            'Biyometrik doğrulama ile kasa açıldı.',
          );
        }
        notifyListeners();
        return true;
      }
      if (!isSilentAutoTrigger) {
        _errorMessage = 'Biyometrik doğrulama başarısız veya iptal edildi.';
        notifyListeners();
      }
      return false;
    } catch (e) {
      if (!isSilentAutoTrigger) {
        _errorMessage = 'Biyometrik kilit açılamadı.';
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> toggleBiometrics(bool enable) async {
    if (_isDuressMode) {
      _errorMessage = 'Bu işlem mevcut modda kullanılamaz.';
      notifyListeners();
      return false;
    }
    if (enable) {
      if (_masterKey == null) return false;
      final authenticated = await runWithoutAutoLock(
        () => _biometricService.authenticate(
          reason: 'Biyometrik kilit açmayı aktifleştirmek için onaylayın',
        ),
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
  }

  void lockVault({String reason = 'Kullanıcı veya otomatik zamanlayıcı tarafından kilitlendi.'}) {
    if (_status != VaultLockStatus.unlocked && _status != VaultLockStatus.mfaRequired) {
      return;
    }
    // Dismiss all active sub-routes, credential/card editors, dialogs back to root AuthScreen
    final nav = _navigatorKey ?? rootNavigatorKey;
    nav.currentState?.popUntil((route) => route.isFirst);

    CryptoService.wipe(_masterKey);
    _masterKey = null;
    _isDuressMode = false;
    _status = VaultLockStatus.lockedWithPass;
    _securityLogService.logEvent(SecurityEventType.vaultLocked, reason);

    // Clear decoded image memory buffers (QR codes, avatars, attachments)
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    // Flush native autofill index
    NativeBridgeService.clearAutofillIndex();

    // Pause centralized TOTP ticker
    TotpTickerService.instance.pause();

    // Advise runtime to clean old-generation garbage immediately
    try {
      WidgetsBinding.instance.handleMemoryPressure();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> logout() async {
    final nav = _navigatorKey ?? rootNavigatorKey;
    nav.currentState?.popUntil((route) => route.isFirst);

    CryptoService.wipe(_masterKey);
    _masterKey = null;
    _isDuressMode = false;
    await _biometricService.disableBiometrics();
    await disableQuickPin();
    await disableDuressPassword();
    _isBiometricEnabled = false;
    await _supabaseService.signOut();
    await OfflineStorageService.clearLocal();
    await NativeBridgeService.clearAutofillIndex();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyMasterSalt);
    await prefs.remove(AppConstants.keyCachedEmail);
    await prefs.remove(AppConstants.keyTwoFactorLastVerifiedIso);
    _currentUserEmail = null;
    _currentSalt = null;
    _hasVerifiedMfa = false;
    _twoFactorLastVerified = null;

    _status = VaultLockStatus.lockedWithPass;
    notifyListeners();
  }
}
