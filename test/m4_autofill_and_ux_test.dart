import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/services/clipboard_service.dart';
import 'package:multipad/services/database_service.dart';
import 'package:multipad/services/native_bridge_service.dart';
import 'package:multipad/widgets/credential_detail_pane.dart';
import 'package:multipad/widgets/password_generator_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrapWithLocalization(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'),
      Locale('tr'),
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ClipboardService.setDefaultTimeoutSeconds(30);
    NativeBridgeService.resetForTesting();
    tempDir = Directory.systemTemp.createTempSync('multipad_m4_test_');
    DatabaseService.configureForTesting(
      dbPath: p.join(tempDir.path, 'm4_test.db'),
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('VaultItemType Expansion & CustomFieldType', () {
    test('expands VaultItemType to include bankAccount, server, database, cryptoWallet', () {
      expect(VaultItemType.bankAccount.storageKey, 'bankAccount');
      expect(VaultItemType.server.storageKey, 'server');
      expect(VaultItemType.database.storageKey, 'database');
      expect(VaultItemType.cryptoWallet.storageKey, 'cryptoWallet');

      expect(VaultItem.typeFromString('bankAccount'), VaultItemType.bankAccount);
      expect(VaultItem.typeFromString('bank_account'), VaultItemType.bankAccount);
      expect(VaultItem.typeFromString('server'), VaultItemType.server);
      expect(VaultItem.typeFromString('database'), VaultItemType.database);
      expect(VaultItem.typeFromString('cryptoWallet'), VaultItemType.cryptoWallet);
      expect(VaultItem.typeFromString('crypto_wallet'), VaultItemType.cryptoWallet);
    });

    test('typeFromString falls back to VaultItemType.note on unknown types', () {
      expect(VaultItem.typeFromString('unknown_type_xyz'), VaultItemType.note);
      expect(VaultItem.typeFromString(''), VaultItemType.note);
      expect(VaultItem.typeFromString('arbitrary'), VaultItemType.note);
    });

    test('CustomField supports all 7 types with full backward compatibility', () {
      const text = CustomField(id: '1', label: 'K1', value: 'V1', type: CustomFieldType.text);
      expect(text.type, CustomFieldType.text);
      expect(text.isHidden, false);

      const hidden = CustomField(id: '2', label: 'K2', value: 'V2', type: CustomFieldType.hidden);
      expect(hidden.type, CustomFieldType.hidden);
      expect(hidden.isHidden, true);

      const boolean = CustomField(id: '3', label: 'K3', value: 'true', type: CustomFieldType.boolean);
      expect(boolean.type, CustomFieldType.boolean);

      const url = CustomField(id: '4', label: 'K4', value: 'https://multipad.dev', type: CustomFieldType.url);
      expect(url.type, CustomFieldType.url);

      const email = CustomField(id: '5', label: 'K5', value: 'test@multipad.dev', type: CustomFieldType.email);
      expect(email.type, CustomFieldType.email);

      const date = CustomField(id: '6', label: 'K6', value: '2026-11-18', type: CustomFieldType.date);
      expect(date.type, CustomFieldType.date);

      const otp = CustomField(id: '7', label: 'K7', value: 'JBSWY3DPEHPK3PXP', type: CustomFieldType.otp);
      expect(otp.type, CustomFieldType.otp);

      // Backward compatibility fromJson: missing type infers from isHidden
      final legacyHidden = CustomField.fromJson({'id': '8', 'label': 'OldKey', 'value': 'OldVal', 'isHidden': true});
      expect(legacyHidden.type, CustomFieldType.hidden);
      expect(legacyHidden.isHidden, true);

      final legacyNormal = CustomField.fromJson({'id': '9', 'label': 'OldKey2', 'value': 'OldVal2', 'isHidden': false});
      expect(legacyNormal.type, CustomFieldType.text);
      expect(legacyNormal.isHidden, false);

      // toJson includes both type and isHidden for backward compatibility
      final map = otp.toJson();
      expect(map['type'], 'otp');
      expect(map['isHidden'], false);
    });

    test('VaultItem serialization & deserialization with new fields', () {
      final now = DateTime.now();
      final item = VaultItem(
        id: 'test-bank-1',
        title: 'Main Bank Account',
        type: VaultItemType.bankAccount,
        bankName: 'Acme Bank',
        bankIban: 'TR980006100512345678901234',
        bankAccountNumber: '12345678',
        bankRoutingNumber: '00061',
        serverHost: 'db.internal.lan',
        serverPort: '5432',
        serverUsername: 'admin',
        databaseName: 'production',
        databaseType: 'PostgreSQL',
        cryptoWalletAddress: '0x71C...B29',
        cryptoNetwork: 'Ethereum Mainnet',
        cryptoSeedPhrase: 'apple banana cherry dog elephant fox grape horse igloo jaguar kite lemon',
        customFields: const [
          CustomField(id: 'cf-1', label: 'SWIFT', value: 'ACMETR2A', type: CustomFieldType.text),
        ],
        updatedAt: now,
      );

      final jsonString = item.toPlainJson();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(json['bankName'], 'Acme Bank');
      expect(json['bankIban'], 'TR980006100512345678901234');
      expect(json['bankRoutingNumber'], '00061');
      expect(json['serverHost'], 'db.internal.lan');
      expect(json['serverPort'], '5432');
      expect(json['databaseName'], 'production');
      expect(json['cryptoWalletAddress'], '0x71C...B29');

      final reconstructed = VaultItem.fromDecryptedJson(
        id: item.id,
        type: item.type,
        decryptedPayload: json,
        isDeleted: false,
        clientUpdatedAt: now,
        updatedAt: item.updatedAt,
      );

      expect(reconstructed.type, VaultItemType.bankAccount);
      expect(reconstructed.bankName, 'Acme Bank');
      expect(reconstructed.bankIban, 'TR980006100512345678901234');
      expect(reconstructed.bankAccountNumber, '12345678');
      expect(reconstructed.serverHost, 'db.internal.lan');
      expect(reconstructed.serverPort, '5432');
      expect(reconstructed.databaseName, 'production');
      expect(reconstructed.databaseType, 'PostgreSQL');
      expect(reconstructed.cryptoWalletAddress, '0x71C...B29');
      expect(reconstructed.cryptoSeedPhrase, item.cryptoSeedPhrase);
      expect(reconstructed.customFields.length, 1);
      expect(reconstructed.customFields.first.label, 'SWIFT');
    });
  });

  group('ISO 7064 Mod-97 IBAN Validator', () {
    test('validates standard Turkish IBAN', () {
      expect(IbanValidator.isValid('TR980006100512345678901234'), true);
      expect(IbanValidator.isValid('TR98 0006 1005 1234 5678 9012 34'), true);
      expect(IbanValidator.isValid('tr98-0006-1005-1234-5678-9012-34'), true);
    });

    test('validates standard UK & German test IBANs', () {
      expect(IbanValidator.isValid('GB82WEST12345698765432'), true);
      expect(IbanValidator.isValid('DE89370400440532013000'), true);
    });

    test('rejects invalid checksums and invalid lengths', () {
      // Changed check digit from 98 to 97
      expect(IbanValidator.isValid('TR970006100512345678901234'), false);
      // Too short
      expect(IbanValidator.isValid('TR9800061005'), false);
      // Invalid country characters
      expect(IbanValidator.isValid('12980006100512345678901234'), false);
      // Empty or garbage
      expect(IbanValidator.isValid(''), false);
      expect(IbanValidator.isValid('NOT AN IBAN'), false);
    });

    test('enforces ISO 13616 prefix: rejects all-numeric and ill-formed prefixes even if mod 97 matches', () {
      // 009800000000000: 15 chars, BigInt % 97 == 1, but starts with digits '00'
      expect(IbanValidator.isValid('009800000000000'), false);
      expect(IbanValidator.isValid('123456789012345'), false);
      expect(IbanValidator.isValid('T1980006100512345678901234'), false);
      expect(IbanValidator.isValid('TRA80006100512345678901234'), false);
    });

    test('formats IBAN with clean 4-character grouping', () {
      final formatted = IbanValidator.format('TR980006100512345678901234');
      expect(formatted, 'TR98 0006 1005 1234 5678 9012 34');
    });

    test('VaultItem.isValidIban and isIbanValid helper methods', () {
      final validItem = VaultItem(
        id: '1',
        title: 'Valid IBAN Item',
        type: VaultItemType.bankAccount,
        bankIban: 'TR980006100512345678901234',
      );
      expect(validItem.isIbanValid, true);
      expect(VaultItem.isValidIban(validItem.bankIban), true);

      final invalidItem = VaultItem(
        id: '2',
        title: 'Invalid IBAN Item',
        type: VaultItemType.bankAccount,
        bankIban: 'TR000000000000000000000000',
      );
      expect(invalidItem.isIbanValid, false);
      expect(VaultItem.isValidIban(invalidItem.bankIban), false);
    });
  });

  group('EFF Diceware Wordlist & Generator Engine', () {
    test('EFF Diceware wordlist contains exactly 7,776 words', () {
      expect(EFFWordlist.words.length, 7776);
      expect(EFFWordlist.words.first, isNotEmpty);
      expect(EFFWordlist.words.last, isNotEmpty);
      expect(EFFWordlist.words.toSet().length, 7776); // all unique
    });

    test('generatePassphrase produces requested word count with custom separator', () {
      final passphrase4 = EFFWordlist.generatePassphrase(
        wordCount: 4,
        separator: '-',
      );
      final parts4 = passphrase4.split('-');
      expect(parts4.length, 4);
      for (final part in parts4) {
        expect(EFFWordlist.words.contains(part), true);
      }

      final passphrase6Dot = EFFWordlist.generatePassphrase(
        wordCount: 6,
        separator: '.',
      );
      final parts6 = passphrase6Dot.split('.');
      expect(parts6.length, 6);
      for (final part in parts6) {
        expect(EFFWordlist.words.contains(part), true);
      }
    });

    test('entropy calculation for EFF Diceware is ~12.92 bits per word', () {
      final bits4 = EFFWordlist.calculateEntropy(wordCount: 4);
      expect(bits4, closeTo(51.69, 0.1));

      final bits6 = EFFWordlist.calculateEntropy(wordCount: 6);
      expect(bits6, closeTo(77.54, 0.1));
    });
  });

  group('Password Generator Ring Buffer History', () {
    test('records generated passwords and maintains FIFO ring buffer of 50', () {
      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history.isEmpty, true);

      final now = DateTime.now();
      for (int i = 1; i <= 60; i++) {
        PasswordGeneratorDialog.recordGeneration(
          GeneratedPasswordRecord(
            password: 'password_$i',
            mode: 'passphrase',
            entropyBits: 50.0,
            timestamp: now,
          ),
        );
      }

      expect(PasswordGeneratorDialog.history.length, 50);
      // Newest should be password_60 at index 0
      expect(PasswordGeneratorDialog.history.first.password, 'password_60');
      // Oldest retained should be password_11 (1-10 evicted)
      expect(PasswordGeneratorDialog.history.last.password, 'password_11');

      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history.isEmpty, true);
    });
  });

  group('VaultProvider Sorting & Structured Search Tokens', () {
    test('A-Z and Z-A case-insensitive title sorting', () {
      final vault = VaultProvider();
      final now = DateTime.now();

      final itemA = VaultItem(id: '1', title: 'apple', type: VaultItemType.credential, updatedAt: now);
      final itemB = VaultItem(id: '2', title: 'Banana', type: VaultItemType.credential, updatedAt: now);
      final itemC = VaultItem(id: '3', title: 'cherry', type: VaultItemType.credential, updatedAt: now);

      vault.setItemsForTesting([itemB, itemC, itemA]);

      vault.setSortOrder(VaultSortOrder.az);
      var items = vault.filteredItems;
      expect(items.map((i) => i.title).toList(), ['apple', 'Banana', 'cherry']);

      vault.setSortOrder(VaultSortOrder.za);
      items = vault.filteredItems;
      expect(items.map((i) => i.title).toList(), ['cherry', 'Banana', 'apple']);
    });

    test('structured search tokens: type:, is:favorite, is:trash, has:totp, tag:', () {
      final vault = VaultProvider();
      final now = DateTime.now();

      final cred = VaultItem(
        id: '1',
        title: 'GitHub Login',
        username: 'user@github.com',
        type: VaultItemType.credential,
        totpSecret: 'JBSWY3DPEHPK3PXP',
        isFavorite: true,
        tags: ['dev', 'git'],
        updatedAt: now,
      );

      final bank = VaultItem(
        id: '2',
        title: 'Ziraat Bankası',
        bankName: 'Ziraat',
        type: VaultItemType.bankAccount,
        bankIban: 'TR980006100512345678901234',
        tags: ['finance'],
        updatedAt: now,
      );

      final server = VaultItem(
        id: '3',
        title: 'Production Web Server',
        serverHost: 'web.prod.internal',
        type: VaultItemType.server,
        tags: ['infra'],
        updatedAt: now,
      );

      vault.setItemsForTesting([cred, bank, server]);

      // Token: type:credential
      vault.setSearchQuery('type:credential');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '1');

      // Token: type:bankAccount
      vault.setSearchQuery('type:bankAccount');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '2');

      // Token: is:favorite
      vault.setSearchQuery('is:favorite');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '1');

      // Token: has:totp
      vault.setSearchQuery('has:totp');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '1');

      // Token: tag:finance
      vault.setSearchQuery('tag:finance');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '2');

      // Token + query: type:server web
      vault.setSearchQuery('type:server web');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '3');

      // Non-matching query
      vault.setSearchQuery('nonexistent');
      expect(vault.filteredItems.isEmpty, true);
    });
  });

  group('CredentialDetailPane Widget Tests', () {
    testWidgets('renders credential with password mask toggle and quick copy action chips', (tester) async {
      final item = VaultItem(
        id: 'c1',
        title: 'Netflix Account',
        username: 'user@netflix.com',
        password: 'SuperSecretPassword123!',
        website: 'https://netflix.com',
        type: VaultItemType.credential,
        totpSecret: 'JBSWY3DPEHPK3PXP',
        content: 'Monthly billing via card',
        customFields: const [
          CustomField(id: 'f1', label: 'Security Answer', value: 'Blue', type: CustomFieldType.hidden),
          CustomField(id: 'f2', label: 'Profile PIN', value: '4321', type: CustomFieldType.text),
        ],
        tags: const ['entertainment', 'stream'],
      );

      await tester.pumpWidget(
        _wrapWithLocalization(
          CredentialDetailPane(
            item: item,
            onEdit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title & Username displayed
      expect(find.text('Netflix Account'), findsOneWidget);
      expect(find.text('user@netflix.com'), findsWidgets);

      // Password masked initially (contains '••••••••••••')
      expect(find.text('••••••••••••'), findsWidgets);
      expect(find.text('SuperSecretPassword123!'), findsNothing);

      // Tap password reveal icon
      final revealButtons = find.byIcon(Icons.visibility_outlined);
      if (revealButtons.evaluate().isNotEmpty) {
        await tester.tap(revealButtons.first);
        await tester.pumpAndSettle();
        expect(find.text('SuperSecretPassword123!'), findsOneWidget);
      }

      // Quick copy chips
      expect(find.widgetWithText(ActionChip, 'Username'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Password'), findsOneWidget);

      // Custom fields displayed
      expect(find.text('Security Answer'), findsOneWidget);
      expect(find.text('Profile PIN'), findsOneWidget);
    });

    testWidgets('renders bank account with IBAN validity badge and details', (tester) async {
      final bankItem = VaultItem(
        id: 'b1',
        title: 'Primary Checking',
        type: VaultItemType.bankAccount,
        bankName: 'Test Bank',
        bankIban: 'TR980006100512345678901234',
        bankAccountNumber: '99887766',
        bankRoutingNumber: '00061',
      );

      await tester.pumpWidget(
        _wrapWithLocalization(
          CredentialDetailPane(
            item: bankItem,
            onEdit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Checking'), findsOneWidget);
      expect(find.text('Test Bank'), findsOneWidget);
      expect(find.text('TR98 0006 1005 1234 5678 9012 34'), findsOneWidget);
      expect(find.textContaining('ISO 7064'), findsOneWidget);
    });

    testWidgets('renders cleanly on narrow viewports (<300px) without RenderFlex overflow', (tester) async {
      final bankItem = VaultItem(
        id: 'b-narrow',
        title: 'Compact Viewport Bank Account',
        type: VaultItemType.bankAccount,
        bankName: 'Deutsche Bank Germany',
        bankIban: 'DE89370400440532013000',
        bankAccountNumber: '0532013000',
        bankRoutingNumber: '37040044',
      );

      await tester.binding.setSurfaceSize(const Size(280, 600));
      await tester.pumpWidget(
        _wrapWithLocalization(
          CredentialDetailPane(
            item: bankItem,
            onEdit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CredentialDetailPane), findsOneWidget);
      expect(find.text('Compact Viewport Bank Account'), findsOneWidget);
      expect(find.textContaining('DE89 3704 0044 0532 0130 00'), findsOneWidget);
      expect(find.textContaining('ISO 7064'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('renders server and crypto wallet details cleanly', (tester) async {
      final serverItem = VaultItem(
        id: 's1',
        title: 'App Gateway',
        type: VaultItemType.server,
        serverHost: 'gateway.prod.net',
        serverPort: '2222',
        serverUsername: 'deploy',
      );

      await tester.pumpWidget(
        _wrapWithLocalization(
          CredentialDetailPane(
            item: serverItem,
            onEdit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App Gateway'), findsOneWidget);
      expect(find.text('gateway.prod.net:2222'), findsOneWidget);
      expect(find.text('deploy'), findsOneWidget);
    });
  });

  group('NativeBridgeService Pending Autofill Platform Channel', () {
    const nativeChannel = MethodChannel('com.multipad.multipad/native');

    test('getPendingAutofillCredentials retrieves and deserializes pending entries', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'getPendingAutofillCredentials') {
          return [
            {
              'id': 'pending-1',
              'title': 'Captured Login',
              'website': 'https://example.com',
              'username': 'captured_user',
              'password': 'captured_password_123',
              'packageName': 'com.example.app',
              'timestamp': 1731888000000,
            }
          ];
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      final pending = await NativeBridgeService.getPendingAutofillCredentials();
      expect(pending.length, 1);
      expect(pending.first['id'], 'pending-1');
      expect(pending.first['username'], 'captured_user');
      expect(pending.first['password'], 'captured_password_123');
      expect(pending.first['website'], 'https://example.com');
    });

    test('clearPendingAutofillCredentials invokes native platform channel', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      bool clearCalled = false;

      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'clearPendingAutofillCredentials') {
          clearCalled = true;
          return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

      await NativeBridgeService.clearPendingAutofillCredentials();
      expect(clearCalled, true);
    });
  });
}
