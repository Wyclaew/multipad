import 'dart:convert';
import 'dart:typed_data';
import '../models/vault_item.dart';
import 'totp_service.dart';

enum TotpMigrationSource {
  googleAuthenticatorQr,
  otpAuthUri,
  aegisJson,
  twoFasJson,
  bitwardenJson,
}

class MigratedTotpAccount {
  final String secret;
  final String issuer;
  final String accountName;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;
  final TotpMigrationSource source;
  final String note;

  const MigratedTotpAccount({
    required this.secret,
    required this.issuer,
    required this.accountName,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    required this.source,
    this.note = '',
  });

  String get displayTitle {
    if (issuer.trim().isNotEmpty) return issuer.trim();
    if (accountName.trim().isNotEmpty) return accountName.trim();
    return '2FA Hesabı';
  }

  String get storageTotpValue => TotpService.formatForVaultStorage(
        secret: secret,
        issuer: issuer,
        accountName: accountName,
        period: period,
        digits: digits,
        algorithm: algorithm,
      );

  String get otpAuthUri => TotpService.buildOtpAuthUri(
        secret: secret,
        issuer: issuer,
        accountName: accountName,
        period: period,
        digits: digits,
        algorithm: algorithm,
      );
}

class GoogleMigrationBatchInfo {
  final int version;
  final int batchSize;
  final int batchIndex;
  final int batchId;

  const GoogleMigrationBatchInfo({
    required this.version,
    required this.batchSize,
    required this.batchIndex,
    required this.batchId,
  });

  bool get isMultiPart => batchSize > 1;
}

class TotpMigrationResult {
  final List<MigratedTotpAccount> accounts;
  final List<String> warnings;
  final GoogleMigrationBatchInfo? googleBatch;
  final String? error;

  const TotpMigrationResult({
    this.accounts = const [],
    this.warnings = const [],
    this.googleBatch,
    this.error,
  });

  bool get hasError => error != null && error!.isNotEmpty;
}

enum TotpImportDisposition {
  createStandalone,
  mergeIntoExisting,
  skipDuplicate,
}

class TotpImportCandidate {
  final MigratedTotpAccount account;
  final VaultItem? existingDuplicate;
  final VaultItem? suggestedMergeTarget;
  TotpImportDisposition disposition;
  bool selected;

  TotpImportCandidate({
    required this.account,
    this.existingDuplicate,
    this.suggestedMergeTarget,
    required this.disposition,
    required this.selected,
  });
}

/// Parses 2FA TOTP secrets from Google Authenticator export QRs (`otpauth-migration://`),
/// standard `otpauth://totp/...` URIs (Ente Auth, Duo/Microsoft 3rd-party QRs),
/// Aegis plain JSON, 2FAS `.2fas` JSON, and Bitwarden JSON.
class TotpMigrationService {
  /// Automatically detects and parses arbitrary QR payload, pasted text, or backup file text.
  static TotpMigrationResult parseInput(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const TotpMigrationResult(
        error: 'Aktarılacak veri boş görünüyor.',
      );
    }

