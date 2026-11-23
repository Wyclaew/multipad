// MultiPad Global Configuration Constants

import 'package:flutter/material.dart';

class AppConstants {
  static const String appVersion = '1.4.1';
  static const int buildNumber = 5;

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
  static const String keyTwoFactorRepromptDays = 'multipad_2fa_reprompt_days'; // 30, 60, 90 (default: 30)
  static const String keyTwoFactorLastVerifiedIso = 'multipad_2fa_last_verified_iso';
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

/// Centralized Design System Tokens for Material 3 Theme Overhaul
class AppThemeConstants {
  // Brand & Slate/Indigo Palette
  static const Color indigoLight = Color(0xFF4338CA); // Deep indigo 700
  static const Color indigoDark = Color(0xFF818CF8);  // Vibrant indigo 400
  static const Color slateLight = Color(0xFF475569);  // Slate 600
  static const Color slateDark = Color(0xFF94A3B8);   // Slate 400

  // Surface Elevation Tiers - Light Mode
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFF8FAFC);
  static const Color lightSurfaceContainer = Color(0xFFF1F5F9);
  static const Color lightSurfaceContainerHigh = Color(0xFFE2E8F0);
  static const Color lightSurfaceContainerHighest = Color(0xFFCBD5E1);
  static const Color lightOutline = Color(0xFF94A3B8);
  static const Color lightOutlineVariant = Color(0xFFE2E8F0);

  // Surface Elevation Tiers - Dark Mode (Slate)
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceContainerLowest = Color(0xFF0B1120);
  static const Color darkSurfaceContainerLow = Color(0xFF131D31);
  static const Color darkSurfaceContainer = Color(0xFF1E293B);
  static const Color darkSurfaceContainerHigh = Color(0xFF27354E);
  static const Color darkSurfaceContainerHighest = Color(0xFF334155);
  static const Color darkOutline = Color(0xFF64748B);
  static const Color darkOutlineVariant = Color(0xFF334155);

  // Surface Elevation Tiers - AMOLED Pure Black Mode
  static const Color amoledBg = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF050508);
  static const Color amoledSurfaceContainerLowest = Color(0xFF000000);
  static const Color amoledSurfaceContainerLow = Color(0xFF0A0A0E);
  static const Color amoledSurfaceContainer = Color(0xFF111116);
  static const Color amoledSurfaceContainerHigh = Color(0xFF1A1A22);
  static const Color amoledSurfaceContainerHighest = Color(0xFF262630);
  static const Color amoledOutline = Color(0xFF3F3F46);
  static const Color amoledOutlineVariant = Color(0xFF27272A);

  // Monospace Typography Style for Sensitive Secrets & Codes
  static const String monospaceFontFamily = 'monospace';
  static const TextStyle secretTextStyle = TextStyle(
    fontFamily: monospaceFontFamily,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  );
}

