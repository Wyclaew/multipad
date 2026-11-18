import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/services/totp_ticker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TotpTickerService.instance.resetForTesting();
  });

  tearDown(() {
    TotpTickerService.instance.resetForTesting();
  });

  group('TotpTickerService Tests', () {
    test('instance is a singleton', () {
      final a = TotpTickerService.instance;
      final b = TotpTickerService();
      expect(identical(a, b), isTrue);
    });

    test('starts ticking when subscriber listens and stops when cancelled', () async {
      final service = TotpTickerService.instance;
      expect(service.isRunning, isFalse);
      expect(service.activeSubscribers, 0);

      final completer = Completer<int>();
      final sub = service.tickStream.listen((ms) {
        if (!completer.isCompleted) completer.complete(ms);
      });

      expect(service.activeSubscribers, 1);
      expect(service.isRunning, isTrue);

      final tick = await completer.future.timeout(const Duration(seconds: 3));
      expect(tick, greaterThan(0));

      await sub.cancel();
      expect(service.activeSubscribers, 0);
      expect(service.isRunning, isFalse);
    });

    test('multiple subscribers share the same ticker controller', () async {
      final service = TotpTickerService.instance;
      expect(service.activeSubscribers, 0);

      final sub1 = service.tickStream.listen((_) {});
      final sub2 = service.tickStream.listen((_) {});
      expect(service.activeSubscribers, 2);
      expect(service.isRunning, isTrue);

      await sub1.cancel();
      expect(service.activeSubscribers, 1);
      expect(service.isRunning, isTrue);

      await sub2.cancel();
      expect(service.activeSubscribers, 0);
      expect(service.isRunning, isFalse);
    });

    test('pause and resume control timer execution', () async {
      final service = TotpTickerService.instance;
      final sub = service.tickStream.listen((_) {});

      expect(service.isRunning, isTrue);
      expect(service.isPaused, isFalse);

      service.pause();
      expect(service.isPaused, isTrue);
      expect(service.isRunning, isFalse);

      service.resume();
      expect(service.isPaused, isFalse);
      expect(service.isRunning, isTrue);

      await sub.cancel();
    });

    test('lifecycle changes pause in background and resume in foreground', () async {
      final service = TotpTickerService.instance;
      final sub = service.tickStream.listen((_) {});

      expect(service.isRunning, isTrue);

      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.isAppInBackground, isTrue);
      expect(service.isRunning, isFalse);

      service.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(service.isAppInBackground, isTrue);
      expect(service.isRunning, isFalse);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.isAppInBackground, isFalse);
      expect(service.isRunning, isTrue);

      await sub.cancel();
    });

    test('manual emitTick broadcasts immediately', () async {
      final service = TotpTickerService.instance;
      final receivedTicks = <int>[];
      final sub = service.subscribe((tick) {
        receivedTicks.add(tick);
      });

      service.emitTick();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(receivedTicks.isNotEmpty, isTrue);

      await sub.cancel();
    });
  });
}
