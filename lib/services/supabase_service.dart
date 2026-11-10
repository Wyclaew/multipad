import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants.dart';

class SupabaseService {
  static SupabaseClient? _client;
  static bool _isInitialized = false;

  static SupabaseClient? get client => _client;
  static bool get isInitialized => _isInitialized;
  static User? get currentUser => _client?.auth.currentUser;

  /// Initializes Supabase with either saved configuration, constants, or user-supplied config
  static Future<bool> initialize({String? customUrl, String? customAnonKey}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = customUrl ??
          prefs.getString(AppConstants.keySupabaseUrl) ??
          AppConstants.defaultSupabaseUrl;
      final anonKey = customAnonKey ??
          prefs.getString(AppConstants.keySupabaseAnonKey) ??
          AppConstants.defaultSupabaseAnonKey;

      if (url.trim().isEmpty || anonKey.trim().isEmpty) {
        _isInitialized = false;
        return false;
      }

      // If custom credentials were provided, save them
      if (customUrl != null && customAnonKey != null) {
        await prefs.setString(AppConstants.keySupabaseUrl, customUrl.trim());
        await prefs.setString(AppConstants.keySupabaseAnonKey, customAnonKey.trim());
      }

      await Supabase.initialize(
        url: url.trim(),
        anonKey: anonKey.trim(),
        debug: kDebugMode,
      );

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
      // Store user's salt in user_profiles
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

    // 1. Update master_salt in user_profiles
    await _client!.from('user_profiles').update({
      'master_salt': newMasterSalt,
    }).eq('id', currentUser!.id);

    // 2. Update Supabase Auth account password
    await _client!.auth.updateUser(
      UserAttributes(password: newAuthPassword),
    );
  }

  /// Sign out
  Future<void> signOut() async {
    if (_client != null) {
      await _client!.auth.signOut();
    }
  }

  /// Fetch all active vault items for the authenticated user
  Future<List<Map<String, dynamic>>> fetchVaultItems() async {
    if (_client == null || currentUser == null) return [];

    final response = await _client!
        .from('vault_items')
        .select()
        .eq('user_id', currentUser!.id)
        .eq('is_deleted', false)
        .order('client_updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Upsert an encrypted item
  Future<void> upsertVaultItem(Map<String, dynamic> itemMap) async {
    if (_client == null || currentUser == null) return;

    final dataToSave = Map<String, dynamic>.from(itemMap);
    dataToSave['user_id'] = currentUser!.id;
    dataToSave['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await _client!.from('vault_items').upsert(dataToSave);
  }

  /// Soft delete an item (tombstone) so that other devices sync the deletion
  Future<void> deleteVaultItem(String itemId) async {
    if (_client == null || currentUser == null) return;

    await _client!.from('vault_items').update({
      'is_deleted': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', itemId).eq('user_id', currentUser!.id);
  }

  /// Listen to real-time changes on vault_items table
  RealtimeChannel? subscribeToVaultChanges(void Function(PostgresChangePayload payload) onData) {
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
