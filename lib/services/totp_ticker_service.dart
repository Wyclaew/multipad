import 'dart:async';
import 'package:flutter/widgets.dart';

/// Centralized, lifecycle-aware broadcast TOTP ticker service.
///
/// Consolidates periodic 1-second ticks into a single stream, eliminating
/// per-widget timer proliferation and suspending CPU wakeups when the app
/// is backgrounded or when no subscribers are active.
class TotpTickerService with WidgetsBindingObserver {
  static final TotpTickerService instance = TotpTickerService._internal();
  factory TotpTickerService() => instance;

  Timer? _periodicTimer;
  Timer? _alignmentTimer;
  final StreamController<int> _controller = StreamController<int>.broadcast();
  bool _isPaused = false;
  bool _isAppInBackground = false;
  int _listenerCount = 0;

  TotpTickerService._internal() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  /// Broadcast stream emitting millisecond epoch timestamps on every 1-second tick.
  Stream<int> get tickStream {
    late StreamController<int> child;
    StreamSubscription<int>? parentSub;

    child = StreamController<int>(
      onListen: () {
        _listenerCount++;
        if (!_isPaused && !_isAppInBackground) {
          _startTimer();
        }
        parentSub = _controller.stream.listen(
          (val) {
            if (!child.isClosed) child.add(val);
          },
          onError: (err) {
            if (!child.isClosed) child.addError(err);
          },
          onDone: () {
            if (!child.isClosed) child.close();
          },
        );
      },
      onCancel: () {
        _listenerCount = (_listenerCount - 1).clamp(0, 999999);
        parentSub?.cancel();
        if (_listenerCount == 0) {
          _stopTimer();
        }
      },
    );
    return child.stream;
  }

  /// Subscribes a listener to the ticker stream with reference counting.
  StreamSubscription<int> subscribe(void Function(int) onTick) {
    return tickStream.listen(onTick);
  }

  void _startTimer() {
    if ((_periodicTimer != null && _periodicTimer!.isActive) ||
        (_alignmentTimer != null && _alignmentTimer!.isActive)) {
      return;
    }
    _emitTick();

    // Top-of-second clock alignment to ensure synchronicity with TOTP 30-second windows
    final now = DateTime.now();
    final msUntilNextSecond = (1000 - now.millisecond).clamp(1, 1000);
    _alignmentTimer = Timer(Duration(milliseconds: msUntilNextSecond), () {
      _alignmentTimer = null;
      if (!_isPaused && !_isAppInBackground && _listenerCount > 0) {
        _emitTick();
        _periodicTimer?.cancel();
        _periodicTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _emitTick(),
        );
      }
    });
  }

  void _stopTimer() {
    _alignmentTimer?.cancel();
    _alignmentTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void _emitTick() {
    if (!_controller.isClosed && _listenerCount > 0) {
      _controller.add(DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Pauses the ticker and cancels active timers (e.g. on backgrounding or vault lock).
  void pause() {
    _isPaused = true;
    _stopTimer();
  }

  /// Resumes the ticker if listeners are active and app is in foreground.
  void resume() {
    _isPaused = false;
    if (!_isAppInBackground && _listenerCount > 0) {
      _startTimer();
    }
  }

  /// Emits an immediate manual tick (useful in tests).
  void emitTick() {
    _emitTick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      if (!_isPaused && _listenerCount > 0) {
        _startTimer();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.hidden ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.detached) {
      _isAppInBackground = true;
      _stopTimer();
    }
  }

  /// Returns true if the internal periodic or alignment timer is currently active.
  bool get isRunning =>
      (_periodicTimer != null && _periodicTimer!.isActive) ||
      (_alignmentTimer != null && _alignmentTimer!.isActive);

  /// Returns true if the ticker is explicitly paused.
  bool get isPaused => _isPaused;

  /// Returns true if the app is currently in background.
  bool get isAppInBackground => _isAppInBackground;

  /// Number of currently active subscribers listening to the stream.
  int get activeSubscribers => _listenerCount;

  /// Resets internal test state.
  @visibleForTesting
  void resetForTesting() {
    _stopTimer();
    _isPaused = false;
    _isAppInBackground = false;
    _listenerCount = 0;
  }
}

