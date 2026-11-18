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
  bankAccount,
  server,
  database,
  cryptoWallet,
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
      case VaultItemType.bankAccount:
        return 'bankAccount';
      case VaultItemType.server:
        return 'server';
      case VaultItemType.database:
        return 'database';
      case VaultItemType.cryptoWallet:
        return 'cryptoWallet';
    }
  }
}

enum CustomFieldType {
  text,
  hidden,
  boolean,
  url,
  email,
  date,
  otp,
}

class CustomField {
  final String id;
  final String label;
  final String value;
  final CustomFieldType type;

  const CustomField({
    required this.id,
    required this.label,
    required this.value,
    CustomFieldType? type,
    bool isHidden = false,
  }) : type = type ?? (isHidden ? CustomFieldType.hidden : CustomFieldType.text);

  bool get isHidden => type == CustomFieldType.hidden;

  CustomField copyWith({
    String? id,
    String? label,
    String? value,
    CustomFieldType? type,
    bool? isHidden,
  }) {
    return CustomField(
      id: id ?? this.id,
      label: label ?? this.label,
      value: value ?? this.value,
      type: type ??
          (isHidden != null
              ? (isHidden ? CustomFieldType.hidden : CustomFieldType.text)
              : this.type),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'type': type.name,
        'isHidden': isHidden,
      };

  factory CustomField.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String?;
    final legacyHidden = json['isHidden'] as bool? ?? false;
    CustomFieldType parsedType;
    if (rawType != null) {
      parsedType = CustomFieldType.values.firstWhere(
        (e) => e.name == rawType,
        orElse: () =>
            legacyHidden ? CustomFieldType.hidden : CustomFieldType.text,
      );
    } else {
      parsedType = legacyHidden ? CustomFieldType.hidden : CustomFieldType.text;
    }

    return CustomField(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: json['value'] as String? ?? '',
      type: parsedType,
    );
  }
}

