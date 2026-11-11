import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';

class SupabaseService {
  static SupabaseClient? _client;
  static bool _isInitialized = false;
  static bool _hasSdkInitialized = false;
  static String? _initializedUrl;
  static String? _initializedAnonKey;

  static SupabaseClient? get client => _client;
  static bool get isInitialized => _isInitialized;
  static User? get currentUser => _client?.auth.currentUser;

  /// Initializes Supabase with either saved configuration, constants, or user-supplied config.
  /// Supports clean dynamic re-initialization (e.g. during cross-device pairing).
  static Future<bool> initialize({String? customUrl, String? customAnonKey}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = (customUrl ??
              prefs.getString(AppConstants.keySupabaseUrl) ??
              AppConstants.defaultSupabaseUrl)
          .trim();
      final anonKey = (customAnonKey ??
              prefs.getString(AppConstants.keySupabaseAnonKey) ??
              AppConstants.defaultSupabaseAnonKey)
          .trim();

      if (url.isEmpty || anonKey.isEmpty) {
        _isInitialized = false;
        return false;
      }

      // If custom credentials were provided, save them
      if (customUrl != null && customAnonKey != null) {
        await prefs.setString(AppConstants.keySupabaseUrl, url);
        await prefs.setString(AppConstants.keySupabaseAnonKey, anonKey);
      }

      // Idempotent fast path if already initialized with same credentials
      if (_hasSdkInitialized &&
          _initializedUrl == url &&
          _initializedAnonKey == anonKey &&
          _client != null) {
        _isInitialized = true;
        return true;
      }

      // Dispose previous instance if switching projects dynamically
      if (_hasSdkInitialized) {
        try {
          await Supabase.instance.dispose();
        } catch (e) {
          debugPrint('Supabase dispose note: $e');
        }
        _hasSdkInitialized = false;
        _client = null;
      }

      await Supabase.initialize(
        url: url,
        publishableKey: anonKey,
        debug: kDebugMode,
      );

      _hasSdkInitialized = true;
      _initializedUrl = url;
      _initializedAnonKey = anonKey;
      _client = Supabase.instance.client;
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Supabase initialize error: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Check if user profile has a master_salt stored in Supabase
  Future<String?> fetchUserMasterSalt(String email) async {
    if (_client == null) return null;
    final cleanEmail = email.trim().toLowerCase();

    // 1. Primary method: call the Security Definer RPC function (works before authentication)
    try {
      final res = await _client!.rpc('get_user_salt', params: {'lookup_email': cleanEmail});
      if (res != null && res.toString().trim().isNotEmpty) {
        return res.toString().trim();
      }
    } catch (e) {
      debugPrint('RPC get_user_salt error (falling back to direct query): $e');
    }

    // 2. Direct query fallback
    try {
      final response = await _client!
          .from('user_profiles')
          .select('master_salt')
          .eq('email', cleanEmail)
          .maybeSingle();

      if (response != null && response['master_salt'] != null) {
        return response['master_salt'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('fetchUserMasterSalt direct query error: $e');
      return null;
    }
  }

  /// Sign up user with derived auth password and store master salt
  Future<AuthResponse> signUp({
    required String email,
    required String authPassword,
    required String masterSalt,
  }) async {
    if (_client == null) throw Exception('Supabase bağlantısı henüz yapılandırılmadı.');

    final cleanEmail = email.trim().toLowerCase();
    final response = await _client!.auth.signUp(
      email: cleanEmail,
      password: authPassword,
    );

    final user = response.user;
    if (user != null) {
      await _client!.from('user_profiles').upsert({
        'id': user.id,
        'email': cleanEmail,
        'master_salt': masterSalt,
      });
    }

    return response;
  }

  /// Sign in user with email and derived auth password
  Future<AuthResponse> signIn({
    required String email,
    required String authPassword,
  }) async {
    if (_client == null) throw Exception('Supabase bağlantısı henüz yapılandırılmadı.');
    return await _client!.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: authPassword,
    );
  }

  /// Updates user master salt and auth password in Supabase during password change
  Future<void> updateMasterSaltAndAuthPassword({
    required String newMasterSalt,
    required String newAuthPassword,
  }) async {
    if (_client == null || currentUser == null) return;

    await _client!.from('user_profiles').update({
      'master_salt': newMasterSalt,
    }).eq('id', currentUser!.id);

    await _client!.auth.updateUser(
      UserAttributes(password: newAuthPassword),
    );
  }

  /// Sign out local session (preserving other paired devices)
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    if (_client != null) {
      await _client!.auth.signOut(scope: scope);
    }
  }

  /// Revokes refresh tokens on all OTHER active devices while keeping the current session alive.
  Future<void> signOutOtherDevices() async {
    if (_client == null || currentUser == null) {
      throw Exception('Bulut oturumu aktif değil.');
    }
    await _client!.auth.signOut(scope: SignOutScope.others);
  }

  // --- Supabase Account-Level TOTP MFA ---

  /// Returns true when the current user has a verified TOTP factor and session is still aal1.
  bool requiresMfaVerification() {
    if (_client == null || currentUser == null) return false;
    final aal = _client!.auth.mfa.getAuthenticatorAssuranceLevel();
    return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
        aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
  }

  Future<List<Factor>> listTotpFactors() async {
    if (_client == null || currentUser == null) return [];
    final res = await _client!.auth.mfa.listFactors();
    return res.totp;
  }

  Future<List<Factor>> listAllMfaFactors() async {
    if (_client == null || currentUser == null) return [];
    final res = await _client!.auth.mfa.listFactors();
    return res.all;
  }

  Future<AuthMFAEnrollResponse> enrollTotpMfa({
    String friendlyName = 'MultiPad',
  }) async {
    if (_client == null || currentUser == null) {
      throw Exception('2FA etkinleştirmek için bulut oturumu açık olmalıdır.');
    }
    return await _client!.auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'MultiPad',
      friendlyName: friendlyName,
    );
  }

