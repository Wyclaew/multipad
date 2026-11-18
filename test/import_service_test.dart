import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/import_service.dart';

void main() {
  test('parses Chrome/Edge CSV with UTF-8 BOM, quoted commas, and notes', () {
    const csv = '\uFEFFname,url,username,password,note\n'
        '"Bank, Main",https://bank.example.com,alice,"p@ss,word!","PIN: 1234, Branch: Istanbul"\n'
        'GitHub,https://github.com,dev,ghSecret!99,\n';

    final preview = ImportService.inspectFile(csv, fileName: 'chrome_passwords.csv');
    expect(preview.detectedFormat, ImportSourceFormat.chromeEdgeCsv);
    expect(preview.headers, ['name', 'url', 'username', 'password', 'note']);

    final result = ImportService.buildItemsFromPreview(preview, preview.suggestedMapping);
    expect(result.items.length, 2);
    expect(result.items[0].title, 'Bank, Main');
    expect(result.items[0].password, 'p@ss,word!');
    expect(result.items[0].content, 'PIN: 1234, Branch: Istanbul');
    expect(result.items[1].type, VaultItemType.credential);
    expect(result.items[1].username, 'dev');
  });

  test('parses Bitwarden JSON preserving folders, TOTP secrets, cards, and notes', () {
    const jsonStr = '''
    {
      "folders": [{"id": "f-1", "name": "Work"}],
      "items": [
        {
          "type": 1,
          "folderId": "f-1",
          "name": "Portal",
          "notes": "Corporate SSO",
          "login": {
            "username": "bob@corp.io",
            "password": "CorpPassword!2026",
            "totp": "JBSWY3DPEHPK3PXP",
            "uris": [{"uri": "https://portal.corp.io"}]
          }
        },
        {
          "type": 2,
          "name": "Recovery Note",
          "notes": "Seed words here"
        }
      ]
    }
    ''';

    final preview = ImportService.inspectFile(jsonStr, fileName: 'bitwarden_export.json');
    expect(preview.detectedFormat, ImportSourceFormat.bitwardenJson);

    final result = ImportService.buildItemsFromPreview(preview, preview.suggestedMapping);
    expect(result.folders.length, 1);
    expect(result.folders.first.name, 'Work');
    expect(result.items.length, 2);
    expect(result.items[0].folderId, result.folders.first.id);
    expect(result.items[0].totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(result.items[1].type, VaultItemType.note);
  });

  test('parses KeePass 2.x XML preserving groups and entries', () {
    const xmlStr = '''<?xml version="1.0" encoding="utf-8"?>
    <KeePassFile>
      <Root>
        <Group>
          <Name>Root</Name>
          <Group>
            <Name>Servers</Name>
            <Entry>
              <String><Key>Title</Key><Value>SSH Bastion</Value></String>
              <String><Key>UserName</Key><Value>root</Value></String>
              <String><Key>Password</Key><Value>BastionPass!88</Value></String>
              <String><Key>URL</Key><Value>https://bastion.internal</Value></String>
              <String><Key>Notes</Key><Value>Production</Value></String>
            </Entry>
          </Group>
        </Group>
      </Root>
    </KeePassFile>
    ''';

    final preview = ImportService.inspectFile(xmlStr, fileName: 'keepass.xml');
    expect(preview.detectedFormat, ImportSourceFormat.keepassXml);

    final result = ImportService.buildItemsFromPreview(preview, preview.suggestedMapping);
    expect(result.folders.any((f) => f.name == 'Servers'), isTrue);
    expect(result.items.length, 1);
    expect(result.items.first.title, 'SSH Bastion');
    expect(result.items.first.username, 'root');
    expect(result.items.first.password, 'BastionPass!88');
  });

  test('supports custom CsvColumnMapping override for generic CSV', () {
    const csv = 'SiteTitle;Login;Secret\nMyForum;user42;pass42!\n';
    final preview = ImportService.inspectFile(
      csv,
      fileName: 'custom.csv',
      formatHint: ImportSourceFormat.genericCsv,
    );
    final customMap = CsvColumnMapping(
      titleIndex: 0,
      usernameIndex: 1,
      passwordIndex: 2,
    );
    final result = ImportService.buildItemsFromPreview(preview, customMap);
    expect(result.items.length, 1);
    expect(result.items.first.title, 'MyForum');
    expect(result.items.first.username, 'user42');
    expect(result.items.first.password, 'pass42!');
  });

  group('Encrypted Bitwarden JSON Import Decryption', () {
    test('isEncryptedExport accurately detects encrypted vs unencrypted exports', () {
      expect(ImportService.isEncryptedExport('{"encrypted": true}'), isTrue);
      expect(ImportService.isEncryptedExport('{"passwordProtected": true}'), isTrue);
      expect(ImportService.isEncryptedExport('{"folders": [], "items": []}'), isFalse);
      expect(ImportService.isEncryptedExport('name,url,username,password'), isFalse);
      expect(ImportService.isEncryptedExport(''), isFalse);
      expect(ImportService.isEncryptedExport('not json at all'), isFalse);
    });

    test('inspectFile marks encrypted export as isEncrypted without dumping 0 items silently', () {
      const rawEncrypted = '{"encrypted": true, "salt": "a@b.com", "data": "2.iv|cipher|mac"}';
      final preview = ImportService.inspectFile(rawEncrypted, fileName: 'export.json');
      expect(preview.isEncrypted, isTrue);
      expect(preview.directParsedItems, isEmpty);
      expect(preview.detectedFormat, ImportSourceFormat.bitwardenJson);
    });

    test('inspectFileAsync decrypts Bitwarden JSON export with valid password', () async {
      final crypto = CryptoService();
      const innerJson = '''
      {
        "folders": [{"id": "folder-1", "name": "Banking"}],
        "items": [
          {
            "id": "item-1",
            "type": 1,
            "folderId": "folder-1",
            "name": "Acme Bank",
            "login": {
              "username": "customer123",
              "password": "BankPassword!2026",
              "totp": "JBSWY3DPEHPK3PXP",
              "uris": [{"uri": "https://acmebank.com"}]
            }
          }
        ]
      }
      ''';

      final subkeys = await crypto.deriveBitwardenSubKeys(
        password: 'VaultPass!2026',
        salt: 'alice@acme.com',
        iterations: 1000,
      );

      final cipherString = await crypto.encryptBitwardenCipherString(
        plaintext: innerJson,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );

      final rawEncrypted = '''
      {
        "encrypted": true,
        "passwordProtected": true,
        "salt": "alice@acme.com",
        "kdfType": 0,
        "kdfIterations": 1000,
        "data": "$cipherString"
      }
      ''';

      // 1. Without password -> returns preview with isEncrypted: true
      final unauthedPreview = await ImportService.inspectFileAsync(rawEncrypted);
      expect(unauthedPreview.isEncrypted, isTrue);
      expect(unauthedPreview.directParsedItems, isEmpty);

      // 2. With correct password -> decrypts and parses folders + items
      final authedPreview = await ImportService.inspectFileAsync(
        rawEncrypted,
        decryptionPassword: 'VaultPass!2026',
      );
      expect(authedPreview.isEncrypted, isFalse);
      expect(authedPreview.directParsedFolders.length, 1);
      expect(authedPreview.directParsedFolders.first.name, 'Banking');
      expect(authedPreview.directParsedItems.length, 1);
      expect(authedPreview.directParsedItems.first.title, 'Acme Bank');
      expect(authedPreview.directParsedItems.first.username, 'customer123');
      expect(authedPreview.directParsedItems.first.password, 'BankPassword!2026');
      expect(authedPreview.directParsedItems.first.totpSecret, 'JBSWY3DPEHPK3PXP');

      // 3. With wrong password -> throws FormatException
      await expectLater(
        () => ImportService.inspectFileAsync(
          rawEncrypted,
          decryptionPassword: 'WrongPassword!',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
