import 'dart:convert';
import '../models/vault_item.dart';
import 'crypto_service.dart';

class BackupService {
  final CryptoService _cryptoService;

  BackupService(this._cryptoService);

  /// Exports vault items as an AES-256-GCM encrypted backup package with a custom backup password.
  Future<String> exportEncryptedBackup({
    required List<VaultItem> items,
    required String backupPassword,
  }) async {
    final salt = _cryptoService.generateSalt();
    List<int>? backupKey;

    try {
      backupKey = await _cryptoService.deriveMasterKey(backupPassword, salt);

      // Prepare JSON data preserving all metadata & Item 30 fields
      final itemsJson = items.map((item) {
        return {
          'id': item.id,
          'type': item.type.toString().split('.').last,
          'title': item.title,
          'content': item.content,
          'username': item.username,
          'password': item.password,
          'website': item.website,
          'totpSecret': item.totpSecret,
          'passwordLastModified': item.passwordLastModified?.toIso8601String(),
          'customExpiryDays': item.customExpiryDays,
          'customReminderDate': item.customReminderDate?.toIso8601String(),
          'cardNumber': item.cardNumber,
          'cardHolder': item.cardHolder,
          'cardExpiry': item.cardExpiry,
          'cardCvv': item.cardCvv,
          'cardPin': item.cardPin,
          'secretType': item.secretType,
          'tags': item.tags,
          'isFavorite': item.isFavorite,
          'isPinned': item.isPinned,
          'isTrash': item.isTrash,
          'passwordHistory': item.passwordHistory,
          'clientUpdatedAt': item.clientUpdatedAt.toIso8601String(),
        };
      }).toList();

      final plainText = jsonEncode({
        'version': 2,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'itemCount': items.length,
        'items': itemsJson,
      });

      final encrypted = await _cryptoService.encryptData(plainText, backupKey);

      final backupPackage = {
        'format': 'multipad_backup_e2ee',
        'version': 2,
        'salt': salt,
        'iv': encrypted.iv,
        'mac': encrypted.mac,
        'data': encrypted.ciphertext,
      };

      return jsonEncode(backupPackage);
    } finally {
      // Immediate RAM hygiene: wipe derived backup key
      CryptoService.wipe(backupKey);
    }
  }

  /// Imports and decrypts a backup package using the backup password.
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
        result.add(VaultItem(
          id: m['id'] ?? '',
          type: VaultItem.typeFromString(m['type'] ?? 'note'),
          title: m['title'] ?? '',
          content: m['content'] ?? '',
          username: m['username'] ?? '',
          password: m['password'] ?? '',
          website: m['website'] ?? '',
          totpSecret: m['totpSecret'] ?? '',
          passwordLastModified: m['passwordLastModified'] != null
              ? DateTime.tryParse(m['passwordLastModified'])
              : null,
          customExpiryDays: m['customExpiryDays'] as int?,
          customReminderDate: m['customReminderDate'] != null
              ? DateTime.tryParse(m['customReminderDate'])
              : null,
          cardNumber: m['cardNumber'] ?? '',
          cardHolder: m['cardHolder'] ?? '',
          cardExpiry: m['cardExpiry'] ?? '',
          cardCvv: m['cardCvv'] ?? '',
          cardPin: m['cardPin'] ?? '',
          secretType: m['secretType'] ?? 'Genel Gizli Bilgi',
          tags: List<String>.from(m['tags'] ?? []),
          isFavorite: m['isFavorite'] ?? false,
          isPinned: m['isPinned'] ?? false,
          isTrash: m['isTrash'] ?? false,
          passwordHistory: List<String>.from(m['passwordHistory'] ?? []),
          clientUpdatedAt: m['clientUpdatedAt'] != null
              ? DateTime.parse(m['clientUpdatedAt'])
              : DateTime.now(),
        ));
      }

      return result;
    } finally {
      // Immediate RAM hygiene: wipe derived backup key
      CryptoService.wipe(backupKey);
    }
  }
}
