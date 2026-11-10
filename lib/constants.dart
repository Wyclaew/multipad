// MultiPad Global Configuration Constants

class AppConstants {
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
  static const String keyGlobalPasswordExpiryDays = 'multipad_global_password_expiry_days'; // 0 = off, 30, 60, 90, 180, 365

  // Crypto parameters
  static const int pbkdf2Iterations = 100000;
  static const int keyLength = 32; // 256-bit key for AES-GCM
}
