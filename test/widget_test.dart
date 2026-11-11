import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/main.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/settings_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/widgets/markdown_checklist_view.dart';
import 'package:multipad/widgets/quick_search_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('MarkdownChecklistView', () {
    test('toggleTaskAtLine toggles unchecked task to checked preserving indent', () {
      const src = '# Başlık\n  - [ ] Süt al\n- [x] Ekmek al\n';
      final updated = MarkdownChecklistView.toggleTaskAtLine(src, 1, true);
      expect(updated, '# Başlık\n  - [x] Süt al\n- [x] Ekmek al\n');

      final reverted = MarkdownChecklistView.toggleTaskAtLine(updated, 2, false);
      expect(reverted, '# Başlık\n  - [x] Süt al\n- [ ] Ekmek al\n');
    });

    test('toggleTaskAtLine ignores invalid indices safely', () {
      const src = '- [ ] Task 1';
      expect(MarkdownChecklistView.toggleTaskAtLine(src, -1, true), src);
      expect(MarkdownChecklistView.toggleTaskAtLine(src, 99, true), src);
    });

    testWidgets('renders checklist items and notifies toggle callback', (tester) async {
      int? toggledLine;
      bool? toggledChecked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownChecklistView(
              content: '## Alınacaklar\n- [ ] Kahve\n- [x] Şeker',
              onToggleChecklist: (lineIndex, checked) {
                toggledLine = lineIndex;
                toggledChecked = checked;
              },
            ),
          ),
        ),
      );

      expect(find.text('Kahve'), findsOneWidget);
      expect(find.text('Şeker'), findsOneWidget);

      await tester.tap(find.text('Kahve'));
      await tester.pump();
      expect(toggledLine, 1);
      expect(toggledChecked, isTrue);
    });
  });

  group('AppLocalizations & MultiPadApp', () {
    testWidgets('AppLocalizations switches cleanly between Turkish and English', (tester) async {
      late AppLocalizations trL10n;
      late AppLocalizations enL10n;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('tr'), Locale('en')],
          home: Builder(
            builder: (ctx) {
              trL10n = ctx.l10n;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(trL10n.isEnglish, isFalse);
      expect(trL10n.settings, 'Ayarlar');
      expect(trL10n.copiedWithTimeout('PIN', 10), contains('10 sn'));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('tr'), Locale('en')],
          home: Builder(
            builder: (ctx) {
              enL10n = ctx.l10n;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(enL10n.isEnglish, isTrue);
      expect(enL10n.settings, 'Settings');
      expect(enL10n.copiedWithTimeout('PIN', 0), contains('auto-clear disabled'));
    });

    testWidgets('QuickSearchDialog warns when vault is locked', (tester) async {
      final auth = AuthProvider();
      final vault = VaultProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: vault),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('tr'), Locale('en')],
            home: Scaffold(body: QuickSearchDialog()),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('locked'), findsOneWidget);
      expect(const MultiPadApp(), isA<MultiPadApp>());
    });
  });
}
