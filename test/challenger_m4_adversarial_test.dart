import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
    tempDir = Directory.systemTemp.createTempSync('multipad_challenger_m4_');
    DatabaseService.configureForTesting(
      dbPath: p.join(tempDir.path, 'challenger_m4.db'),
    );
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Adversarial Group 1: IBAN ISO 7064 Mod 97-10 Edge Cases', () {
    test('Validates multi-country authentic IBAN test vectors across Europe & Middle East', () {
      final validIbans = <String, String>{
        'DE': 'DE89370400440532013000', // Germany (22 chars)
        'FR': 'FR1420041010050500013M02606', // France (27 chars, alphanumeric BBAN with 'M')
        'GB': 'GB82WEST12345698765432', // United Kingdom (22 chars, letters in bank code 'WEST')
        'TR': 'TR980006100512345678901234', // Turkey (26 chars)
        'NL': 'NL91ABNA0417164300', // Netherlands (18 chars, bank code 'ABNA')
        'BE': 'BE68539007547034', // Belgium (16 chars)
        'CH': 'CH9300762011623852957', // Switzerland (21 chars)
        'NO': 'NO9386011117947', // Norway (15 chars, ISO minimum boundary)
        'MT': 'MT84MALT011000012345MTLCAST001S', // Malta (31 chars, alphanumeric BBAN)
      };

      for (final entry in validIbans.entries) {
        final iban = entry.value;
        expect(
          IbanValidator.isValid(iban),
          isTrue,
          reason: 'Valid IBAN for country ${entry.key} ($iban) must pass validation',
        );
        expect(
          VaultItem.isValidIban(iban),
          isTrue,
          reason: 'VaultItem.isValidIban helper must match for ${entry.key}',
        );
      }
    });

    test('Tolerates whitespace, dashes, underscores, dots and lowercase formatting', () {
      final formattedVariants = [
        'TR98 0006 1005 1234 5678 9012 34',
        'tr98 0006 1005 1234 5678 9012 34',
        '  TR98   0006 1005   1234 5678 9012 34  ',
        'TR98-0006-1005-1234-5678-9012-34',
        'tr98.0006.1005.1234.5678.9012.34',
        'TR98_0006_1005_1234_5678_9012_34',
        '\tTR98 0006 1005 1234 5678 9012 34\n',
      ];

      for (final variant in formattedVariants) {
        expect(
          IbanValidator.isValid(variant),
          isTrue,
          reason: 'Formatted variant "$variant" must be sanitized and pass',
        );
      }
    });

    test('Rejects transposed check digits, single-digit substitutions, and corrupt checksums', () {
      // 1. Transposed check digits 98 -> 89
      expect(IbanValidator.isValid('TR890006100512345678901234'), isFalse);
      // 2. Off-by-one check digits
      expect(IbanValidator.isValid('TR970006100512345678901234'), isFalse);
      expect(IbanValidator.isValid('TR990006100512345678901234'), isFalse);
      // 3. Single digit tamper in BBAN account portion (last digit 4 -> 5)
      expect(IbanValidator.isValid('TR980006100512345678901235'), isFalse);
      // 4. Transposed adjacent digits in BBAN (5678 -> 5768)
      expect(IbanValidator.isValid('TR980006100512345768901234'), isFalse);
      // 5. Corrupt German IBAN (last digit 0 -> 1)
      expect(IbanValidator.isValid('DE89370400440532013001'), isFalse);
      // 6. Corrupt French IBAN (letter M -> N)
      expect(IbanValidator.isValid('FR1420041010050500013N02606'), isFalse);
    });

    test('Length boundary probing: rejects < 15 and > 34 chars, empty, and null', () {
      expect(IbanValidator.isValid(null), isFalse);
      expect(IbanValidator.isValid(''), isFalse);
      expect(IbanValidator.isValid('   '), isFalse);

      // 14 characters (1 below ISO min 15)
      expect(IbanValidator.isValid('NO938601111794'), isFalse);

      // 34 characters (ISO max valid boundary length)
      final chars34 = 'TR98000610051234567890123400000000';
      expect(chars34.length, 34);
      expect(IbanValidator.isValid(chars34), isFalse);

      // 35 characters (1 above ISO max 34)
      final chars35 = 'TR980006100512345678901234000000001';
      expect(chars35.length, 35);
      expect(IbanValidator.isValid(chars35), isFalse);

      // Extreme length: 1,000 characters
      final massive = 'DE89370400440532013000${'0' * 1000}';
      expect(IbanValidator.isValid(massive), isFalse);
    });

    test('Probes ISO 13616 country code and check digit format requirements', () {
      // In ISO 13616, positions 0..1 MUST be uppercase letters (ISO 3166-1 alpha-2 country code).
      // A string where positions 0..1 are numeric but mod 97 == 1 mathematically:
      // "009800000000000" -> rearranged is "000000000000098" -> BigInt(98) % 97 == 1.
      final numericCountryCodeResult = IbanValidator.isValid('009800000000000');
      // Document whether IbanValidator validates ISO 13616 country code prefix structure:
      // If it returns true, it fails to enforce that positions 0..1 must be alpha country codes!
      expect(
        numericCountryCodeResult,
        isFalse,
        reason: 'IBAN starting with digits "00" must be rejected per ISO 13616 country code structure',
      );

      // Letters in check digit positions
      expect(IbanValidator.isValid('TRXX0006100512345678901234'), isFalse);
      expect(IbanValidator.isValid('TRA90006100512345678901234'), isFalse);

      // Turkish non-ASCII characters
      expect(IbanValidator.isValid('TR98000610051234567890123İ'), isFalse);
      expect(IbanValidator.isValid('TR98000610051234567890123Ş'), isFalse);
    });

    test('IbanValidator.format groups into neat 4-character blocks', () {
      expect(
        IbanValidator.format('TR980006100512345678901234'),
        'TR98 0006 1005 1234 5678 9012 34',
      );
      expect(
        IbanValidator.format('DE89370400440532013000'),
        'DE89 3704 0044 0532 0130 00',
      );
      expect(
        IbanValidator.format('NO9386011117947'),
        'NO93 8601 1117 947',
      );
      expect(IbanValidator.format(''), '');
    });
  });

  group('Adversarial Group 2: Diceware Entropy, 1000+ Generation Collision & FIFO History', () {
    test('EFF Wordlist contains exactly 7,776 unique non-empty lowercase words', () {
      final words = EFFWordlist.words;
      expect(words.length, 7776, reason: 'EFF Diceware large list must contain exactly 6^5 = 7776 words');
      final uniqueSet = words.toSet();
      expect(uniqueSet.length, 7776, reason: 'Every word in EFF wordlist must be unique');

      for (final word in words) {
        expect(word, isNotEmpty);
        expect(word, equals(word.toLowerCase()));
        expect(word.contains(' '), isFalse, reason: 'No word should contain whitespace: "$word"');
      }
    });

    test('Generates 1,000+ passphrases without collisions and analyzes delimiter collision on hyphenated dictionary words', () {
      final generated = <String>{};
      const totalToGenerate = 1200;

      // Check hyphenated words in EFF wordlist:
      // The EFF large wordlist natively contains: 'drop-down', 'felt-tip', 't-shirt', 'yo-yo'.
      final hyphenatedWords = EFFWordlist.words.where((w) => w.contains('-')).toList();
      expect(hyphenatedWords, containsAll(['drop-down', 'felt-tip', 't-shirt', 'yo-yo']));

      // 1. Generate 1,200 passphrases using non-colliding delimiter '.'
      for (int i = 0; i < totalToGenerate; i++) {
        final phrase = EFFWordlist.generatePassphrase(
          wordCount: 5,
          separator: '.',
          capitalize: false,
        );

        final parts = phrase.split('.');
        expect(parts.length, 5, reason: 'Dot delimiter must yield exactly 5 words');

        for (final word in parts) {
          expect(
            EFFWordlist.words.contains(word),
            isTrue,
            reason: 'Generated token "$word" must exist in official EFF wordlist',
          );
        }

        generated.add(phrase);
      }

      // 7776^5 ≈ 2.84 * 10^19 combinations. Zero collisions expected.
      expect(
        generated.length,
        totalToGenerate,
        reason: 'Zero collisions expected across $totalToGenerate 5-word passphrases',
      );
    });

    test('Evaluates custom separators and capitalization behavior', () {
      final separators = ['_', '.', ' ', '#', '/', '::'];

      for (final sep in separators) {
        final phrase = EFFWordlist.generatePassphrase(
          wordCount: 4,
          separator: sep,
          capitalize: true,
        );

        expect(phrase, isNotEmpty);
        final tokens = phrase.split(sep);
        expect(tokens.length, 4);
        for (final token in tokens) {
          expect(token[0], equals(token[0].toUpperCase()), reason: 'Token $token must be capitalized');
          expect(EFFWordlist.words.contains(token.toLowerCase()), isTrue);
        }
      }
    });

    test('Verifies mathematical entropy calculation formula (log2(7776) * words)', () {
      const bitsPerWord = 12.924812503605762;

      for (int wc = 1; wc <= 12; wc++) {
        final expected = wc * bitsPerWord;
        final computed = EFFWordlist.calculateEntropy(wordCount: wc);
        expect(computed, closeTo(expected, 0.001));
      }

      expect(EFFWordlist.calculateEntropy(wordCount: 4), closeTo(51.699, 0.01));
      expect(EFFWordlist.calculateEntropy(wordCount: 5), closeTo(64.624, 0.01));
      expect(EFFWordlist.calculateEntropy(wordCount: 6), closeTo(77.548, 0.01));
    });

    test('PasswordGeneratorDialog history maintains strictly capped 50-item FIFO ring buffer', () {
      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history, isEmpty);

      final now = DateTime.now();

      // Push 110 items
      for (int i = 1; i <= 110; i++) {
        PasswordGeneratorDialog.recordGeneration(
          GeneratedPasswordRecord(
            password: 'pass_$i',
            mode: i.isEven ? 'password' : 'passphrase',
            entropyBits: 50.0 + i,
            timestamp: now.add(Duration(seconds: i)),
          ),
        );
      }

      // History must be strictly capped at 50
      expect(PasswordGeneratorDialog.history.length, 50);

      // Most recent should be at index 0
      expect(PasswordGeneratorDialog.history[0].password, 'pass_110');
      expect(PasswordGeneratorDialog.history[1].password, 'pass_109');

      // Oldest remaining should be at index 49 (pass_61)
      expect(PasswordGeneratorDialog.history[49].password, 'pass_61');

      // Passes 1 through 60 must have been evicted
      final passwords = PasswordGeneratorDialog.history.map((r) => r.password).toSet();
      for (int i = 1; i <= 60; i++) {
        expect(
          passwords.contains('pass_$i'),
          isFalse,
          reason: 'pass_$i should have been evicted by FIFO ring buffer',
        );
      }

      PasswordGeneratorDialog.clearHistory();
      expect(PasswordGeneratorDialog.history, isEmpty);
    });
  });

  group('Adversarial Group 3: VaultItem Backward Compatibility & Schema Tamper Resistance', () {
    test('Deserializes legacy Milestone 1-3 payloads without any new Milestone 4 fields', () {
      final legacyPayload = <String, dynamic>{
        'title': 'Legacy Credentials Item',
        'username': 'legacy_user',
        'password': 'LegacyPassword123!',
        'website': 'https://legacy.example.com',
        'totpSecret': 'JBSWY3DPEHPK3PXP',
        'tags': ['legacy', 'm1'],
        'isFavorite': true,
        'isPinned': false,
        'isTrash': false,
      };

      final item = VaultItem.fromDecryptedJson(
        id: 'legacy-id-1',
        type: VaultItemType.credential,
        decryptedPayload: legacyPayload,
        isDeleted: false,
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      expect(item.id, 'legacy-id-1');
      expect(item.title, 'Legacy Credentials Item');
      expect(item.username, 'legacy_user');
      expect(item.password, 'LegacyPassword123!');

      // All new Milestone 4 fields must safely default without null pointer exceptions
      expect(item.bankName, '');
      expect(item.bankAccountHolder, '');
      expect(item.bankIban, '');
      expect(item.bankBicSwift, '');
      expect(item.bankAccountNumber, '');
      expect(item.bankRoutingNumber, '');
      expect(item.serverHost, '');
      expect(item.serverPort, '');
      expect(item.serverUsername, '');
      expect(item.serverPassword, '');
      expect(item.serverKey, '');
      expect(item.databaseType, '');
      expect(item.databaseHost, '');
      expect(item.databasePort, '');
      expect(item.databaseName, '');
      expect(item.databaseUser, '');
      expect(item.databasePassword, '');
      expect(item.cryptoWalletAddress, '');
      expect(item.cryptoSeedPhrase, '');
      expect(item.cryptoNetwork, '');
      expect(item.customFields, isEmpty);
      expect(item.attachments, isEmpty);
      expect(item.revisions, isEmpty);
      expect(item.isIbanValid, isFalse);
    });

    test('Robustly handles corrupted, null, and non-conforming customFields elements', () {
      final corruptPayload = <String, dynamic>{
        'title': 'Corrupt Payload Item',
        'customFields': [
          null, // null element
          'invalid_string_not_a_map', // non-map
          12345, // int
          <String, dynamic>{}, // empty map
          <String, dynamic>{
            'id': 'cf-valid-1',
            'label': 'API Token',
            'value': 'sec_123',
            'type': 'hidden',
          },
          <String, dynamic>{
            'id': 'cf-unknown-type',
            'label': 'Quantum Key',
            'value': 'qk_999',
            'type': 'QUANTUM_TYPE_UNKNOWN_V99', // Unknown future type
            'isHidden': true,
          },
          <String, dynamic>{
            'id': 'cf-legacy-boolean',
            'label': 'Auto Renew',
            'value': 'true',
            'type': 'boolean',
          },
        ],
      };

      final item = VaultItem.fromDecryptedJson(
        id: 'corrupt-cf-1',
        type: VaultItemType.note,
        decryptedPayload: corruptPayload,
        isDeleted: false,
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      expect(item.customFields.length, 4);

      // Check empty map fallback
      expect(item.customFields[0].id, '');
      expect(item.customFields[0].label, '');
      expect(item.customFields[0].value, '');
      expect(item.customFields[0].type, CustomFieldType.text);

      // Check valid hidden field
      expect(item.customFields[1].id, 'cf-valid-1');
      expect(item.customFields[1].type, CustomFieldType.hidden);
      expect(item.customFields[1].isHidden, isTrue);

      // Check unknown type fallback (falls back to hidden since isHidden is true)
      expect(item.customFields[2].id, 'cf-unknown-type');
      expect(item.customFields[2].type, CustomFieldType.hidden);

      // Check boolean field
      expect(item.customFields[3].id, 'cf-legacy-boolean');
      expect(item.customFields[3].type, CustomFieldType.boolean);
    });

    test('VaultItem serialization roundtrip preserves all 4 new item types and custom fields', () {
      final now = DateTime.now().toUtc();
      final item = VaultItem(
        id: 'full-test-1',
        title: 'Full Bank Item',
        type: VaultItemType.bankAccount,
        bankName: 'Swiss Trust',
        bankAccountHolder: 'Ada Lovelace',
        bankIban: 'CH9300762011623852957',
        bankBicSwift: 'SWISTRZZ',
        bankAccountNumber: '00762011623852957',
        bankRoutingNumber: '0076',
        serverHost: 'ssh.cluster.dev',
        serverPort: '2200',
        serverUsername: 'root',
        serverPassword: 'RootPassword99!',
        serverKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...',
        databaseType: 'PostgreSQL',
        databaseHost: 'pg.internal.dev',
        databasePort: '5432',
        databaseName: 'primary_vault',
        databaseUser: 'pg_admin',
        databasePassword: 'DbSecretPassword!1',
        cryptoWalletAddress: '0x1234567890abcdef1234567890abcdef12345678',
        cryptoSeedPhrase: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        cryptoNetwork: 'Ethereum',
        customFields: const [
          CustomField(id: 'c1', label: 'Support PIN', value: '4321', type: CustomFieldType.hidden),
          CustomField(id: 'c2', label: 'Portal', value: 'https://bank.ch', type: CustomFieldType.url),
          CustomField(id: 'c3', label: 'Branch Email', value: 'branch@bank.ch', type: CustomFieldType.email),
          CustomField(id: 'c4', label: 'Opened Date', value: '2024-01-15', type: CustomFieldType.date),
          CustomField(id: 'c5', label: 'Backup 2FA', value: 'JBSWY3DPEHPK3PXP', type: CustomFieldType.otp),
        ],
        tags: const ['banking', 'crypto', 'devops'],
        isFavorite: true,
        updatedAt: now,
      );

      final jsonStr = item.toPlainJson();
      final decodedMap = jsonDecode(jsonStr) as Map<String, dynamic>;

      final reconstructed = VaultItem.fromDecryptedJson(
        id: item.id,
        type: item.type,
        decryptedPayload: decodedMap,
        isDeleted: false,
        clientUpdatedAt: now,
        updatedAt: item.updatedAt,
      );

      expect(reconstructed.id, item.id);
      expect(reconstructed.type, VaultItemType.bankAccount);
      expect(reconstructed.bankName, item.bankName);
      expect(reconstructed.bankIban, item.bankIban);
      expect(reconstructed.isIbanValid, isTrue);
      expect(reconstructed.serverHost, item.serverHost);
      expect(reconstructed.serverPort, item.serverPort);
      expect(reconstructed.databaseType, item.databaseType);
      expect(reconstructed.databaseName, item.databaseName);
      expect(reconstructed.cryptoWalletAddress, item.cryptoWalletAddress);
      expect(reconstructed.cryptoSeedPhrase, item.cryptoSeedPhrase);
      expect(reconstructed.customFields.length, 5);
      expect(reconstructed.customFields[0].type, CustomFieldType.hidden);
      expect(reconstructed.customFields[1].type, CustomFieldType.url);
      expect(reconstructed.customFields[2].type, CustomFieldType.email);
      expect(reconstructed.customFields[3].type, CustomFieldType.date);
      expect(reconstructed.customFields[4].type, CustomFieldType.otp);

      // Hash deterministic stability
      expect(reconstructed.computeContentHash(), equals(item.computeContentHash()));
    });
  });

  group('Adversarial Group 4: CredentialDetailPane Layout, Overflows & Structured Search Stress', () {
    testWidgets('Probes CredentialDetailPane layout behavior under standard viewports (600px, 1000px, 2560px)', (tester) async {
      final now = DateTime.now();
      final item = VaultItem(
        id: 'test-item-1',
        title: 'Primary Test Item',
        type: VaultItemType.bankAccount,
        bankName: 'Deutsche Bank',
        bankIban: 'DE89370400440532013000',
        bankAccountNumber: '0532013000',
        bankRoutingNumber: '37040044',
        updatedAt: now,
      );

      final viewports = [
        const Size(600, 800), // Mobile
        const Size(1000, 700), // Tablet/Desktop
        const Size(2560, 1440), // 4K Ultrawide
      ];

      for (final vp in viewports) {
        await tester.binding.setSurfaceSize(vp);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('tr')],
            home: Scaffold(
              body: CredentialDetailPane(
                item: item,
                onEdit: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDetailPane), findsOneWidget);
        expect(find.text('Deutsche Bank'), findsOneWidget);
        expect(find.text('DE89 3704 0044 0532 0130 00'), findsOneWidget);
      }

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Survives massive unbroken string overflow in CredentialDetailPane without layout crash', (tester) async {
      final massiveItem = VaultItem(
        id: 'massive-1',
        title: 'M' * 500,
        type: VaultItemType.credential,
        username: '${'U' * 300}@unbrokenlongdomainname123456789.com',
        password: 'P' * 256,
        website: 'https://${'W' * 400}.org',
        totpSecret: 'JBSWY3DPEHPK3PXP',
        content: 'C' * 5000,
        bankName: 'B' * 200,
        bankIban: 'TR980006100512345678901234',
        serverHost: 'S' * 200,
        serverPort: '2222',
        databaseName: 'D' * 200,
        cryptoWalletAddress: '0x${'A' * 150}',
        customFields: List.generate(
          15,
          (i) => CustomField(
            id: 'cf-$i',
            label: 'Field_Label_${i}_${'L' * 80}',
            value: 'Field_Value_${i}_${'V' * 150}',
            type: CustomFieldType.text,
          ),
        ),
        tags: List.generate(10, (i) => 'tag_$i'),
      );

      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('tr')],
          home: Scaffold(
            body: CredentialDetailPane(
              item: massiveItem,
              onEdit: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CredentialDetailPane), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    test('Stress-tests structured search tokens with complex combinations, casing, and regex characters', () {
      final vault = VaultProvider();
      final now = DateTime.now();

      final items = [
        VaultItem(
          id: '1',
          title: 'Google Cloud Console',
          username: 'admin@google.com',
          website: 'https://console.cloud.google.com',
          type: VaultItemType.credential,
          totpSecret: 'JBSWY3DPEHPK3PXP',
          isFavorite: true,
          tags: const ['cloud', 'infra'],
          updatedAt: now,
        ),
        VaultItem(
          id: '2',
          title: 'Ziraat Bank Checking',
          bankName: 'Ziraat',
          bankIban: 'TR980006100512345678901234',
          type: VaultItemType.bankAccount,
          isFavorite: false,
          tags: const ['finance', 'turkey'],
          updatedAt: now,
        ),
        VaultItem(
          id: '3',
          title: 'AWS Production Bastion',
          serverHost: 'bastion.prod.internal',
          type: VaultItemType.server,
          isFavorite: true,
          tags: const ['infra', 'ssh'],
          updatedAt: now,
        ),
        VaultItem(
          id: '4',
          title: 'PostgreSQL Analytics Replica',
          databaseName: 'analytics_db',
          databaseType: 'PostgreSQL',
          type: VaultItemType.database,
          tags: const ['data', 'sql'],
          updatedAt: now,
        ),
        VaultItem(
          id: '5',
          title: 'Ledger Cold Storage',
          cryptoWalletAddress: '0x71C...B29',
          cryptoNetwork: 'Ethereum',
          type: VaultItemType.cryptoWallet,
          isFavorite: false,
          tags: const ['crypto', 'cold'],
          updatedAt: now,
        ),
        VaultItem(
          id: '6',
          title: 'Archived Old Secret Note',
          content: 'super confidential note',
          type: VaultItemType.note,
          isTrash: true,
          tags: const ['old'],
          updatedAt: now,
        ),
      ];

      vault.setItemsForTesting(items);

      // 1. Single token tests
      vault.setSearchQuery('type:bankAccount');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '2');

      vault.setSearchQuery('type:server');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '3');

      vault.setSearchQuery('type:database');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '4');

      vault.setSearchQuery('type:cryptoWallet');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '5');

      // 2. Token case-insensitivity: TYPE:CREDENTIAL
      vault.setSearchQuery('TYPE:CREDENTIAL');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '1');

      // 3. Combined tokens: type:credential has:totp is:favorite
      vault.setSearchQuery('type:credential has:totp is:favorite');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '1');

      // 4. Combined tokens with free text: type:server bastion
      vault.setSearchQuery('type:server bastion');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '3');

      // 5. Multiple spaces between tokens
      vault.setSearchQuery('   type:server     ssh   ');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '3');

      // 6. Trash token: is:trash
      vault.setSearchQuery('is:trash');
      expect(vault.filteredItems.length, 1);
      expect(vault.filteredItems.first.id, '6');

      // 7. Regex / symbol characters in query text without crash: [a-z]+.*(?=test)$^
      vault.setSearchQuery(r'[a-z]+.*(?=test)$^');
      expect(vault.filteredItems, isEmpty);

      // 8. Tag filter
      vault.setSearchQuery('tag:infra');
      expect(vault.filteredItems.map((i) => i.id).toSet(), equals({'1', '3'}));
    });
  });
}
