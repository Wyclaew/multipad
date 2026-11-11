import 'dart:convert';
import '../services/crypto_service.dart';

enum VaultItemType {
  note,
  credential,
  card,
  secret,
  wifi,
  identity,
  license,
  folder,
}

extension VaultItemTypeExt on VaultItemType {
  bool get isUserContent => this != VaultItemType.folder;

  String get storageKey {
    switch (this) {
      case VaultItemType.note:
        return 'note';
      case VaultItemType.credential:
        return 'credential';
      case VaultItemType.card:
        return 'card';
      case VaultItemType.secret:
        return 'secret';
      case VaultItemType.wifi:
        return 'wifi';
      case VaultItemType.identity:
        return 'identity';
      case VaultItemType.license:
        return 'license';
      case VaultItemType.folder:
        return 'folder';
    }
  }
}

class CustomField {
  final String id;
  final String label;
  final String value;
  final bool isHidden;

  const CustomField({
    required this.id,
    required this.label,
    required this.value,
    this.isHidden = false,
  });

  CustomField copyWith({
    String? id,
    String? label,
    String? value,
    bool? isHidden,
  }) {
    return CustomField(
      id: id ?? this.id,
      label: label ?? this.label,
      value: value ?? this.value,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'isHidden': isHidden,
      };

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '',
      isHidden: json['isHidden'] as bool? ?? false,
    );
  }
}

class VaultAttachmentMeta {
  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;

  const VaultAttachmentMeta({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.sha256 = '',
    required this.createdAt,
  });