    // 1. JSON formats (Aegis, 2FAS, Bitwarden)
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _parseJsonExport(trimmed);
    }

    // 2. Single Google Authenticator migration URI
    if (_looksLikeSingleLineGoogleMigration(trimmed)) {
      return parseGoogleMigrationUri(trimmed);
    }

    // 3. Multi-line / mixed URIs (otpauth://totp/... and/or otpauth-migration://...)
    final List<MigratedTotpAccount> accounts = [];
    final List<String> warnings = [];
    GoogleMigrationBatchInfo? lastBatch;

    final uriMatches = RegExp(
      r'(otpauth-migration://[^\s]+|otpauth://[^\s]+)',
      caseSensitive: false,
    ).allMatches(trimmed);

    for (final match in uriMatches) {
      final token = match.group(0)!;
      if (token.toLowerCase().startsWith('otpauth-migration://')) {
        final res = parseGoogleMigrationUri(token);
        if (res.hasError) {
          warnings.add(res.error!);
        } else {
          accounts.addAll(res.accounts);
          warnings.addAll(res.warnings);
          lastBatch = res.googleBatch ?? lastBatch;
        }
      } else {
        final uri = Uri.tryParse(token);
        if (uri != null && uri.host.toLowerCase() == 'hotp') {
          warnings.add('HOTP (sayaç tabanlı) kod atlandı: ${uri.path}');
          continue;
        }
        final parsed = TotpService.parseOtpAuthUri(token);
        if (parsed != null) {
          accounts.add(
            MigratedTotpAccount(
              secret: parsed.secret,
              issuer: parsed.issuer,
              accountName: parsed.accountName,
              algorithm: parsed.algorithm,
              digits: parsed.digits,
              period: parsed.period,
              source: TotpMigrationSource.otpAuthUri,
            ),
          );
        } else {
          warnings.add('Geçersiz otpauth URI atlandı.');
        }
      }
    }

    if (accounts.isEmpty && warnings.isEmpty) {
      return const TotpMigrationResult(
        error:
            'Desteklenen bir 2FA verisi bulunamadı. "otpauth-migration://", "otpauth://totp/..." veya Aegis/2FAS/Bitwarden JSON kullanın.',
      );
    }

    return TotpMigrationResult(
      accounts: _deduplicateParsed(accounts),
      warnings: warnings,
      googleBatch: lastBatch,
    );
  }

  static bool _looksLikeSingleLineGoogleMigration(String input) {
    final lower = input.toLowerCase();
    return lower.startsWith('otpauth-migration://') &&
        !input.contains('\n') &&
        !input.contains('\r');
  }

  /// Parses a Google Authenticator `otpauth-migration://offline?data=...` QR URI.
  static TotpMigrationResult parseGoogleMigrationUri(String rawUri) {
    final trimmed = rawUri.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'otpauth-migration' ||
        (uri.queryParameters['data'] ?? '').trim().isEmpty) {
      return const TotpMigrationResult(
        error: 'Geçersiz Google Authenticator dışa aktarma QR bağlantısı.',
      );
    }

    final rawData = uri.queryParameters['data']!.trim().replaceAll(' ', '+');
    final decodedBytes = _decodeFlexibleBase64(rawData);
    if (decodedBytes == null || decodedBytes.isEmpty) {
      return const TotpMigrationResult(
        error: 'Google Authenticator QR verisi (Base64) çözülemedi.',
      );
    }

    try {
      return _decodeGoogleProtobufPayload(decodedBytes);
    } catch (e) {
      return TotpMigrationResult(
        error: 'Google Authenticator Protobuf verisi okunamadı: $e',
      );
    }
  }

  static TotpMigrationResult _decodeGoogleProtobufPayload(Uint8List bytes) {
    final reader = _ProtoReader(bytes);
    final List<MigratedTotpAccount> accounts = [];
    final List<String> warnings = [];

    int version = 1;
    int batchSize = 1;
    int batchIndex = 0;
    int batchId = 0;

    while (!reader.isEOF) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      switch (fieldNum) {
        case 1:
          if (wireType != 2) {
            reader.skipField(wireType);
            break;
          }
          final entryBytes = reader.readBytes();
          final parsedEntry = _parseGoogleOtpParameters(entryBytes, warnings);
          if (parsedEntry != null) {
            accounts.add(parsedEntry);
          }
          break;
        case 2:
          version = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 1);
          break;
        case 3:
          batchSize = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 1);
          break;
        case 4:
          batchIndex = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 0);
          break;
        case 5:
          batchId = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 0);
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return TotpMigrationResult(
      accounts: accounts,
      warnings: warnings,
      googleBatch: GoogleMigrationBatchInfo(
        version: version,
        batchSize: batchSize <= 0 ? 1 : batchSize,
        batchIndex: batchIndex < 0 ? 0 : batchIndex,
        batchId: batchId,
      ),
    );
  }

  static MigratedTotpAccount? _parseGoogleOtpParameters(
    Uint8List bytes,
    List<String> warnings,
  ) {
    final reader = _ProtoReader(bytes);
    Uint8List secretBytes = Uint8List(0);
    String name = '';
    String issuer = '';
    int algoCode = 1;
    int digitsCode = 1;
    int typeCode = 2;

    while (!reader.isEOF) {
      final tag = reader.readVarint();
      final fieldNum = tag >> 3;
      final wireType = tag & 0x07;

      switch (fieldNum) {
        case 1:
          secretBytes = wireType == 2 ? reader.readBytes() : _skipBytes(reader, wireType);
          break;
        case 2:
          name = wireType == 2 ? utf8.decode(reader.readBytes(), allowMalformed: true) : '';
          if (wireType != 2) reader.skipField(wireType);
          break;
        case 3:
          issuer = wireType == 2 ? utf8.decode(reader.readBytes(), allowMalformed: true) : '';
          if (wireType != 2) reader.skipField(wireType);
          break;
        case 4:
          algoCode = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 1);
          break;
        case 5:
          digitsCode = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 1);
          break;
        case 6:
          typeCode = wireType == 0 ? reader.readVarint() : _skipAndReturn(reader, wireType, 2);
          break;
        default:
          reader.skipField(wireType);
      }
    }

    final label = name.trim();
    String cleanIssuer = issuer.trim();
    String cleanAccount = label;

    final colonIdx = label.indexOf(':');
    if (colonIdx > 0) {
      final labelIssuer = label.substring(0, colonIdx).trim();
      final labelAccount = label.substring(colonIdx + 1).trim();
      if (cleanIssuer.isEmpty) {
        cleanIssuer = labelIssuer;
        cleanAccount = labelAccount;
      } else if (labelIssuer.toLowerCase() == cleanIssuer.toLowerCase()) {
        cleanAccount = labelAccount;
      }
    }

    final displayName = cleanIssuer.isNotEmpty ? '$cleanIssuer ($cleanAccount)' : cleanAccount;

    // 1 == HOTP
    if (typeCode == 1) {
      warnings.add('HOTP (sayaç tabanlı) kod atlandı: $displayName');
      return null;
    }

    // 4 == MD5
    if (algoCode == 4) {
      warnings.add('MD5 tabanlı eski 2FA kodu desteklenmiyor, atlandı: $displayName');
      return null;
    }

    if (secretBytes.isEmpty) {
      warnings.add('Gizli anahtarı boş olan kayıt atlandı: $displayName');
      return null;
    }

    final base32Secret = TotpService.encodeBase32(secretBytes);
    final algorithm = switch (algoCode) {
      2 => TotpAlgorithm.sha256,
      3 => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    };
    final digits = digitsCode == 2 ? 8 : 6;

    return MigratedTotpAccount(
      secret: base32Secret,
      issuer: cleanIssuer,
      accountName: cleanAccount,
      algorithm: algorithm,
      digits: digits,
      period: 30,
      source: TotpMigrationSource.googleAuthenticatorQr,
    );
  }

  static TotpMigrationResult _parseJsonExport(String rawJson) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (e) {
      return TotpMigrationResult(error: 'JSON dosyası çözümlenemedi: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      return const TotpMigrationResult(
        error: 'Tanınmayan JSON formatı (Aegis, 2FAS veya Bitwarden JSON bekleniyor).',
      );
    }

    // 1. Aegis JSON
    if (decoded.containsKey('db') || decoded.containsKey('header')) {
      final db = decoded['db'];
      if (db is String) {
        return const TotpMigrationResult(
          error:
              'Şifreli Aegis yedeği algılandı. Lütfen Aegis -> Ayarlar -> İçe/Dışa Aktar kısmından "Yedeği şifrele" seçeneğini kapatarak Düz JSON dışa aktarın ve aktarım sonrası o dosyayı silin.',
        );
      }
      if (db is Map<String, dynamic> && db['entries'] is List) {
        return _parseAegisEntries(db['entries'] as List);
      }
    }
    if (decoded['entries'] is List) {
      return _parseAegisEntries(decoded['entries'] as List);
    }

    // 2. 2FAS (.2fas JSON)
    if (decoded.containsKey('services') || decoded.containsKey('servicesEncrypted')) {
      final enc = decoded['servicesEncrypted'];
      final services = decoded['services'];
      if (enc is String && enc.isNotEmpty && (services is! List || services.isEmpty)) {
        return const TotpMigrationResult(
          error:
              'Parola korumalı .2fas yedeği algılandı. Lütfen 2FAS uygulamasından şifresiz JSON yedek dışa aktarın.',
        );
      }
      if (services is List) {
        return _parse2FasServices(services);
      }
    }

    // 3. Bitwarden JSON (items[].login.totp)
    if (decoded['items'] is List) {
      return _parseBitwardenItems(decoded['items'] as List);
    }

    return const TotpMigrationResult(
      error: 'Bu JSON dosyası desteklenen bir 2FA formatıyla (Aegis, 2FAS, Bitwarden) eşleşmedi.',
    );
  }

  static TotpMigrationResult _parseAegisEntries(List entries) {
    final List<MigratedTotpAccount> accounts = [];
    final List<String> warnings = [];

    for (final raw in entries) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final type = (map['type'] as String? ?? 'totp').toLowerCase();
      final issuer = (map['issuer'] as String? ?? '').trim();
      final name = (map['name'] as String? ?? '').trim();
      final note = (map['note'] as String? ?? '').trim();

      if (type != 'totp') {
        warnings.add('TOTP dışındaki ($type) Aegis kaydı atlandı: $issuer $name');
        continue;
      }

      final info = map['info'] is Map
          ? Map<String, dynamic>.from(map['info'] as Map)
          : <String, dynamic>{};
      final secret = TotpService.normalizeBase32(info['secret'] as String? ?? '');
      if (secret.isEmpty || !TotpService.isValidBase32(secret)) {
        warnings.add('Geçersiz Base32 gizli anahtarı atlandı: $issuer $name');
        continue;
      }

      final algo = TotpAlgorithmX.parse(info['algo'] as String?);
      final digits = (info['digits'] as int?) ?? 6;
      final period = (info['period'] as int?) ?? 30;

      accounts.add(
        MigratedTotpAccount(
          secret: secret,
          issuer: issuer,
          accountName: name,
          algorithm: algo,
          digits: digits == 8 ? 8 : 6,
          period: period > 0 ? period : 30,
          source: TotpMigrationSource.aegisJson,
          note: note,
        ),
      );
    }

    return TotpMigrationResult(
      accounts: _deduplicateParsed(accounts),
      warnings: warnings,
    );
  }

  static TotpMigrationResult _parse2FasServices(List services) {
    final List<MigratedTotpAccount> accounts = [];
    final List<String> warnings = [];

    for (final raw in services) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final serviceName = (map['name'] as String? ?? '').trim();
      final otp = map['otp'] is Map
          ? Map<String, dynamic>.from(map['otp'] as Map)
          : <String, dynamic>{};

      final tokenType = (otp['tokenType'] as String? ?? 'TOTP').toUpperCase();
      if (tokenType != 'TOTP') {
        warnings.add('TOTP dışındaki ($tokenType) 2FAS kaydı atlandı: $serviceName');
        continue;
      }

      final link = (otp['link'] as String? ?? '').trim();
      if (link.toLowerCase().startsWith('otpauth://')) {
        final parsed = TotpService.parseOtpAuthUri(link);
        if (parsed != null) {
          accounts.add(
            MigratedTotpAccount(
              secret: parsed.secret,
              issuer: parsed.issuer.isNotEmpty ? parsed.issuer : serviceName,
              accountName: parsed.accountName.isNotEmpty
                  ? parsed.accountName
                  : (otp['account'] as String? ?? '').trim(),
              algorithm: parsed.algorithm,
              digits: parsed.digits,
              period: parsed.period,
              source: TotpMigrationSource.twoFasJson,
            ),
          );
          continue;
        }
      }

      final rawSecret = (map['secret'] as String?) ?? (otp['secret'] as String?) ?? '';
      final secret = TotpService.normalizeBase32(rawSecret);
      if (secret.isEmpty || !TotpService.isValidBase32(secret)) {
        warnings.add('Geçersiz 2FAS gizli anahtarı atlandı: $serviceName');
        continue;
      }

      final issuerFromOtp = (otp['issuer'] as String? ?? '').trim();
      final issuer = serviceName.isNotEmpty ? serviceName : issuerFromOtp;
      final account = (otp['account'] as String? ?? otp['label'] as String? ?? '').trim();

      accounts.add(
        MigratedTotpAccount(
          secret: secret,
          issuer: issuer,
          accountName: account,
          algorithm: TotpAlgorithmX.parse(otp['algorithm'] as String?),
          digits: ((otp['digits'] as int?) ?? 6) == 8 ? 8 : 6,
          period: ((otp['period'] as int?) ?? 30) > 0
              ? (otp['period'] as int? ?? 30)
              : 30,
          source: TotpMigrationSource.twoFasJson,
        ),
      );
    }

    return TotpMigrationResult(
      accounts: _deduplicateParsed(accounts),
      warnings: warnings,
    );
  }

  static TotpMigrationResult _parseBitwardenItems(List items) {
    final List<MigratedTotpAccount> accounts = [];
    final List<String> warnings = [];

    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final login = map['login'] is Map
          ? Map<String, dynamic>.from(map['login'] as Map)
          : null;
      if (login == null) continue;

      final totpRaw = (login['totp'] as String? ?? '').trim();
      if (totpRaw.isEmpty) continue;

      final title = (map['name'] as String? ?? '').trim();
      final username = (login['username'] as String? ?? '').trim();

      final parsed = TotpService.parseOtpAuthUri(totpRaw);
      if (parsed != null) {
        accounts.add(
          MigratedTotpAccount(
            secret: parsed.secret,
            issuer: parsed.issuer.isNotEmpty ? parsed.issuer : title,
            accountName: parsed.accountName.isNotEmpty ? parsed.accountName : username,
            algorithm: parsed.algorithm,
            digits: parsed.digits,
            period: parsed.period,
            source: TotpMigrationSource.bitwardenJson,
          ),
        );
      } else if (TotpService.isValidBase32(totpRaw)) {
        accounts.add(
          MigratedTotpAccount(
            secret: TotpService.normalizeBase32(totpRaw),
            issuer: title,
            accountName: username,
            source: TotpMigrationSource.bitwardenJson,
          ),
        );
      } else {
        warnings.add('Geçersiz Bitwarden 2FA anahtarı atlandı: $title');
      }
    }

    if (accounts.isEmpty && warnings.isEmpty) {
      return const TotpMigrationResult(
        error: 'Bitwarden JSON dosyasında herhangi bir 2FA (TOTP) anahtarı bulunamadı.',
      );
    }

    return TotpMigrationResult(
      accounts: _deduplicateParsed(accounts),
      warnings: warnings,
    );
  }

  static List<MigratedTotpAccount> _deduplicateParsed(
    List<MigratedTotpAccount> accounts,
  ) {
    final seen = <String>{};
    final out = <MigratedTotpAccount>[];
    for (final acc in accounts) {
      if (seen.add(acc.secret)) {
        out.add(acc);
      }
    }
    return out;
  }

  /// Plans how each parsed account should be imported against the user's current vault:
  /// - Skip if identical Base32 secret already exists in an active vault item.
  /// - Suggest merging onto an existing password credential if issuer/account matches cleanly.
  /// - Otherwise create a standalone 2FA credential entry (`isTotpOnly`).
  static List<TotpImportCandidate> planImport(
    List<MigratedTotpAccount> parsedAccounts,
    List<VaultItem> existingItems,
  ) {
    final activeItems =
        existingItems.where((i) => !i.isTrash && !i.isDeleted).toList();
    final activeCreds =
        activeItems.where((i) => i.type == VaultItemType.credential).toList();

    final Map<String, VaultItem> secretToExisting = {};
    for (final item in activeCreds) {
      if (item.totpSecret.trim().isEmpty) continue;
      final norm = TotpService.extractNormalizedSecret(item.totpSecret);
      if (norm.isNotEmpty) {
        secretToExisting.putIfAbsent(norm, () => item);
      }
    }

    final Set<String> reservedMergeIds = {};
    final List<TotpImportCandidate> plan = [];

    for (final acc in _deduplicateParsed(parsedAccounts)) {
      final existingDup = secretToExisting[acc.secret];
      if (existingDup != null) {
        plan.add(
          TotpImportCandidate(
            account: acc,
            existingDuplicate: existingDup,
            disposition: TotpImportDisposition.skipDuplicate,
            selected: false,
          ),
        );
        continue;
      }

      final mergeTarget = _findBestMergeCandidate(
        acc,
        activeCreds,
        reservedMergeIds,
      );
      if (mergeTarget != null) {
        reservedMergeIds.add(mergeTarget.id);
      }

      plan.add(
        TotpImportCandidate(
          account: acc,
          suggestedMergeTarget: mergeTarget,
          disposition: mergeTarget != null
              ? TotpImportDisposition.mergeIntoExisting
              : TotpImportDisposition.createStandalone,
          selected: true,
        ),
      );
    }

    return plan;
  }

  static VaultItem? _findBestMergeCandidate(
    MigratedTotpAccount acc,
    List<VaultItem> credentials,
    Set<String> reservedIds,
  ) {
    final issuerNorm = _normText(acc.issuer);
    final accountNorm = _normText(acc.accountName);

    VaultItem? best;
    int bestScore = 0;

    for (final item in credentials) {
      if (reservedIds.contains(item.id)) continue;
      if (item.totpSecret.trim().isNotEmpty) continue;

      final titleNorm = _normText(item.title);
      final userNorm = _normText(item.username);
      final hostNorm = _extractHostToken(item.website);

      // Avoid merging accounts with conflicting non-empty usernames (e.g. work vs personal)
      if (accountNorm.isNotEmpty &&
          userNorm.isNotEmpty &&
          userNorm != accountNorm) {
        continue;
      }

      int score = 0;
      if (accountNorm.isNotEmpty && userNorm == accountNorm) {
        score += 5;
      }

      if (issuerNorm.isNotEmpty) {
        if (titleNorm == issuerNorm || hostNorm == issuerNorm) {
          score += 5;
        } else if ((titleNorm.isNotEmpty &&
                (titleNorm.contains(issuerNorm) || issuerNorm.contains(titleNorm))) ||
            (hostNorm.isNotEmpty &&
                (hostNorm.contains(issuerNorm) || issuerNorm.contains(hostNorm)))) {
          score += 3;
        }
      }

      // Require both issuer/service signal or exact username + service signal
      if (score >= 5 && score > bestScore) {
        bestScore = score;
        best = item;
      }
    }

    return best;
  }

  static String _normText(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _extractHostToken(String rawUrl) {
    final trimmed = rawUrl.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    final normalized =
        trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(normalized);
    final host = (uri?.host ?? trimmed).replaceFirst(RegExp(r'^www\.'), '');
    final dotIdx = host.indexOf('.');
    return dotIdx > 0 ? host.substring(0, dotIdx) : host;
  }

  static Uint8List? _decodeFlexibleBase64(String input) {
    var cleaned = input.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll('-', '+').replaceAll('_', '/');
    final mod = cleaned.length % 4;
    if (mod == 1) return null;
    if (mod > 1) {
      cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
    }
    try {
      return Uint8List.fromList(base64Decode(cleaned));
    } catch (_) {
      return null;
    }
  }

  static int _skipAndReturn(_ProtoReader reader, int wireType, int fallback) {
    reader.skipField(wireType);
    return fallback;
  }

  static Uint8List _skipBytes(_ProtoReader reader, int wireType) {
    reader.skipField(wireType);
    return Uint8List(0);
  }
}

class _ProtoReader {
  final Uint8List _data;
  int _offset = 0;

  _ProtoReader(this._data);

  bool get isEOF => _offset >= _data.length;

  int readVarint() {
    int result = 0;
    int shift = 0;
    while (_offset < _data.length) {
      final byte = _data[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;
      if (shift > 63) {
        throw const FormatException('Protobuf varint taşması');
      }
    }
    throw const FormatException('Beklenmeyen Protobuf veri sonu');
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (length < 0 || _offset + length > _data.length) {
      throw const FormatException('Geçersiz Protobuf alan uzunluğu');
    }
    final slice = _data.sublist(_offset, _offset + length);
    _offset += length;
    return slice;
  }

  void skipField(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        _advance(8);
        break;
      case 2:
        final len = readVarint();
        _advance(len);
        break;
      case 5:
        _advance(4);
        break;
      default:
        throw FormatException('Desteklenmeyen Protobuf wireType: $wireType');
    }
  }

  void _advance(int count) {
    if (count < 0 || _offset + count > _data.length) {
      throw const FormatException('Protobuf atlama sınırı aşıldı');
    }
    _offset += count;
  }
}
