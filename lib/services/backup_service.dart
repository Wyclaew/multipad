import 'dart:convert';
import '../models/vault_item.dart';
import 'crypto_service.dart';

class BackupService {
  final CryptoService _cryptoService;

  BackupService(this._cryptoService);

  /// Exports vault items (including folders, custom fields, Wi-Fi, identity, license,
  /// revisions, and optional attachment payloads) as an Argon2id + AES-256-GCM encrypted backup.
  Future<String> exportEncryptedBackup({
    required List<VaultItem> items,
    required String backupPassword,
    bool useArgon2id = true,
  }) async {
    final salt = _cryptoService.generateSalt(useArgon2id: useArgon2id);
    List<int>? backupKey;

    try {
      backupKey = await _cryptoService.deriveMasterKey(backupPassword, salt);

      final itemsJson = items.map((item) {
        final plainMap = jsonDecode(item.toPlainJson()) as Map<String, dynamic>;
        return {
          'id': item.id,
          'type': item.type.storageKey,
          'isDeleted': item.isDeleted,
          'clientUpdatedAt': item.clientUpdatedAt.toIso8601String(),
          ...plainMap,
        };
      }).toList();

      final plainText = jsonEncode({
        'version': 3,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'itemCount': items.length,
        'items': itemsJson,
      });

      final encrypted = await _cryptoService.encryptData(plainText, backupKey);

      final backupPackage = {
        'format': 'multipad_backup_e2ee',
        'version': 3,
        'salt': salt,
        'iv': encrypted.iv,
        'mac': encrypted.mac,
        'data': encrypted.ciphertext,
      };

      return jsonEncode(backupPackage);
    } finally {
      CryptoService.wipe(backupKey);
    }
  }

  /// Imports and decrypts a backup package (supports both v1/v2 PBKDF2 and v3 Argon2id).
  Future<List<VaultItem>> importEncryptedBackup({
    required String backupString,
    required String backupPassword,
  }) async {
    final Map<String, dynamic> package = jsonDecode(backupString);
    if (package['format'] != 'multipad_backup_e2ee') {
      throw Exception('Geçersiz MultiPad yedek dosyası biçimi.');
    }

    final salt = package['salt'] as String;
    final iv = package['iv'] as String;
    final mac = package['mac'] as String;
    final data = package['data'] as String;

    List<int>? backupKey;
    try {
      backupKey = await _cryptoService.deriveMasterKey(backupPassword, salt);

      final decryptedPlain = await _cryptoService.decryptData(
        ciphertextBase64: data,
        ivBase64: iv,
        macBase64: mac,
        masterKey: backupKey,
      );

      final Map<String, dynamic> content = jsonDecode(decryptedPlain);
      final List<dynamic> itemsList = content['items'] as List<dynamic>;

      final List<VaultItem> result = [];
      for (final itemMap in itemsList) {
        final m = Map<String, dynamic>.from(itemMap as Map);
        final id = (m['id'] as String? ?? '').isNotEmpty
            ? m['id'] as String
            : 'imported_${result.length}';
        final type = VaultItem.typeFromString(m['type'] as String? ?? 'note');
        final isDeleted = m['isDeleted'] as bool? ?? false;
        final updatedAt = m['clientUpdatedAt'] != null
            ? (DateTime.tryParse(m['clientUpdatedAt'] as String) ??
                DateTime.now().toUtc())
            : DateTime.now().toUtc();

        result.add(
          VaultItem.fromDecryptedJson(
            id: id,
            type: type,
            decryptedPayload: m,
            isDeleted: isDeleted,
            clientUpdatedAt: updatedAt,
          ),
        );
      }

      return result;
    } finally {
      CryptoService.wipe(backupKey);
    }
  }
}
