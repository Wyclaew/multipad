import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/services/extension_installer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExtensionInstallerService', () {
    test('resolves extension directory and manifest paths', () {
      final dir = ExtensionInstallerService.getExtensionDirectoryPath();
      expect(dir, isNotNull);
      expect(dir, contains('extension'));

      final manifest = ExtensionInstallerService.getManifestPath();
      expect(manifest, isNotNull);
      expect(manifest, endsWith('manifest.json'));

      final xpi = ExtensionInstallerService.getXpiPath();
      expect(xpi, isNotNull);
      expect(xpi, endsWith('multipad-firefox.xpi'));
    });

    test('copyPathToClipboard stores valid path in system clipboard', () async {
      String? copiedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      });

      final successFirefox = await ExtensionInstallerService.copyPathToClipboard(isFirefox: true);
      expect(successFirefox, isTrue);
      expect(copiedText, contains('manifest.json'));

      final successChrome = await ExtensionInstallerService.copyPathToClipboard(isFirefox: false);
      expect(successChrome, isTrue);
      expect(copiedText, contains('extension'));
    });
  });
}
