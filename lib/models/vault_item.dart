import 'dart:convert';

enum VaultItemType {
  note,
  credential,
  card,
  secret,
}

class VaultItem {
  final String id;
  final String? userId;
  final VaultItemType type;

  // Decrypted contents (available in memory when unlocked)
  final String title;
  final String content;       // Used for notes or general text
  final String username;      // Used for credentials
  final String password;      // Used for credentials
  final String website;       // Used for credentials
  final String totpSecret;    // 2FA TOTP Base32 secret

  // Credit / Bank Card fields
  final String cardNumber;
  final String cardHolder;
  final String cardExpiry;
  final String cardCvv;
  final String cardPin;

  // Secret Key / Token fields
  final String secretType;    // 'SSH Key', 'API Token', 'Recovery Phrase', 'Other'

  // Metadata & Organization
  final List<String> tags;
  final bool isFavorite;
  final bool isPinned;
  final bool isTrash;
  final List<String> passwordHistory;

  // Sync / Cloud metadata
  final bool isDeleted;       // Permanent soft-delete tombstone
  final DateTime clientUpdatedAt;
  final DateTime? updatedAt;

  // Stored raw ciphertext (when synced or cached)
  final String? rawCiphertext;
  final String? rawIv;
  final String? rawMac;

  VaultItem({
    required this.id,
    this.userId,
    required this.type,
    required this.title,
    this.content = '',
    this.username = '',
    this.password = '',
    this.website = '',
    this.totpSecret = '',
    this.cardNumber = '',
    this.cardHolder = '',
    this.cardExpiry = '',
    this.cardCvv = '',
    this.cardPin = '',
    this.secretType = 'Genel Gizli Bilgi',
    this.tags = const [],
    this.isFavorite = false,
    this.isPinned = false,
    this.isTrash = false,
    this.passwordHistory = const [],
    this.isDeleted = false,
    DateTime? clientUpdatedAt,
    this.updatedAt,
    this.rawCiphertext,
    this.rawIv,
    this.rawMac,
  }) : clientUpdatedAt = clientUpdatedAt ?? DateTime.now().toUtc();

  // Create a copy with modified fields
  VaultItem copyWith({
    String? id,
    String? userId,
    VaultItemType? type,
    String? title,
    String? content,
    String? username,
    String? password,
    String? website,
    String? totpSecret,
    String? cardNumber,
    String? cardHolder,
    String? cardExpiry,
    String? cardCvv,
    String? cardPin,
    String? secretType,
    List<String>? tags,
    bool? isFavorite,
    bool? isPinned,
    bool? isTrash,
    List<String>? passwordHistory,
    bool? isDeleted,
    DateTime? clientUpdatedAt,
    DateTime? updatedAt,
    String? rawCiphertext,
    String? rawIv,
    String? rawMac,
  }) {
    return VaultItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      username: username ?? this.username,
      password: password ?? this.password,
      website: website ?? this.website,
      totpSecret: totpSecret ?? this.totpSecret,
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      cardExpiry: cardExpiry ?? this.cardExpiry,
      cardCvv: cardCvv ?? this.cardCvv,
      cardPin: cardPin ?? this.cardPin,
      secretType: secretType ?? this.secretType,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      isTrash: isTrash ?? this.isTrash,
      passwordHistory: passwordHistory ?? this.passwordHistory,
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rawCiphertext: rawCiphertext ?? this.rawCiphertext,
      rawIv: rawIv ?? this.rawIv,
      rawMac: rawMac ?? this.rawMac,
    );
  }

  // Plain JSON payload to be encrypted by AES-256-GCM
  String toPlainJson() {
    final Map<String, dynamic> data = {
      'title': title,
      'content': content,
      'username': username,
      'password': password,
      'website': website,
      'totpSecret': totpSecret,
      'cardNumber': cardNumber,
      'cardHolder': cardHolder,
      'cardExpiry': cardExpiry,
      'cardCvv': cardCvv,
      'cardPin': cardPin,
      'secretType': secretType,
      'tags': tags,
      'isFavorite': isFavorite,
      'isPinned': isPinned,
      'isTrash': isTrash,
      'passwordHistory': passwordHistory,
    };
    return jsonEncode(data);
  }

  // Factory to construct from decrypted JSON
  static VaultItem fromDecryptedJson({
    required String id,
    String? userId,
    required VaultItemType type,
    required Map<String, dynamic> decryptedPayload,
    required bool isDeleted,
    required DateTime clientUpdatedAt,
    DateTime? updatedAt,
    String? rawCiphertext,
    String? rawIv,
    String? rawMac,
  }) {
    return VaultItem(
      id: id,
      userId: userId,
      type: type,
      title: decryptedPayload['title'] as String? ?? '',
      content: decryptedPayload['content'] as String? ?? '',
      username: decryptedPayload['username'] as String? ?? '',
      password: decryptedPayload['password'] as String? ?? '',
      website: decryptedPayload['website'] as String? ?? '',
      totpSecret: decryptedPayload['totpSecret'] as String? ?? '',
      cardNumber: decryptedPayload['cardNumber'] as String? ?? '',
      cardHolder: decryptedPayload['cardHolder'] as String? ?? '',
      cardExpiry: decryptedPayload['cardExpiry'] as String? ?? '',
      cardCvv: decryptedPayload['cardCvv'] as String? ?? '',
      cardPin: decryptedPayload['cardPin'] as String? ?? '',
      secretType: decryptedPayload['secretType'] as String? ?? 'Genel Gizli Bilgi',
      tags: (decryptedPayload['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isFavorite: decryptedPayload['isFavorite'] as bool? ?? false,
      isPinned: decryptedPayload['isPinned'] as bool? ?? false,
      isTrash: decryptedPayload['isTrash'] as bool? ?? false,
      passwordHistory: (decryptedPayload['passwordHistory'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isDeleted: isDeleted,
      clientUpdatedAt: clientUpdatedAt,
      updatedAt: updatedAt,
      rawCiphertext: rawCiphertext,
      rawIv: rawIv,
      rawMac: rawMac,
    );
  }

  // Map representation for Supabase or local offline storage (only encrypted values!)
  Map<String, dynamic> toStorageMap({
    required String encryptedPayload,
    required String iv,
    required String mac,
  }) {
    return {
      'id': id,
      'item_type': _typeToString(type),
      'encrypted_payload': encryptedPayload,
      'iv': iv,
      'mac': mac,
      'is_deleted': isDeleted,
      'client_updated_at': clientUpdatedAt.toIso8601String(),
    };
  }

  static String _typeToString(VaultItemType t) {
    switch (t) {
      case VaultItemType.credential:
        return 'credential';
      case VaultItemType.card:
        return 'card';
      case VaultItemType.secret:
        return 'secret';
      case VaultItemType.note:
      default:
        return 'note';
    }
  }

  static VaultItemType typeFromString(String str) {
    switch (str.toLowerCase()) {
      case 'credential':
        return VaultItemType.credential;
      case 'card':
        return VaultItemType.card;
      case 'secret':
        return VaultItemType.secret;
      case 'note':
      default:
        return VaultItemType.note;
    }
  }
}
