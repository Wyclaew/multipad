import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/main.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/widgets/desktop_title_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('com.multipad.multipad/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    DesktopTitleBar.debugIsMacOS = null;
    DesktopTitleBar.debugIsWindows = null;
  });

  tearDown(() {
    DesktopTitleBar.debugIsMacOS = null;
    DesktopTitleBar.debugIsWindows = null;
    messenger.setMockMethodCallHandler(nativeChannel, null);
  });

  group('NativeBridgeService Desktop Window Platform Channel', () {
    test('windowMinimize invokes platform channel', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        invokedMethod = call.method;
        return true;
      });

      await NativeBridgeService.windowMinimize();
      expect(invokedMethod, 'windowMinimize');
    });

    test('windowMaximize invokes platform channel', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        invokedMethod = call.method;
        return true;
      });

      await NativeBridgeService.windowMaximize();
      expect(invokedMethod, 'windowMaximize');
    });

    test('windowClose invokes platform channel', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        invokedMethod = call.method;
        return true;
      });

      await NativeBridgeService.windowClose();
      expect(invokedMethod, 'windowClose');
    });

    test('isWindowMaximized queries platform channel and parses boolean', () async {
      bool mockState = false;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'isWindowMaximized') {
          return mockState;
        }
        return null;
      });

      expect(await NativeBridgeService.isWindowMaximized(), isFalse);
      mockState = true;
      expect(await NativeBridgeService.isWindowMaximized(), isTrue);
    });

    test('windowStartDragging invokes platform channel', () async {
      String? invokedMethod;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        invokedMethod = call.method;
        return true;
      });

      await NativeBridgeService.windowStartDragging();
      expect(invokedMethod, 'windowStartDragging');
    });

    test('window methods catch MissingPluginException gracefully', () async {
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        throw MissingPluginException();
      });

      // None of these should throw
      await NativeBridgeService.windowMinimize();
      await NativeBridgeService.windowMaximize();
      await NativeBridgeService.windowClose();
      final isMax = await NativeBridgeService.isWindowMaximized();
      expect(isMax, isFalse);
      await NativeBridgeService.windowStartDragging();
    });
  });

  group('DesktopTitleBar macOS Mode', () {
    setUp(() {
      DesktopTitleBar.debugIsMacOS = true;
      DesktopTitleBar.debugIsWindows = false;
    });

    testWidgets('renders 78px traffic light reservation and branding', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Brand title & icon
      expect(find.text('MultiPad'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // Height check
      final titleBarFinder = find.byType(DesktopTitleBar);
      expect(titleBarFinder, findsOneWidget);
      final size = tester.getSize(titleBarFinder);
      expect(size.height, 38.0);

      // Traffic light spacer: 78.0px
      final spacerFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 78.0,
      );
      expect(spacerFinder, findsOneWidget);

      // Windows chrome buttons should NOT be rendered
      expect(find.byIcon(Icons.remove), findsNothing);
      expect(find.byIcon(Icons.crop_square), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('supports custom leading, title, and action widgets', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(
                  leading: Icon(Icons.star, key: Key('custom-lead')),
                  title: Text('Custom Title', key: Key('custom-title')),
                  actions: [Icon(Icons.settings, key: Key('custom-action'))],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-lead')), findsOneWidget);
      expect(find.byKey(const Key('custom-title')), findsOneWidget);
      expect(find.byKey(const Key('custom-action')), findsOneWidget);
    });

    testWidgets('gesture detector initiates window drag on pan start and maximize on double tap', (tester) async {
      final List<String> channelCalls = [];
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        channelCalls.add(call.method);
        if (call.method == 'isWindowMaximized') return false;
        return true;
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final brandFinder = find.text('MultiPad');
      // Drag/pan start
      final gesture = await tester.startGesture(tester.getCenter(brandFinder));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(channelCalls, contains('windowStartDragging'));

      // Double tap to maximize
      await tester.tap(brandFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(brandFinder);
      await tester.pumpAndSettle();

      expect(channelCalls, contains('windowMaximize'));
    });
  });

  group('DesktopTitleBar Windows Mode', () {
    setUp(() {
      DesktopTitleBar.debugIsMacOS = false;
      DesktopTitleBar.debugIsWindows = true;
    });

    testWidgets('renders Windows chrome buttons without 78px spacer', (tester) async {
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'isWindowMaximized') return false;
        return true;
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No 78px spacer on Windows
      final spacerFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 78.0,
      );
      expect(spacerFinder, findsNothing);

      // Windows buttons present
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('clicking Windows minimize, maximize, and close invokes native channel', (tester) async {
      final List<String> channelCalls = [];
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        channelCalls.add(call.method);
        if (call.method == 'isWindowMaximized') return false;
        return true;
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap minimize
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(channelCalls, contains('windowMinimize'));

      // Tap maximize
      await tester.tap(find.byIcon(Icons.crop_square));
      await tester.pumpAndSettle();
      expect(channelCalls, contains('windowMaximize'));

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(channelCalls, contains('windowClose'));
    });

    testWidgets('displays restore icon when window is maximized', (tester) async {
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'isWindowMaximized') return true; // Window is zoomed/maximized
        return true;
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Maximize icon changes to restore (filter_none)
      expect(find.byIcon(Icons.filter_none), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsNothing);
    });

    testWidgets('close button hover effect applies red background', (tester) async {
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'isWindowMaximized') return false;
        return true;
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeBtnFinder = find.byIcon(Icons.close);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(closeBtnFinder));
      await tester.pumpAndSettle();

      // Check red hover color container
      final redContainerFinder = find.byWidgetPredicate(
        (w) => w is Container && w.color == const Color(0xFFE81123),
      );
      expect(redContainerFinder, findsOneWidget);

      await gesture.removePointer();
    });
  });

  group('DesktopTitleBar Non-Desktop Immunity', () {
    setUp(() {
      DesktopTitleBar.debugIsMacOS = false;
      DesktopTitleBar.debugIsWindows = false;
    });

    testWidgets('renders SizedBox.shrink with 0 dimensions on non-desktop platforms', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                DesktopTitleBar(),
                Text('Content Below'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should be completely invisible and 0-sized
      final shrinkFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 0.0 && w.height == 0.0,
      );
      expect(shrinkFinder, findsOneWidget);
      expect(find.text('MultiPad'), findsNothing);
      expect(find.text('Content Below'), findsOneWidget);
    });
  });

  group('Shell Integration in MultiPadApp', () {
    testWidgets('renders DesktopTitleBar permanently across app lifecycle shell', (tester) async {
      DesktopTitleBar.debugIsMacOS = true;
      DesktopTitleBar.debugIsWindows = false;

      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'isWindowMaximized') return false;
        if (call.method == 'consumePendingLaunchAction') return null;
        return true;
      });

      await tester.pumpWidget(
        MultiPadApp(
          authProvider: auth,
          vaultProvider: vault,
          settingsProvider: settings,
        ),
      );
      await tester.pumpAndSettle();

      // Title bar is present in AuthScreen (vault locked)
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(find.text('MultiPad'), findsWidgets);
    });
  });
}
