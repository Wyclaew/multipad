// MultiPad Global Configuration Constants

class AppConstants {
  static const String appVersion = '1.1.0';
  static const int buildNumber = 1;

  // Can be configured here or entered directly in the app's Setup / Settings screen.
  static const String defaultSupabaseUrl = '';
  static const String defaultSupabaseAnonKey = '';

  // Storage keys for flutter_secure_storage and shared_preferences
  static const String keySupabaseUrl = 'multipad_supabase_url';
  static const String keySupabaseAnonKey = 'multipad_supabase_anon_key';
  static const String keyMasterSalt = 'multipad_master_salt';
  static const String keyBiometricEnabled = 'multipad_biometric_enabled';
  static const String keyBiometricMasterKey = 'multipad_biometric_master_key';
  static const String keyCachedEmail = 'multipad_cached_email';
  static const String keyOfflineItems = 'multipad_offline_items';
  static const String keySqliteMigrated = 'multipad_sqlite_migrated_v1';
  static const String keyGlobalPasswordExpiryDays =
      'multipad_global_password_expiry_days'; // 0 = off, 30, 60, 90, 180, 365

  // Security & Privacy preferences
  static const String keyAutoLockMinutes = 'multipad_auto_lock_minutes'; // 0 = off, 1, 5, 15
  static const String keyLockOnBackground = 'multipad_lock_on_background';
  static const String keyFlagSecureEnabled = 'multipad_flag_secure_enabled';
  static const String keyClipboardTimeoutSeconds =
      'multipad_clipboard_timeout_seconds'; // 0 = off, 10, 30, 60
  static const String keyPreferArgon2id = 'multipad_prefer_argon2id';
  static const String keyQuickPinEnabled = 'multipad_quick_pin_enabled';
  static const String keyQuickPinWrappedMasterKey =
      'multipad_quick_pin_wrapped_mk';
  static const String keyQuickPinSalt = 'multipad_quick_pin_salt';
  static const String keyQuickPinFailedAttempts = 'multipad_quick_pin_fails';

  // Duress / Panic Vault
  static const String keyDuressEnabled = 'multipad_duress_enabled';
  static const String keyDuressSalt = 'multipad_duress_salt';
  static const String keyDuressVerifier = 'multipad_duress_verifier';
  static const String keyDuressEncryptedItems = 'multipad_duress_items';

  // Brute-force lockout & Security Log
  static const String keyFailedAttempts = 'multipad_failed_attempts';
  static const String keyLockoutUntilIso = 'multipad_lockout_until';
  static const String keyBiometricDisabledDueToFailures =
      'multipad_bio_temp_disabled';
  static const String keySecurityLogKey = 'multipad_security_log_key';

  // Appearance, Locale & Platform features
  static const String keyThemePreference =
      'multipad_theme_preference'; // system, light, dark, amoled
  static const String keyFontScale = 'multipad_font_scale';
  static const String keyLocaleCode = 'multipad_locale_code'; // system, tr, en
  static const String keyTrayEnabled = 'multipad_tray_enabled';
  static const String keyGlobalHotkeyEnabled = 'multipad_global_hotkey_enabled';
  static const String keyAutofillEnabled = 'multipad_autofill_enabled';

  // Crypto parameters
  static const int pbkdf2Iterations = 100000;
  static const int argon2MemoryKib = 19456; // 19 MiB (OWASP recommended)
  static const int argon2Iterations = 2;
  static const int argon2Parallelism = 1;
  static const int keyLength = 32; // 256-bit key for AES-GCM
}