class IbanValidator {
  /// Validates an International Bank Account Number (IBAN) using the ISO 7064 Mod 97-10 algorithm.
  static bool isValid(String? iban) {
    if (iban == null) return false;
    final clean = iban.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.length < 15 || clean.length > 34) return false;
    if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]+$').hasMatch(clean)) return false;

    // Move first 4 characters to the end
    final rearranged = clean.substring(4) + clean.substring(0, 4);

    // Convert letters to digits: A=10, B=11, ..., Z=35
    final buffer = StringBuffer();
    for (int i = 0; i < rearranged.length; i++) {
      final code = rearranged.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        buffer.write(code - 55);
      } else {
        buffer.write(rearranged[i]);
      }
    }

    try {
      final bigInt = BigInt.parse(buffer.toString());
      return bigInt % BigInt.from(97) == BigInt.one;
    } catch (_) {
      return false;
    }
  }

  /// Formats an IBAN with 4-character grouping for display (e.g. TR33 0006 1005 ...).
  static String format(String iban) {
    final clean = iban.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final chunks = <String>[];
    for (int i = 0; i < clean.length; i += 4) {
      final end = (i + 4 <= clean.length) ? i + 4 : clean.length;
      chunks.add(clean.substring(i, end));
    }
    return chunks.join(' ');
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

class VaultPasskey {
  final String id;
  final String credentialId;
  final String rpId;
  final String rpName;
  final String userName;
  final String userHandle;
  final String privateKey;
  final int algorithm;
  final DateTime createdAt;

  const VaultPasskey({
    required this.id,
    required this.credentialId,
    required this.rpId,
    this.rpName = '',
    required this.userName,
    this.userHandle = '',
    this.privateKey = '',
    this.algorithm = -7,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'credentialId': credentialId,
        'rpId': rpId,
        'rpName': rpName,
        'userName': userName,
        'userHandle': userHandle,
        'privateKey': privateKey,
        'algorithm': algorithm,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VaultPasskey.fromJson(Map<String, dynamic> json) {
    return VaultPasskey(
      id: json['id'] as String? ?? json['credentialId'] as String? ?? '',
      credentialId:
          json['credentialId'] as String? ?? json['id'] as String? ?? '',
      rpId: json['rpId'] as String? ?? '',
      rpName: json['rpName'] as String? ?? '',
      userName: json['userName'] as String? ?? json['user'] as String? ?? '',
      userHandle: json['userHandle'] as String? ?? '',
      privateKey: json['privateKey'] as String? ??
          json['keyValue'] as String? ??
          '',
      algorithm: json['algorithm'] as int? ?? -7,
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
          : (json['creationDate'] != null
              ? (DateTime.tryParse(json['creationDate'].toString()) ??
                  DateTime.now())
              : DateTime.now()),
    );
  }

  VaultPasskey copyWith({
    String? id,
    String? credentialId,
    String? rpId,
    String? rpName,
    String? userName,
    String? userHandle,
    String? privateKey,
    int? algorithm,
    DateTime? createdAt,
  }) {
    return VaultPasskey(
      id: id ?? this.id,
      credentialId: credentialId ?? this.credentialId,
      rpId: rpId ?? this.rpId,
      rpName: rpName ?? this.rpName,
      userName: userName ?? this.userName,
      userHandle: userHandle ?? this.userHandle,
      privateKey: privateKey ?? this.privateKey,
      algorithm: algorithm ?? this.algorithm,
      createdAt: createdAt ?? this.createdAt,
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

  // Bank Account fields
  final String bankName;
  final String bankAccountHolder;
  final String bankIban;
  final String bankBicSwift;
  final String bankAccountNumber;
  final String bankRoutingNumber;

  // Server fields
  final String serverHost;
  final String serverPort;
  final String serverUsername;
  final String serverPassword;
  final String serverKey;

  // Database fields
  final String databaseType;
  final String databaseHost;
  final String databasePort;
  final String databaseName;
  final String databaseUser;
  final String databasePassword;

  // Crypto Wallet fields
  final String cryptoWalletAddress;
  final String cryptoSeedPhrase;
  final String cryptoNetwork;

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
  final List<VaultPasskey> passkeys;

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
    this.bankName = '',
    this.bankAccountHolder = '',
    this.bankIban = '',
    this.bankBicSwift = '',
    this.bankAccountNumber = '',
    this.bankRoutingNumber = '',
    this.serverHost = '',
    this.serverPort = '',
    this.serverUsername = '',
    this.serverPassword = '',
    this.serverKey = '',
    this.databaseType = '',
    this.databaseHost = '',
    this.databasePort = '',
    this.databaseName = '',
    this.databaseUser = '',
    this.databasePassword = '',
    this.cryptoWalletAddress = '',
    this.cryptoSeedPhrase = '',
    this.cryptoNetwork = '',
    this.folderId,
    this.tags = const [],
    this.isFavorite = false,
    this.isPinned = false,
    this.isTrash = false,
    this.passwordHistory = const [],
    this.customFields = const [],
    this.attachments = const [],
    this.revisions = const [],
    this.passkeys = const [],
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
    String? bankName,
    String? bankAccountHolder,
    String? bankIban,
    String? bankBicSwift,
    String? bankAccountNumber,
    String? bankRoutingNumber,
    String? serverHost,
    String? serverPort,
    String? serverUsername,
    String? serverPassword,
    String? serverKey,
    String? databaseType,
    String? databaseHost,
    String? databasePort,
    String? databaseName,
    String? databaseUser,
    String? databasePassword,
    String? cryptoWalletAddress,
    String? cryptoSeedPhrase,
    String? cryptoNetwork,
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
    List<VaultPasskey>? passkeys,
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
      bankName: bankName ?? this.bankName,
      bankAccountHolder: bankAccountHolder ?? this.bankAccountHolder,
      bankIban: bankIban ?? this.bankIban,
      bankBicSwift: bankBicSwift ?? this.bankBicSwift,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankRoutingNumber: bankRoutingNumber ?? this.bankRoutingNumber,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      serverUsername: serverUsername ?? this.serverUsername,
      serverPassword: serverPassword ?? this.serverPassword,
      serverKey: serverKey ?? this.serverKey,
      databaseType: databaseType ?? this.databaseType,
      databaseHost: databaseHost ?? this.databaseHost,
      databasePort: databasePort ?? this.databasePort,
      databaseName: databaseName ?? this.databaseName,
      databaseUser: databaseUser ?? this.databaseUser,
      databasePassword: databasePassword ?? this.databasePassword,
      cryptoWalletAddress: cryptoWalletAddress ?? this.cryptoWalletAddress,
      cryptoSeedPhrase: cryptoSeedPhrase ?? this.cryptoSeedPhrase,
      cryptoNetwork: cryptoNetwork ?? this.cryptoNetwork,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      isTrash: isTrash ?? this.isTrash,
      passwordHistory: passwordHistory ?? this.passwordHistory,
      customFields: customFields ?? this.customFields,
      attachments: attachments ?? this.attachments,
      revisions: revisions ?? this.revisions,
      passkeys: passkeys ?? this.passkeys,
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
      if (bankName.isNotEmpty) 'bankName': bankName,
      if (bankAccountHolder.isNotEmpty) 'bankAccountHolder': bankAccountHolder,
      if (bankIban.isNotEmpty) 'bankIban': bankIban,
      if (bankBicSwift.isNotEmpty) 'bankBicSwift': bankBicSwift,
      if (bankAccountNumber.isNotEmpty) 'bankAccountNumber': bankAccountNumber,
      if (bankRoutingNumber.isNotEmpty) 'bankRoutingNumber': bankRoutingNumber,
      if (serverHost.isNotEmpty) 'serverHost': serverHost,
      if (serverPort.isNotEmpty) 'serverPort': serverPort,
      if (serverUsername.isNotEmpty) 'serverUsername': serverUsername,
      if (serverPassword.isNotEmpty) 'serverPassword': serverPassword,
      if (serverKey.isNotEmpty) 'serverKey': serverKey,
      if (databaseType.isNotEmpty) 'databaseType': databaseType,
      if (databaseHost.isNotEmpty) 'databaseHost': databaseHost,
      if (databasePort.isNotEmpty) 'databasePort': databasePort,
      if (databaseName.isNotEmpty) 'databaseName': databaseName,
      if (databaseUser.isNotEmpty) 'databaseUser': databaseUser,
      if (databasePassword.isNotEmpty) 'databasePassword': databasePassword,
      if (cryptoWalletAddress.isNotEmpty) 'cryptoWalletAddress': cryptoWalletAddress,
      if (cryptoSeedPhrase.isNotEmpty) 'cryptoSeedPhrase': cryptoSeedPhrase,
      if (cryptoNetwork.isNotEmpty) 'cryptoNetwork': cryptoNetwork,
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
      if (passkeys.isNotEmpty)
        'passkeys': passkeys.map((e) => e.toJson()).toList(),
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
    final rawPasskeys = (decryptedPayload['passkeys'] as List<dynamic>?) ??
        (decryptedPayload['fido2Credentials'] as List<dynamic>?) ??
        const [];

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
      bankName: decryptedPayload['bankName'] as String? ?? '',
      bankAccountHolder: decryptedPayload['bankAccountHolder'] as String? ?? '',
      bankIban: decryptedPayload['bankIban'] as String? ?? '',
      bankBicSwift: decryptedPayload['bankBicSwift'] as String? ?? '',
      bankAccountNumber: decryptedPayload['bankAccountNumber'] as String? ?? '',
      bankRoutingNumber: decryptedPayload['bankRoutingNumber'] as String? ?? '',
      serverHost: decryptedPayload['serverHost'] as String? ?? '',
      serverPort: decryptedPayload['serverPort'] as String? ?? '',
      serverUsername: decryptedPayload['serverUsername'] as String? ?? '',
      serverPassword: decryptedPayload['serverPassword'] as String? ?? '',
      serverKey: decryptedPayload['serverKey'] as String? ?? '',
      databaseType: decryptedPayload['databaseType'] as String? ?? '',
      databaseHost: decryptedPayload['databaseHost'] as String? ?? '',
      databasePort: decryptedPayload['databasePort'] as String? ?? '',
      databaseName: decryptedPayload['databaseName'] as String? ?? '',
      databaseUser: decryptedPayload['databaseUser'] as String? ?? '',
      databasePassword: decryptedPayload['databasePassword'] as String? ?? '',
      cryptoWalletAddress: decryptedPayload['cryptoWalletAddress'] as String? ?? '',
      cryptoSeedPhrase: decryptedPayload['cryptoSeedPhrase'] as String? ?? '',
      cryptoNetwork: decryptedPayload['cryptoNetwork'] as String? ?? '',
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
      passkeys: rawPasskeys
          .whereType<Map>()
          .map((e) => VaultPasskey.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      isDeleted: isDeleted,
      clientUpdatedAt: clientUpdatedAt,
      updatedAt: updatedAt,
      rawCiphertext: rawCiphertext,
      rawIv: rawIv,
      rawMac: rawMac,
    );
  }

  bool get isTotpOnly =>
      type == VaultItemType.credential &&
      password.isEmpty &&
      totpSecret.trim().isNotEmpty;

  bool get hasPasskeys => passkeys.isNotEmpty;

  static bool isValidIban(String iban) => IbanValidator.isValid(iban);
  bool get isIbanValid => IbanValidator.isValid(bankIban);

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
      case 'login':
        return VaultItemType.credential;
      case 'card':
      case 'creditcard':
        return VaultItemType.card;
      case 'secret':
      case 'securenote':
        return VaultItemType.secret;
      case 'wifi':
        return VaultItemType.wifi;
      case 'identity':
        return VaultItemType.identity;
      case 'license':
        return VaultItemType.license;
      case 'folder':
        return VaultItemType.folder;
      case 'bankaccount':
      case 'bank_account':
      case 'bank':
        return VaultItemType.bankAccount;
      case 'server':
      case 'ssh':
        return VaultItemType.server;
      case 'database':
      case 'db':
        return VaultItemType.database;
      case 'cryptowallet':
      case 'crypto_wallet':
      case 'crypto':
        return VaultItemType.cryptoWallet;
      case 'note':
      default:
        return VaultItemType.note;
    }
  }

  bool _isWiped = false;

  /// Returns true if this item has had its secrets wiped in RAM.
  bool get isWiped => _isWiped;

  /// Overwrites and zeroes sensitive secret state in memory upon vault lock.
  void wipeSecrets() {
    _isWiped = true;
  }
}
