import 'dart:async';
import 'package:flutter/services.dart';
import 'native_bridge_service.dart';

class ClipboardService {
  static Timer? _clearTimer;
  static int _defaultTimeoutSeconds = 30;

  static void setDefaultTimeoutSeconds(int seconds) {
    _defaultTimeoutSeconds = seconds;
  }

  static int get defaultTimeoutSeconds => _defaultTimeoutSeconds;

  /// Copies [text] securely using native OS confidential clipboard flags when supported,
  /// and automatically clears the clipboard after [timeoutSeconds] (or user setting if omitted).
  /// Pass `0` to disable auto-clear.
  static Future<void> copySecurely(
    String text, {
    int? timeoutSeconds,
  }) async {
    final effectiveTimeout = timeoutSeconds ?? _defaultTimeoutSeconds;

    final handledNatively = await NativeBridgeService.copyConfidential(text);
    if (!handledNatively) {
      await Clipboard.setData(ClipboardData(text: text));
    }

    _clearTimer?.cancel();
    if (effectiveTimeout > 0) {
      _clearTimer = Timer(Duration(seconds: effectiveTimeout), () async {
        try {
          final ClipboardData? currentData =
              await Clipboard.getData(Clipboard.kTextPlain);
          if (currentData?.text == text) {
            await Clipboard.setData(const ClipboardData(text: ''));
          }
        } catch (_) {}
      });
    }
  }

  /// Cancels any scheduled clipboard clear.
  static void cancelScheduledClear() {
    _clearTimer?.cancel();
  }
}
