import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/services/import_service.dart';

void main() {
  group('Passkey & WebAuthn / FIDO2 Integration Tests', () {
    test('VaultPasskey serializes to JSON and deserializes correctly', () {
      final now = DateTime.now().toUtc();
      final passkey = VaultPasskey(
        id: 'pk-test-uuid',
        credentialId: 'cred-id-base64url-12345',
        rpId: 'github.com',
        rpName: 'GitHub Inc',
        userName: 'octocat@github.com',
        userHandle: 'user-handle-abc',
        privateKey: 'mock-private-key-data',
        algorithm: -7,
        createdAt: now,
      );

      final json = passkey.toJson();
      expect(json['id'], 'pk-test-uuid');
      expect(json['credentialId'], 'cred-id-base64url-12345');
      expect(json['rpId'], 'github.com');
      expect(json['rpName'], 'GitHub Inc');
      expect(json['userName'], 'octocat@github.com');
      expect(json['userHandle'], 'user-handle-abc');
      expect(json['privateKey'], 'mock-private-key-data');
      expect(json['algorithm'], -7);

      final reconstructed = VaultPasskey.fromJson(json);
      expect(reconstructed.id, passkey.id);
      expect(reconstructed.credentialId, passkey.credentialId);
      expect(reconstructed.rpId, passkey.rpId);
      expect(reconstructed.rpName, passkey.rpName);
      expect(reconstructed.userName, passkey.userName);
      expect(reconstructed.userHandle, passkey.userHandle);
      expect(reconstructed.privateKey, passkey.privateKey);
      expect(reconstructed.algorithm, passkey.algorithm);
    });

    test('VaultItem preserves passkeys during toPlainJson and fromDecryptedJson roundtrip', () {
      final passkey = VaultPasskey(
        id: 'pk-1',
        credentialId: 'fido2-cred-id-xyz',
        rpId: 'google.com',
        userName: 'user@gmail.com',
        createdAt: DateTime.now().toUtc(),
      );

      final item = VaultItem(
        id: 'item-1',
        userId: 'u1',
        title: 'Google Account',
        type: VaultItemType.credential,
        username: 'user@gmail.com',
        password: 'Password123!',
        passkeys: [passkey],
        clientUpdatedAt: DateTime.now().toUtc(),
      );

      expect(item.hasPasskeys, isTrue);
      expect(item.passkeys.length, 1);
      expect(item.passkeys.first.rpId, 'google.com');

      final plain = jsonDecode(item.toPlainJson()) as Map<String, dynamic>;
      expect(plain['passkeys'], isA<List>());
      expect((plain['passkeys'] as List).length, 1);

      final restored = VaultItem.fromDecryptedJson(
        id: item.id,
        userId: item.userId,
        type: item.type,
        decryptedPayload: plain,
        isDeleted: false,
        clientUpdatedAt: item.clientUpdatedAt,
      );

      expect(restored.hasPasskeys, isTrue);
      expect(restored.passkeys.length, 1);
      expect(restored.passkeys.first.credentialId, 'fido2-cred-id-xyz');
      expect(restored.passkeys.first.rpId, 'google.com');
      expect(restored.passkeys.first.userName, 'user@gmail.com');
    });

    test('ImportService inspectFile parses Bitwarden JSON export containing fido2Credentials', () {
      final bitwardenExport = {
        "encrypted": false,
        "items": [
          {
            "id": "bw-item-1",
            "type": 1,
            "name": "GitHub Account",
            "notes": "Work credentials",
            "login": {
              "uris": [{"match": null, "uri": "https://github.com"}],
              "username": "developer@corp.com",
              "password": "SuperSecretPass123!",
              "totp": "JBSWY3DPEHPK3PXP",
              "fido2Credentials": [
                {
                  "credentialId": "AQIDBAUGBwgJCgsMDQ4PEA==",
                  "keyType": "public-key",
                  "algorithm": -7,
                  "rpId": "github.com",
                  "userHandle": "dXNlci1oYW5kbGU=",
                  "userName": "developer@corp.com",
                  "keyValue": "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...",
                  "creationDate": "2024-05-10T12:00:00.000Z"
                }
              ]
            }
          }
        ]
      };

      final jsonStr = jsonEncode(bitwardenExport);
      final preview = ImportService.inspectFile(jsonStr);
      final imported = preview.directParsedItems;

      expect(imported.length, 1);
      final credential = imported.first;
      expect(credential.title, 'GitHub Account');
      expect(credential.username, 'developer@corp.com');
      expect(credential.website, 'https://github.com');
      expect(credential.totpSecret, 'JBSWY3DPEHPK3PXP');
      expect(credential.hasPasskeys, isTrue);
      expect(credential.passkeys.length, 1);

      final passkey = credential.passkeys.first;
      expect(passkey.credentialId, 'AQIDBAUGBwgJCgsMDQ4PEA==');
      expect(passkey.rpId, 'github.com');
      expect(passkey.userName, 'developer@corp.com');
      expect(passkey.algorithm, -7);
      expect(passkey.privateKey, contains('MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg'));
    });

    test('ImportService inspectFile parses Bitwarden export with standard passkeys key', () {
      final bitwardenExport = {
        "encrypted": false,
        "items": [
          {
            "id": "bw-item-2",
            "type": 1,
            "name": "Google Account",
            "login": {
              "username": "user@gmail.com",
              "password": "MyGooglePassword99!",
              "passkeys": [
                {
                  "credentialId": "google-cred-123",
                  "rpId": "google.com",
                  "userName": "user@gmail.com"
                }
              ]
            }
          }
        ]
      };

      final jsonStr = jsonEncode(bitwardenExport);
      final preview = ImportService.inspectFile(jsonStr);
      final imported = preview.directParsedItems;

      expect(imported.length, 1);
      final credential = imported.first;
      expect(credential.hasPasskeys, isTrue);
      expect(credential.passkeys.first.credentialId, 'google-cred-123');
      expect(credential.passkeys.first.rpId, 'google.com');
    });
  });
}
