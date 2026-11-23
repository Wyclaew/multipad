import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('com.multipad.multipad/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(nativeChannel, null);
  });

  group('Autofill Index Lock Preservation & Duress Wiping', () {
    test('does not invoke clearAutofillIndex when vault locks while autofill is enabled', () async {
      bool clearInvoked = false;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'clearAutofillIndex') {
          clearInvoked = true;
        }
        return true;
      });

      final vault = VaultProvider();
      vault.setItemsForTesting([
        VaultItem(
          id: 'cred-1',
          title: 'Google Account',
          type: VaultItemType.credential,
          website: 'https://accounts.google.com',
          username: 'test@gmail.com',
          password: 'SecretPassword123!',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
      ]);

      // Locking vault should NOT wipe the Android Keystore encrypted autofill index
      vault.lockVault();
      expect(clearInvoked, isFalse);
    });

    test('syncAutofillIndex clears cache when autofill is explicitly disabled', () async {
      bool clearInvoked = false;
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'clearAutofillIndex') {
          clearInvoked = true;
        }
        return true;
      });

      final vault = VaultProvider();
      await vault.syncAutofillIndex(false);
      expect(clearInvoked, isTrue);
    });
  });
}
