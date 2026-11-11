import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
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
}