  bool get isImage {
    final lower = mimeType.toLowerCase();
    final nameLower = fileName.toLowerCase();
    return lower.startsWith('image/') ||
        nameLower.endsWith('.png') ||
        nameLower.endsWith('.jpg') ||
        nameLower.endsWith('.jpeg') ||
        nameLower.endsWith('.webp') ||
        nameLower.endsWith('.gif');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VaultAttachmentMeta.fromJson(Map<String, dynamic> json) {
    return VaultAttachmentMeta(
      id: json['id'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'attachment',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

class VaultItemRevision {
  final String id;
  final DateTime savedAt;
  final String title;
  final String content;
  final String password;
  final String summary;

  const VaultItemRevision({
    required this.id,
    required this.savedAt,
    required this.title,
    this.content = '',
    this.password = '',
    this.summary = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'savedAt': savedAt.toIso8601String(),
        'title': title,
        'content': content,
        'password': password,
        'summary': summary,
      };

  factory VaultItemRevision.fromJson(Map<String, dynamic> json) {
    return VaultItemRevision(
      id: json['id'] as String? ?? '',
      savedAt: json['savedAt'] != null
          ? (DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      password: json['password'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
    );
  }
}

class VaultItem {
  static const int maxRevisions = 15;

  final String id;
  final String? userId;
  final VaultItemType type;

  // Decrypted contents (available in memory when unlocked)
  final String title;
  final String content; // Used for notes (Markdown/Checklist) or general text
  final String username; // Used for credentials
  final String password; // Used for credentials
  final String website; // Used for credentials
  final String totpSecret; // 2FA TOTP Base32 secret or otpauth URI

  // Password Expiry & Reminder System
  final DateTime? passwordLastModified;
  final int? customExpiryDays; // null = global, -1 = never, >0 = custom days
  final DateTime? customReminderDate;

  // Credit / Bank Card fields
  final String cardNumber;
  final String cardHolder;
  final String cardExpiry;
  final String cardCvv;
  final String cardPin;

  // Secret Key / Token fields (also used for folder color hex)
  final String secretType;

  // Wi-Fi fields
  final String wifiSsid;
  final String wifiPassword;
  final String wifiSecurity; // 'WPA', 'WEP', 'nopass'
  final bool wifiHidden;

  // Identity / Passport fields
  final String idNumber;
  final String fullName;
  final String birthDate;
  final String issueDate;
  final String expiryDate;
  final String issuingAuthority;
  final String nationality;

  // Software License fields
  final String licenseKey;
  final String productName;
  final String licensedTo;
  final String purchaseDate;
  final String licenseExpiry;

  // Metadata & Organization
  final String? folderId;
  final List<String> tags;
  final bool isFavorite;
  final bool isPinned;
  final bool isTrash;
  final List<String> passwordHistory;
  final List<CustomField> customFields;
  final List<VaultAttachmentMeta> attachments;
  final List<VaultItemRevision> revisions;

  // Sync / Cloud metadata
  final bool isDeleted; // Permanent soft-delete tombstone
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
    this.passwordLastModified,
    this.customExpiryDays,
    this.customReminderDate,
    this.cardNumber = '',
    this.cardHolder = '',
    this.cardExpiry = '',
    this.cardCvv = '',
    this.cardPin = '',
    this.secretType = 'Genel Gizli Bilgi',
    this.wifiSsid = '',
    this.wifiPassword = '',
    this.wifiSecurity = 'WPA',
    this.wifiHidden = false,
    this.idNumber = '',
    this.fullName = '',
    this.birthDate = '',
    this.issueDate = '',
    this.expiryDate = '',
    this.issuingAuthority = '',
    this.nationality = '',
    this.licenseKey = '',
    this.productName = '',
    this.licensedTo = '',
    this.purchaseDate = '',
    this.licenseExpiry = '',
    this.folderId,
    this.tags = const [],
    this.isFavorite = false,
    this.isPinned = false,
    this.isTrash = false,
    this.passwordHistory = const [],
    this.customFields = const [],
    this.attachments = const [],
    this.revisions = const [],
    this.isDeleted = false,
    DateTime? clientUpdatedAt,
    this.updatedAt,
    this.rawCiphertext,
    this.rawIv,
    this.rawMac,
  }) : clientUpdatedAt = clientUpdatedAt ?? DateTime.now().toUtc();

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
    DateTime? passwordLastModified,
    int? customExpiryDays,
    DateTime? customReminderDate,
    String? cardNumber,
    String? cardHolder,
    String? cardExpiry,
    String? cardCvv,
    String? cardPin,
    String? secretType,
    String? wifiSsid,
    String? wifiPassword,
    String? wifiSecurity,
    bool? wifiHidden,
    String? idNumber,
    String? fullName,
    String? birthDate,
    String? issueDate,
    String? expiryDate,
    String? issuingAuthority,
    String? nationality,
    String? licenseKey,
    String? productName,
    String? licensedTo,
    String? purchaseDate,
    String? licenseExpiry,
    String? folderId,
    bool clearFolderId = false,
    bool clearCustomExpiryDays = false,
    bool clearCustomReminderDate = false,
    List<String>? tags,
    bool? isFavorite,
    bool? isPinned,
    bool? isTrash,
    List<String>? passwordHistory,
    List<CustomField>? customFields,
    List<VaultAttachmentMeta>? attachments,
    List<VaultItemRevision>? revisions,
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
      passwordLastModified: passwordLastModified ?? this.passwordLastModified,
      customExpiryDays: clearCustomExpiryDays
          ? null
          : (customExpiryDays ?? this.customExpiryDays),
      customReminderDate: clearCustomReminderDate
          ? null
          : (customReminderDate ?? this.customReminderDate),
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      cardExpiry: cardExpiry ?? this.cardExpiry,
      cardCvv: cardCvv ?? this.cardCvv,
      cardPin: cardPin ?? this.cardPin,
      secretType: secretType ?? this.secretType,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
      wifiSecurity: wifiSecurity ?? this.wifiSecurity,
      wifiHidden: wifiHidden ?? this.wifiHidden,
      idNumber: idNumber ?? this.idNumber,
      fullName: fullName ?? this.fullName,
      birthDate: birthDate ?? this.birthDate,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      issuingAuthority: issuingAuthority ?? this.issuingAuthority,
      nationality: nationality ?? this.nationality,
      licenseKey: licenseKey ?? this.licenseKey,
      productName: productName ?? this.productName,
      licensedTo: licensedTo ?? this.licensedTo,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      isTrash: isTrash ?? this.isTrash,
      passwordHistory: passwordHistory ?? this.passwordHistory,
      customFields: customFields ?? this.customFields,
      attachments: attachments ?? this.attachments,
      revisions: revisions ?? this.revisions,
      isDeleted: isDeleted ?? this.isDeleted,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rawCiphertext: rawCiphertext ?? this.rawCiphertext,
      rawIv: rawIv ?? this.rawIv,
      rawMac: rawMac ?? this.rawMac,
    );
  }

  /// Plain JSON payload to be encrypted by AES-256-GCM.
  String toPlainJson() {
    final Map<String, dynamic> data = {
      'title': title,
      'content': content,
      'username': username,
      'password': password,
      'website': website,
      'totpSecret': totpSecret,
      'passwordLastModified': passwordLastModified?.toIso8601String(),
      'customExpiryDays': customExpiryDays,
      'customReminderDate': customReminderDate?.toIso8601String(),
      'cardNumber': cardNumber,
      'cardHolder': cardHolder,
      'cardExpiry': cardExpiry,
      'cardCvv': cardCvv,
      'cardPin': cardPin,
      'secretType': secretType,
      if (wifiSsid.isNotEmpty) 'wifiSsid': wifiSsid,
      if (wifiPassword.isNotEmpty) 'wifiPassword': wifiPassword,
      if (wifiSecurity != 'WPA') 'wifiSecurity': wifiSecurity,
      if (wifiHidden) 'wifiHidden': wifiHidden,
      if (idNumber.isNotEmpty) 'idNumber': idNumber,
      if (fullName.isNotEmpty) 'fullName': fullName,
      if (birthDate.isNotEmpty) 'birthDate': birthDate,
      if (issueDate.isNotEmpty) 'issueDate': issueDate,
      if (expiryDate.isNotEmpty) 'expiryDate': expiryDate,
      if (issuingAuthority.isNotEmpty) 'issuingAuthority': issuingAuthority,
      if (nationality.isNotEmpty) 'nationality': nationality,
      if (licenseKey.isNotEmpty) 'licenseKey': licenseKey,
      if (productName.isNotEmpty) 'productName': productName,
      if (licensedTo.isNotEmpty) 'licensedTo': licensedTo,
      if (purchaseDate.isNotEmpty) 'purchaseDate': purchaseDate,
      if (licenseExpiry.isNotEmpty) 'licenseExpiry': licenseExpiry,
      if (folderId != null && folderId!.isNotEmpty) 'folderId': folderId,
      'tags': tags,
      'isFavorite': isFavorite,
      'isPinned': isPinned,
      'isTrash': isTrash,
      'passwordHistory': passwordHistory,
      if (customFields.isNotEmpty)
        'customFields': customFields.map((e) => e.toJson()).toList(),
      if (attachments.isNotEmpty)
        'attachments': attachments.map((e) => e.toJson()).toList(),
      if (revisions.isNotEmpty)
        'revisions': revisions.map((e) => e.toJson()).toList(),
    };
    return jsonEncode(data);
  }

  /// Deterministic SHA-256 hash of decrypted item state (for sync conflict detection).
  String computeContentHash() {
    return CryptoService.sha256Hex(
      '${_typeToString(type)}|$isDeleted|${toPlainJson()}',
    );
  }

  /// Generates standard Wi-Fi QR code payload (`WIFI:T:WPA;S:ssid;P:pass;H:false;;`).
  String toWifiQrPayload() {
    String escapeWifi(String s) => s
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll(':', '\\:');
    final sec = wifiPassword.isEmpty ? 'nopass' : wifiSecurity;
    return 'WIFI:T:$sec;S:${escapeWifi(wifiSsid)};P:${escapeWifi(wifiPassword)};H:$wifiHidden;;';
  }

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
    final rawCustomFields =
        decryptedPayload['customFields'] as List<dynamic>? ?? const [];
    final rawAttachments =
        decryptedPayload['attachments'] as List<dynamic>? ?? const [];
    final rawRevisions =
        decryptedPayload['revisions'] as List<dynamic>? ?? const [];

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
      passwordLastModified: decryptedPayload['passwordLastModified'] != null
          ? DateTime.tryParse(decryptedPayload['passwordLastModified'] as String)
          : null,
      customExpiryDays: decryptedPayload['customExpiryDays'] as int?,
      customReminderDate: decryptedPayload['customReminderDate'] != null
          ? DateTime.tryParse(decryptedPayload['customReminderDate'] as String)
          : null,
      cardNumber: decryptedPayload['cardNumber'] as String? ?? '',
      cardHolder: decryptedPayload['cardHolder'] as String? ?? '',
      cardExpiry: decryptedPayload['cardExpiry'] as String? ?? '',
      cardCvv: decryptedPayload['cardCvv'] as String? ?? '',
      cardPin: decryptedPayload['cardPin'] as String? ?? '',
      secretType:
          decryptedPayload['secretType'] as String? ?? 'Genel Gizli Bilgi',
      wifiSsid: decryptedPayload['wifiSsid'] as String? ?? '',
      wifiPassword: decryptedPayload['wifiPassword'] as String? ?? '',
      wifiSecurity: decryptedPayload['wifiSecurity'] as String? ?? 'WPA',
      wifiHidden: decryptedPayload['wifiHidden'] as bool? ?? false,
      idNumber: decryptedPayload['idNumber'] as String? ?? '',
      fullName: decryptedPayload['fullName'] as String? ?? '',
      birthDate: decryptedPayload['birthDate'] as String? ?? '',
      issueDate: decryptedPayload['issueDate'] as String? ?? '',
      expiryDate: decryptedPayload['expiryDate'] as String? ?? '',
      issuingAuthority: decryptedPayload['issuingAuthority'] as String? ?? '',
      nationality: decryptedPayload['nationality'] as String? ?? '',
      licenseKey: decryptedPayload['licenseKey'] as String? ?? '',
      productName: decryptedPayload['productName'] as String? ?? '',
      licensedTo: decryptedPayload['licensedTo'] as String? ?? '',
      purchaseDate: decryptedPayload['purchaseDate'] as String? ?? '',
      licenseExpiry: decryptedPayload['licenseExpiry'] as String? ?? '',
      folderId: decryptedPayload['folderId'] as String?,
      tags: (decryptedPayload['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isFavorite: decryptedPayload['isFavorite'] as bool? ?? false,
      isPinned: decryptedPayload['isPinned'] as bool? ?? false,
      isTrash: decryptedPayload['isTrash'] as bool? ?? false,
      passwordHistory:
          (decryptedPayload['passwordHistory'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
      customFields: rawCustomFields
          .whereType<Map>()
          .map((e) => CustomField.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      attachments: rawAttachments
          .whereType<Map>()
          .map((e) => VaultAttachmentMeta.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      revisions: rawRevisions
          .whereType<Map>()
          .map((e) => VaultItemRevision.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      isDeleted: isDeleted,
      clientUpdatedAt: clientUpdatedAt,
      updatedAt: updatedAt,
      rawCiphertext: rawCiphertext,
      rawIv: rawIv,
      rawMac: rawMac,
    );
  }

  int get passwordAgeDays {
    final lastMod = passwordLastModified ?? clientUpdatedAt;
    return DateTime.now().difference(lastMod).inDays;
  }

  bool isPasswordExpired(int globalExpiryDays) {
    if (type != VaultItemType.credential || password.isEmpty) return false;

    if (customReminderDate != null) {
      return DateTime.now().isAfter(customReminderDate!);
    }

    if (customExpiryDays != null) {
      if (customExpiryDays == -1) return false;
      return passwordAgeDays >= customExpiryDays!;
    }

    if (globalExpiryDays > 0) {
      return passwordAgeDays >= globalExpiryDays;
    }

    return false;
  }

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

  static String _typeToString(VaultItemType t) => t.storageKey;

  static VaultItemType typeFromString(String str) {
    switch (str.toLowerCase()) {
      case 'credential':
        return VaultItemType.credential;
      case 'card':
        return VaultItemType.card;
      case 'secret':
        return VaultItemType.secret;
      case 'wifi':
        return VaultItemType.wifi;
      case 'identity':
        return VaultItemType.identity;
      case 'license':
        return VaultItemType.license;
      case 'folder':
        return VaultItemType.folder;
      case 'note':
      default:
        return VaultItemType.note;
    }
  }
}
