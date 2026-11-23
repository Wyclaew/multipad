import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SplashScreen.debugDisableAnimations = false;
  });

  tearDown(() {
    SplashScreen.debugDisableAnimations = false;
  });

  group('SplashScreen Visuals & Interaction', () {
    testWidgets('renders brand typography, tagline, and animated progress', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Next Screen Content')),
            minDuration: Duration(milliseconds: 3000),
          ),
        ),
      );

      // Verify Brand Title & Subtitle
      expect(find.text('MultiPad'), findsOneWidget);
      expect(
        find.text('Sıfır-Bilgi Dijital Kasa & Kimlik Yöneticisi'),
        findsOneWidget,
      );
      expect(find.text('Kriptografik Bellek Başlatılıyor...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Advance time by 700ms -> triggers first status text change
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Donanım Anahtarlığı Doğrulanıyor...'), findsOneWidget);

      // Advance time by 600ms -> triggers second status text change
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Sıfır-Bilgi Kasası Hazır'), findsOneWidget);

      // Advance past minDuration -> navigates to nextScreen
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pumpAndSettle();
      expect(find.text('Next Screen Content'), findsOneWidget);
    });

    testWidgets('tapping screen skips splash screen immediately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Instant Target')),
            minDuration: Duration(milliseconds: 5000),
          ),
        ),
      );

      expect(find.text('MultiPad'), findsOneWidget);

      // Tap on screen to skip
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();

      expect(find.text('Instant Target'), findsOneWidget);
    });

    testWidgets('debugDisableAnimations bypasses splash screen directly', (tester) async {
      SplashScreen.debugDisableAnimations = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(
            nextScreen: Scaffold(body: Text('Direct Next Screen')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Direct Next Screen'), findsOneWidget);
    });
  });
}
