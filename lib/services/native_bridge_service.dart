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
      final action = await _channel
          .invokeMethod<String>('consumePendingLaunchAction')
          .timeout(const Duration(milliseconds: 300));
      if (action == 'quick_search') {
        _onQuickSearchRequested?.call();
      }
    } on TimeoutException {
      // Ignored if platform does not respond promptly.
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

  /// Test override to simulate desktop platforms on Linux CI runners or headless tests.
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  /// Returns true if running on desktop (macOS, Windows, or Linux).
  static bool get isDesktopPlatform =>
      debugIsDesktopOverride ??
      (!kIsWeb &&
          (Platform.isMacOS || Platform.isWindows || Platform.isLinux));

  /// Configures macOS Menu Bar StatusItem / Windows System Tray + Global Hotkey (Cmd/Ctrl+Shift+Space).
  static Future<void> configureDesktopShell({
    required bool trayEnabled,
    required bool globalHotkeyEnabled,
  }) async {
    if (!isDesktopPlatform) return;
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
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('bringWindowToFront');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (_) {
      // Non-critical window focus helper.
    }
  }

  /// Minimizes the desktop window.
  static Future<void> windowMinimize() async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('windowMinimize');
    } on MissingPluginException {
      // Ignored in tests
    } catch (e) {
      debugPrint('windowMinimize error: $e');
    }
  }

  /// Toggles maximize / restore on the desktop window.
  static Future<void> windowMaximize() async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('windowMaximize');
    } on MissingPluginException {
      // Ignored in tests
    } catch (e) {
      debugPrint('windowMaximize error: $e');
    }
  }

  /// Closes the desktop window (honors tray preferences).
  static Future<void> windowClose() async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('windowClose');
    } on MissingPluginException {
      // Ignored in tests
    } catch (e) {
      debugPrint('windowClose error: $e');
    }
  }

  /// Checks if the desktop window is currently maximized.
  static Future<bool> isWindowMaximized() async {
    if (!isDesktopPlatform) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isWindowMaximized');
      return res ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Initiates native window dragging on mouse down.
  static Future<void> windowStartDragging() async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('windowStartDragging');
    } on MissingPluginException {
      // Ignored in tests
    } catch (e) {
      debugPrint('windowStartDragging error: $e');
    }
  }

  /// Pushes hardware-encrypted Android Autofill credential index (or empties it on lock).
  static Future<void> updateAutofillIndex(
    List<Map<String, String>> entries,
  ) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
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
    if (kIsWeb) return;
    if (!Platform.isAndroid &&
        !Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await _channel.invokeMethod('clearAutofillIndex');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('clearAutofillIndex error: $e');
    }
  }

  /// Retrieves credentials captured by Android Autofill while app was in background.
  static Future<List<Map<String, dynamic>>> getPendingAutofillCredentials() async {
    if (kIsWeb) return [];
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) {
      return [];
    }
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPendingAutofillCredentials');
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } on MissingPluginException {
      return [];
    } catch (e) {
      debugPrint('getPendingAutofillCredentials error: $e');
      return [];
    }
  }

  /// Clears pending autofill credentials after they have been processed or saved.
  static Future<void> clearPendingAutofillCredentials() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await _channel.invokeMethod('clearPendingAutofillCredentials');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('clearPendingAutofillCredentials error: $e');
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

  static Future<bool> isAccessibilityServiceEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return res ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on MissingPluginException {
      // Ignored when plugin channel is unavailable (e.g., tests).
    } catch (e) {
      debugPrint('openAccessibilitySettings error: $e');
    }
  }

  /// Launches Android FileProvider package installer for downloaded APK.
  static Future<void> installAndroidApk(String apkPath) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod('installApk', {'path': apkPath});
  }
}
