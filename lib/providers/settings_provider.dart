import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/clipboard_service.dart';
import '../services/native_bridge_service.dart';

enum AppThemePreference {
  system,
  light,
  dark,
  amoled,
}

class SettingsProvider extends ChangeNotifier {
  static bool get defaultLockOnBackground {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  AppThemePreference _themePreference = AppThemePreference.system;
  double _fontScale = 1.0;
  String _localeCode = 'system'; // 'system', 'tr', 'en'

  int _autoLockMinutes = 5; // 0 = off, 1, 5, 15
  bool _lockOnBackground = defaultLockOnBackground;
  bool _flagSecureEnabled = true;
  int _clipboardTimeoutSeconds = 30; // 0 = off, 10, 30, 60
  int _twoFactorRepromptDays = 30; // 30, 60, 90 (default: 30)

  bool _trayEnabled = true;
  bool _globalHotkeyEnabled = true;
  bool _autofillEnabled = false;
  int _globalExpiryDays = 0;

  bool _loaded = false;

  AppThemePreference get themePreference => _themePreference;
  double get fontScale => _fontScale;
  String get localeCode => _localeCode;
  int get autoLockMinutes => _autoLockMinutes;
  bool get lockOnBackground => _lockOnBackground;
  bool get flagSecureEnabled => _flagSecureEnabled;
  int get clipboardTimeoutSeconds => _clipboardTimeoutSeconds;
  int get twoFactorRepromptDays => _twoFactorRepromptDays;
  bool get trayEnabled => _trayEnabled;
  bool get globalHotkeyEnabled => _globalHotkeyEnabled;
  bool get autofillEnabled => _autofillEnabled;
  int get globalExpiryDays => _globalExpiryDays;
  bool get isLoaded => _loaded;

  ThemeMode get themeMode {
    switch (_themePreference) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
      case AppThemePreference.amoled:
        return ThemeMode.dark;
      case AppThemePreference.system:
        return ThemeMode.system;
    }
  }

  bool get isAmoledBlack => _themePreference == AppThemePreference.amoled;

  Locale? get locale {
    if (_localeCode == 'tr') return const Locale('tr');
    if (_localeCode == 'en') return const Locale('en');
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeRaw = prefs.getString(AppConstants.keyThemePreference) ?? 'system';
    _themePreference = AppThemePreference.values.firstWhere(
      (e) => e.name == themeRaw,
      orElse: () => AppThemePreference.system,
    );
    _fontScale =
        (prefs.getDouble(AppConstants.keyFontScale) ?? 1.0).clamp(0.85, 1.35);
    _localeCode = prefs.getString(AppConstants.keyLocaleCode) ?? 'system';

    _autoLockMinutes = prefs.getInt(AppConstants.keyAutoLockMinutes) ?? 5;
    _lockOnBackground =
        prefs.getBool(AppConstants.keyLockOnBackground) ?? defaultLockOnBackground;
    _flagSecureEnabled =
        prefs.getBool(AppConstants.keyFlagSecureEnabled) ?? true;
    _clipboardTimeoutSeconds =
        prefs.getInt(AppConstants.keyClipboardTimeoutSeconds) ?? 30;
    _twoFactorRepromptDays =
        prefs.getInt(AppConstants.keyTwoFactorRepromptDays) ?? 30;

    _trayEnabled = prefs.getBool(AppConstants.keyTrayEnabled) ?? true;
    _globalHotkeyEnabled =
        prefs.getBool(AppConstants.keyGlobalHotkeyEnabled) ?? true;
    _autofillEnabled = prefs.getBool(AppConstants.keyAutofillEnabled) ?? false;
    _globalExpiryDays =
        prefs.getInt(AppConstants.keyGlobalPasswordExpiryDays) ?? 0;

    ClipboardService.setDefaultTimeoutSeconds(_clipboardTimeoutSeconds);
    await NativeBridgeService.setFlagSecure(_flagSecureEnabled);
    await NativeBridgeService.configureDesktopShell(
      trayEnabled: _trayEnabled,
      globalHotkeyEnabled: _globalHotkeyEnabled,
    );

    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemePreference(AppThemePreference pref) async {
    _themePreference = pref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyThemePreference, pref.name);
    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale.clamp(0.85, 1.35);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(AppConstants.keyFontScale, _fontScale);
    notifyListeners();
  }

  Future<void> setLocaleCode(String code) async {
    _localeCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyLocaleCode, code);
    notifyListeners();
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _autoLockMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyAutoLockMinutes, minutes);
    notifyListeners();
  }

  Future<void> setLockOnBackground(bool enabled) async {
    _lockOnBackground = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyLockOnBackground, enabled);
    notifyListeners();
  }

  Future<void> setFlagSecureEnabled(bool enabled) async {
    _flagSecureEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyFlagSecureEnabled, enabled);
    await NativeBridgeService.setFlagSecure(enabled);
    notifyListeners();
  }

  Future<void> setClipboardTimeoutSeconds(int seconds) async {
    _clipboardTimeoutSeconds = seconds;
    ClipboardService.setDefaultTimeoutSeconds(seconds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyClipboardTimeoutSeconds, seconds);
    notifyListeners();
  }

  Future<void> setTwoFactorRepromptDays(int days) async {
    _twoFactorRepromptDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyTwoFactorRepromptDays, days);
    notifyListeners();
  }

  Future<void> setTrayEnabled(bool enabled) async {
    _trayEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyTrayEnabled, enabled);
    await NativeBridgeService.configureDesktopShell(
      trayEnabled: _trayEnabled,
      globalHotkeyEnabled: _globalHotkeyEnabled,
    );
    notifyListeners();
  }

  Future<void> setGlobalHotkeyEnabled(bool enabled) async {
    _globalHotkeyEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyGlobalHotkeyEnabled, enabled);
    await NativeBridgeService.configureDesktopShell(
      trayEnabled: _trayEnabled,
      globalHotkeyEnabled: _globalHotkeyEnabled,
    );
    notifyListeners();
  }

  Future<void> setAutofillEnabled(bool enabled) async {
    _autofillEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyAutofillEnabled, enabled);
    if (!enabled) {
      await NativeBridgeService.clearAutofillIndex();
    }
    notifyListeners();
  }

  Future<void> setGlobalExpiryDays(int days) async {
    _globalExpiryDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyGlobalPasswordExpiryDays, days);
    notifyListeners();
  }
}
