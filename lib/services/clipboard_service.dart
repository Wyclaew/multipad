import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardService {
  static Timer? _clearTimer;

  /// Copies text to clipboard and automatically clears it after [timeoutSeconds] seconds for security.
  static Future<void> copySecurely(String text, {int timeoutSeconds = 30}) async {
    await Clipboard.setData(ClipboardData(text: text));

    _clearTimer?.cancel();
    _clearTimer = Timer(Duration(seconds: timeoutSeconds), () async {
      final ClipboardData? currentData = await Clipboard.getData(Clipboard.kTextPlain);
      if (currentData?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  /// Cancels any scheduled clipboard clear
  static void cancelScheduledClear() {
    _clearTimer?.cancel();
  }
}
