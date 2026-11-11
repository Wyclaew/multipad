import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../constants.dart';
import 'crypto_service.dart';
import 'database_service.dart';

enum SecurityEventType {
  unlockSuccess,
  unlockFailed,
  pinUnlockSuccess,
  pinUnlockFailed,
  biometricSuccess,
  biometricDisabledByFailures,
  duressUnlocked,
  lockoutTriggered,
  vaultLocked,
  masterPasswordChanged,
  kdfUpgradedToArgon2id,
  mfaChanged,
  otherSessionsSignedOut,
}

class SecurityLogEntry {
  final String id;
  final DateTime timestamp;
  final SecurityEventType type;
  final String detail;
  final bool isWarning;

  SecurityLogEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.detail,
    this.isWarning = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'detail': detail,
        'isWarning': isWarning,
      };

  factory SecurityLogEntry.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'unlockSuccess';
    return SecurityLogEntry(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      type: SecurityEventType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => SecurityEventType.unlockSuccess,
      ),
      detail: json['detail'] as String? ?? '',
      isWarning: json['isWarning'] as bool? ?? false,
    );
  }
}

class SecurityLogService {
  static const _uuid = Uuid();
  final CryptoService _crypto = CryptoService();
  final FlutterSecureStorage _secureStorage;

  SecurityLogService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              mOptions: MacOsOptions(useDataProtectionKeyChain: false),
              wOptions: WindowsOptions(useBackwardCompatibility: true),
            );

  Future<Uint8List> _getOrCreateDeviceLogKey() async {
    String? existing =
        await _secureStorage.read(key: AppConstants.keySecurityLogKey);
    if (existing == null || existing.isEmpty) {
      final rawKey = _crypto.generateRandomBytes(32);
      existing = base64Encode(rawKey);
      await _secureStorage.write(
        key: AppConstants.keySecurityLogKey,
        value: existing,
      );
      return rawKey;
    }
    return Uint8List.fromList(base64Decode(existing));
  }

  /// Appends an encrypted security event to SQLite `security_logs` (retains latest 200 events).
  Future<void> logEvent(
    SecurityEventType type,
    String detail, {
    bool isWarning = false,
  }) async {
    Uint8List? key;
    try {
      key = await _getOrCreateDeviceLogKey();
      final entry = SecurityLogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now().toUtc(),
        type: type,
        detail: detail,
        isWarning: isWarning,
      );
      final enc = await _crypto.encryptData(jsonEncode(entry.toJson()), key);
      final db = await DatabaseService.database;
      await db.insert(
        'security_logs',
        {
          'id': entry.id,
          'created_at': entry.timestamp.toIso8601String(),
          'ciphertext': enc.ciphertext,
          'iv': enc.iv,
          'mac': enc.mac,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Trim oldest records beyond 200 entries
      await db.execute('''
        DELETE FROM security_logs WHERE id NOT IN (
          SELECT id FROM security_logs ORDER BY created_at DESC LIMIT 200
        )
      ''');
    } catch (_) {
      // Never crash authentication flow if local logging fails
    } finally {
      CryptoService.wipe(key);
    }
  }

  Future<List<SecurityLogEntry>> loadLogs() async {
    Uint8List? key;
    try {
      key = await _getOrCreateDeviceLogKey();
      final db = await DatabaseService.database;
      final rows = await db.query(
        'security_logs',
        orderBy: 'created_at DESC',
        limit: 200,
      );
      final entries = <SecurityLogEntry>[];
      for (final row in rows) {
        try {
          final plain = await _crypto.decryptData(
            ciphertextBase64: row['ciphertext'] as String,
            ivBase64: row['iv'] as String,
            macBase64: row['mac'] as String,
            masterKey: key,
          );
          entries.add(
            SecurityLogEntry.fromJson(
              Map<String, dynamic>.from(jsonDecode(plain) as Map),
            ),
          );
        } catch (_) {
          // Skip unreadable row
        }
      }
      return entries;
    } finally {
      CryptoService.wipe(key);
    }
  }

  Future<void> clearLogs() async {
    final db = await DatabaseService.database;
    await db.delete('security_logs');
  }

  // --- Brute-Force Attempt Lockout State ---

  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.keyFailedAttempts) ?? 0;
  }

  Future<bool> isBiometricTemporarilyDisabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyBiometricDisabledDueToFailures) ??
        false;
  }

  Future<Duration> getRemainingLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(AppConstants.keyLockoutUntilIso);
    if (iso == null || iso.isEmpty) return Duration.zero;
    final until = DateTime.tryParse(iso);
    if (until == null) return Duration.zero;
    final diff = until.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Records a failed unlock attempt and applies progressive cooldown:
  /// - >= 3 failures: biometric temporarily disabled until Master Password succeeds
  /// - 3 fails: 15s, 4 fails: 30s, 5 fails: 60s, 6+ fails: 300s (5m)
  Future<({int failedCount, Duration lockoutDuration, bool biometricDisabled})>
      recordFailedAttempt({required String sourceLabel}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getInt(AppConstants.keyFailedAttempts) ?? 0) + 1;
    await prefs.setInt(AppConstants.keyFailedAttempts, current);

    var bioDisabled =
        prefs.getBool(AppConstants.keyBiometricDisabledDueToFailures) ?? false;

    Duration lockout = Duration.zero;
    if (current == 3) {
      lockout = const Duration(seconds: 15);
    } else if (current == 4) {
      lockout = const Duration(seconds: 30);
    } else if (current == 5) {
      lockout = const Duration(seconds: 60);
    } else if (current >= 6) {
      lockout = const Duration(minutes: 5);
    }

    if (current >= 3 && !bioDisabled) {
      bioDisabled = true;
      await prefs.setBool(AppConstants.keyBiometricDisabledDueToFailures, true);
      await logEvent(
        SecurityEventType.biometricDisabledByFailures,
        '3+ ardışık hatalı deneme nedeniyle biyometrik kilit geçici olarak devre dışı bırakıldı.',
        isWarning: true,
      );
    }

    if (lockout > Duration.zero) {
      final until = DateTime.now().toUtc().add(lockout);
      await prefs.setString(
        AppConstants.keyLockoutUntilIso,
        until.toIso8601String(),
      );
      await logEvent(
        SecurityEventType.lockoutTriggered,
        '$sourceLabel: $current hatalı deneme -> ${lockout.inSeconds} sn bekleme kilidi.',
        isWarning: true,
      );
    } else {
      await logEvent(
        SecurityEventType.unlockFailed,
        '$sourceLabel hatalı deneme ($current. kez).',
        isWarning: true,
      );
    }

    return (
      failedCount: current,
      lockoutDuration: lockout,
      biometricDisabled: bioDisabled,
    );
  }

  Future<void> resetFailedAttempts({bool clearBiometricDisable = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyFailedAttempts);
    await prefs.remove(AppConstants.keyLockoutUntilIso);
    if (clearBiometricDisable) {
      await prefs.remove(AppConstants.keyBiometricDisabledDueToFailures);
    }
  }
}
