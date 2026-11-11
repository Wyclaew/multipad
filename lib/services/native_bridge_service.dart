import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridgeService {
  static const MethodChannel _channel =
      MethodChannel('com.multipad.multipad/native');

  static bool _initialized = false;
  static void Function()? _onQuickSearchRequested;
  static void Function()? _onLockVaultRequested;

  static Future<void> initialize({
    void Function()? onQuickSearchRequested,
    void Function()? onLockVaultRequested,
  }) async {
    _onQuickSearchRequested = onQuickSearchRequested;
    _onLockVaultRequested = onLockVaultRequested;
    if (_initialized || kIsWeb) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onQuickSearchRequested':
          _onQuickSearchRequested?.call();
          break;
        case 'onLockVaultRequested':
          _onLockVaultRequested?.call();
          break;
      }
      return null;
    });

    await _consumePendingLaunchAction();
  }

  static Future<void> _consumePendingLaunchAction() async {
    try {
      final action =
          await _channel.invokeMethod<String>('consumePendingLaunchAction');
      if (action == 'quick_search') {
        _onQuickSearchRequested?.call();
      }
    } on MissingPluginException {
      // Ignored on platforms without launch action support or in unit tests.
    } catch (e) {
      debugPrint('consumePendingLaunchAction error: $e');
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _onQuickSearchRequested = null;
    _onLockVaultRequested = null;
    _channel.setMethodCallHandler(null);
  }

  /// Toggles Android FLAG_SECURE (prevents screenshots & recent-apps thumbnail leaks).
  static Future<void> setFlagSecure(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setFlagSecure', {'enabled': enabled});
    } on MissingPluginException {
      // Ignored in tests or unsupported runners
    } catch (e) {
      debugPrint('setFlagSecure error: $e');
    }
  }

  /// Copies text using OS confidential/concealed pasteboard flags so clipboard history
  /// managers (Windows Clipboard History, macOS clipboard recorders, Android 13+) hide it.
  /// Returns true if native platform copy succeeded.
  static Future<bool> copyConfidential(String text) async {
    if (kIsWeb) return false;
    if (!(Platform.isAndroid || Platform.isMacOS || Platform.isWindows)) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'copyConfidential',
        {'text': text},
      );
      return result == true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('copyConfidential error: $e');
      return false;
    }
  }

  /// Acquires/releases Android WifiManager.MulticastLock so UDP LAN discovery works reliably.
  static Future<void> setMulticastLock(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setMulticastLock', {'enabled': enabled});
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('setMulticastLock error: $e');
    }
  }

  /// Configures macOS Menu Bar StatusItem / Windows System Tray + Global Hotkey (Cmd/Ctrl+Shift+Space).
  static Future<void> configureDesktopShell({
    required bool trayEnabled,
    required bool globalHotkeyEnabled,
  }) async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) return;
    try {
      await _channel.invokeMethod('configureDesktopShell', {
        'trayEnabled': trayEnabled,
        'globalHotkeyEnabled': globalHotkeyEnabled,
      });
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('configureDesktopShell error: $e');
    }
  }

  /// Brings app window forward cleanly when triggered via tray/hotkey.
  static Future<void> bringWindowToFront() async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) return;
    try {
      await _channel.invokeMethod('bringWindowToFront');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (_) {
      // Non-critical window focus helper.
    }
  }

  /// Pushes hardware-encrypted Android Autofill credential index (or empties it on lock).
  static Future<void> updateAutofillIndex(
    List<Map<String, String>> entries,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateAutofillIndex', {
        'entries': entries,
      });
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('updateAutofillIndex error: $e');
    }
  }

  static Future<void> clearAutofillIndex() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('clearAutofillIndex');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('clearAutofillIndex error: $e');
    }
  }

  static Future<void> openAndroidAutofillSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAutofillSettings');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('openAutofillSettings error: $e');
    }
  }

  /// Launches Android FileProvider package installer for downloaded APK.
  static Future<void> installAndroidApk(String apkPath) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod('installApk', {'path': apkPath});
  }
}