  Future<AuthMFAVerifyResponse> verifyTotpMfa({
    required String factorId,
    required String code,
  }) async {
    if (_client == null || currentUser == null) {
      throw Exception('Bulut oturumu aktif değil.');
    }
    return await _client!.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code.trim(),
    );
  }

  Future<void> unenrollMfa(String factorId) async {
    if (_client == null || currentUser == null) {
      throw Exception('Bulut oturumu aktif değil.');
    }
    await _client!.auth.mfa.unenroll(factorId);
  }

  /// Fetch all vault items (including deletion tombstones for accurate offline sync)
  Future<List<Map<String, dynamic>>> fetchVaultItems() async {
    if (_client == null || currentUser == null) return [];

    final response = await _client!
        .from('vault_items')
        .select()
        .eq('user_id', currentUser!.id)
        .order('client_updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Upsert an encrypted item
  Future<void> upsertVaultItem(Map<String, dynamic> itemMap) async {
    if (_client == null || currentUser == null) return;

    final dataToSave = Map<String, dynamic>.from(itemMap);
    dataToSave.remove('dirty');
    dataToSave.remove('base_hash');
    dataToSave['user_id'] = currentUser!.id;
    dataToSave['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _client!.from('vault_items').upsert(dataToSave);
  }

  /// Soft delete an item (tombstone) so that other devices sync the deletion
  Future<void> deleteVaultItem(String itemId) async {
    if (_client == null || currentUser == null) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _client!.from('vault_items').update({
      'is_deleted': true,
      'client_updated_at': nowIso,
      'updated_at': nowIso,
    }).eq('id', itemId).eq('user_id', currentUser!.id);
  }

  /// Listen to real-time changes on vault_items table
  RealtimeChannel? subscribeToVaultChanges(
    void Function(PostgresChangePayload payload) onData,
  ) {
    if (_client == null || currentUser == null) return null;

    final channel = _client!.channel('public:vault_items:${currentUser!.id}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vault_items',
          callback: onData,
        )
        .subscribe();

    return channel;
  }
}
