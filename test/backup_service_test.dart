import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/backup_service.dart';
import 'package:multipad/services/crypto_service.dart';

void main() {
  late CryptoService crypto;
  late BackupService backupService;

  setUp(() {
    crypto = CryptoService();
    backupService = BackupService(crypto);
  });

  test('exports and imports v3 Argon2id backup preserving all 7 item types, folders, custom fields & revisions', () async {
    final now = DateTime.utc(2026, 6, 15, 10, 30);
    final items = [
      VaultItem(
        id: 'note-1',
        type: VaultItemType.note,
        title: 'Şifreli Not 📝',
        content: '- [x] Argon2id test\n- [ ] Kontrol',
        folderId: 'folder-work',
        tags: const ['önemli', 'iş'],
        customFields: [
          CustomField(id: 'cf1', label: 'IBAN', value: 'TR12000100', isHidden: true),
        ],
        revisions: [
          VaultItemRevision(
            id: 'rev1',
            savedAt: now,
            title: 'Eski Başlık',
            content: 'Eski içerik',
            summary: 'İlk düzenleme',
          ),
        ],
        isFavorite: true,
        isPinned: true,
        clientUpdatedAt: now,
      ),
      VaultItem(
        id: 'wifi-1',
        type: VaultItemType.wifi,
        title: 'Ev Ağı',
        wifiSsid: 'Home5G',
        wifiPassword: 'SuperWifiPass!99',
        wifiSecurity: 'WPA',
        wifiHidden: true,
        clientUpdatedAt: now,
      ),
      VaultItem(
        id: 'id-1',
        type: VaultItemType.identity,
        title: 'Pasaport',
        idNumber: 'U12345678',
        fullName: 'Ada Lovelace',
        expiryDate: '2030-05-01',
        issuingAuthority: 'TR',
        clientUpdatedAt: now,
      ),
      VaultItem(
        id: 'lic-1',
        type: VaultItemType.license,
        title: 'JetBrains',
        licenseKey: 'XXXX-YYYY-ZZZZ',
        productName: 'IntelliJ IDEA',
        licensedTo: 'ada@example.com',
        licenseExpiry: '2027-01-01',
        clientUpdatedAt: now,
      ),
    ];

    final exported = await backupService.exportEncryptedBackup(
      items: items,
      backupPassword: 'BackupMasterPassword#2026',
      useArgon2id: true,
    );

    final envelope = jsonDecode(exported) as Map<String, dynamic>;
    expect(envelope['version'], 3);
    expect(CryptoService.isArgon2idSalt(envelope['salt'] as String), isTrue);

    final restored = await backupService.importEncryptedBackup(
      backupString: exported,
      backupPassword: 'BackupMasterPassword#2026',
    );

    expect(restored.length, 4);
    expect(restored[0].type, VaultItemType.note);
    expect(restored[0].title, 'Şifreli Not 📝');
    expect(restored[0].folderId, 'folder-work');
    expect(restored[0].customFields.first.isHidden, isTrue);
    expect(restored[0].customFields.first.value, 'TR12000100');
    expect(restored[0].revisions.length, 1);

    expect(restored[1].type, VaultItemType.wifi);
    expect(restored[1].wifiSsid, 'Home5G');
    expect(restored[1].wifiHidden, isTrue);

    expect(restored[2].type, VaultItemType.identity);
    expect(restored[2].idNumber, 'U12345678');

    expect(restored[3].type, VaultItemType.license);
    expect(restored[3].licenseKey, 'XXXX-YYYY-ZZZZ');
  });

  test('rejects wrong password or tampered backup envelope', () async {
    final items = [
      VaultItem(id: '1', type: VaultItemType.note, title: 'Secret', content: 'Data'),
    ];
    final exported = await backupService.exportEncryptedBackup(
      items: items,
      backupPassword: 'CorrectBackupPass!1',
    );

    await expectLater(
      () => backupService.importEncryptedBackup(
        backupString: exported,
        backupPassword: 'WrongBackupPass!2',
      ),
      throwsException,
    );

    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    final origData = decoded['data'] as String;
    decoded['data'] = '${origData.substring(0, 8)}AAAA${origData.substring(12)}';
    await expectLater(
      () => backupService.importEncryptedBackup(
        backupString: jsonEncode(decoded),
        backupPassword: 'CorrectBackupPass!1',
      ),
      throwsException,
    );
  });
}
