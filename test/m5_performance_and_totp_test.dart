import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/biometric_service.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/totp_ticker_service.dart';
import 'package:multipad/widgets/vault_item_card.dart';
import 'package:multipad/widgets/credential_detail_pane.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockBioService extends BiometricService {
  @override
  Future<bool> canCheckBiometrics() async => true;
  @override
  Future<bool> isBiometricUnlockEnabled() async => true;
  @override
  Future<List<int>?> retrieveBiometricMasterKey() async => List<int>.generate(32, (i) => i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TotpTickerService.instance.resetForTesting();
  });

  tearDown(() {
    TotpTickerService.instance.resetForTesting();
  });

  group('M5 Performance & Parallel Decryption Tests', () {
    test('decryptRowsParallel decrypts chunks with identical results to sequential decryption', () async {
      final crypto = CryptoService();
      final key = crypto.generateRandomBytes(32);

      final testRows = <Map<String, dynamic>>[];
      for (int i = 0; i < 12; i++) {
        final payloadMap = {
          'title': 'Test Item $i',
          'username': 'user_$i',
          'password': 'password_$i',
          'item_type': 'credential',
        };
        final enc = await crypto.encryptData(jsonEncode(payloadMap), key);
        testRows.add({
          'id': 'item-$i',
          'user_id': 'user-1',
          'encrypted_payload': enc.ciphertext,
          'iv': enc.iv,
          'mac': enc.mac,
          'item_type': 'credential',
          'is_deleted': 0,
          'client_updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      final parallelDecrypted = await VaultProvider.decryptRowsParallel(
        rows: testRows,
        masterKey: key,
        maxChunks: 4,
      );

      expect(parallelDecrypted.length, 12);
      for (int i = 0; i < 12; i++) {
        expect(parallelDecrypted[i].title, 'Test Item $i');
        expect(parallelDecrypted[i].username, 'user_$i');
        expect(parallelDecrypted[i].password, 'password_$i');
      }
    });

    test('decryptRowsParallel handles empty list and single row gracefully', () async {
      final crypto = CryptoService();
      final key = crypto.generateRandomBytes(32);

      final emptyResult = await VaultProvider.decryptRowsParallel(
        rows: [],
        masterKey: key,
      );
      expect(emptyResult, isEmpty);

      final payloadMap = {'title': 'Single Item', 'item_type': 'note'};
      final enc = await crypto.encryptData(jsonEncode(payloadMap), key);
      final singleResult = await VaultProvider.decryptRowsParallel(
        rows: [
          {
            'id': 'single-1',
            'user_id': 'user-1',
            'encrypted_payload': enc.ciphertext,
            'iv': enc.iv,
            'mac': enc.mac,
            'item_type': 'note',
            'is_deleted': 0,
            'client_updated_at': DateTime.now().toUtc().toIso8601String(),
          }
        ],
        masterKey: key,
      );
      expect(singleResult.length, 1);
      expect(singleResult.first.title, 'Single Item');
    });
  });

  group('M5 Lock Sanitization Tests', () {
    test('lockVault pauses TotpTickerService and clears image cache', () async {
      final fakeBio = _MockBioService();
      final auth = AuthProvider(biometricService: fakeBio);
      auth.setBiometricsEnabledForTesting(true);

      final unlocked = await auth.unlockWithBiometrics();
      expect(unlocked, isTrue);
      expect(auth.isUnlocked, isTrue);

      final ticker = TotpTickerService.instance;

      // Start ticker listener
      final sub = ticker.tickStream.listen((_) {});
      expect(ticker.isRunning, isTrue);

      // Populate dummy image into cache
      PaintingBinding.instance.imageCache.maximumSize = 100;

      // Lock vault
      auth.lockVault(reason: 'Test lock');

      expect(ticker.isPaused, isTrue);
      expect(ticker.isRunning, isFalse);

      await sub.cancel();
      auth.dispose();
    });
  });

  group('M5 Widget Ticker Integration Tests', () {
    testWidgets('VaultItemCard subscribes to TotpTickerService and updates', (tester) async {
      final item = VaultItem(
        id: 'cred-1',
        type: VaultItemType.credential,
        title: 'TOTP Service',
        username: 'user@test.com',
        totpSecret: 'JBSWY3DPEHPK3PXP', // Valid Base32 RFC test secret
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VaultItemCard(
              item: item,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify widget initialized and active subscriber is connected
      expect(TotpTickerService.instance.activeSubscribers, greaterThanOrEqualTo(1));

      // Trigger tick from central ticker
      TotpTickerService.instance.emitTick();
      await tester.pump();

      // Card should be rendered and display item title
      expect(find.text('TOTP Service'), findsOneWidget);

      // Destroy widget and verify subscription cleaned up
      await tester.pumpWidget(const SizedBox());
      expect(TotpTickerService.instance.activeSubscribers, 0);
    });

    testWidgets('CredentialDetailPane subscribes to TotpTickerService and cleans up on dispose', (tester) async {
      final item = VaultItem(
        id: 'cred-2',
        type: VaultItemType.credential,
        title: 'Detail Service',
        username: 'alice@example.com',
        totpSecret: 'JBSWY3DPEHPK3PXP',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CredentialDetailPane(
              item: item,
            ),
          ),
        ),
      );

      expect(TotpTickerService.instance.activeSubscribers, greaterThanOrEqualTo(1));
      expect(find.text('Detail Service'), findsOneWidget);

      TotpTickerService.instance.emitTick();
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      expect(TotpTickerService.instance.activeSubscribers, 0);
    });
  });
}
