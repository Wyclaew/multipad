import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/services/crypto_service.dart';

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('CryptoService KDF & Salt', () {
    test('generates valid Argon2id and legacy PBKDF2 salts deterministically', () async {
      final argonSalt = crypto.generateSalt(useArgon2id: true);
      final pbkdf2Salt = crypto.generateSalt(useArgon2id: false);

      expect(CryptoService.isArgon2idSalt(argonSalt), isTrue);
      expect(CryptoService.isArgon2idSalt(pbkdf2Salt), isFalse);

      final k1 = await crypto.deriveMasterKey('StrongMasterPass!2026', argonSalt);
      final k2 = await crypto.deriveMasterKey('StrongMasterPass!2026', argonSalt);
      final kWrong = await crypto.deriveMasterKey('WrongMasterPass!2026', argonSalt);

      expect(k1.length, 32);
      expect(CryptoService.constantTimeEquals(k1, k2), isTrue);
      expect(CryptoService.constantTimeEquals(k1, kWrong), isFalse);

      final legacy1 = await crypto.deriveMasterKey('LegacyPass!99', pbkdf2Salt);
      final legacy2 = await crypto.deriveMasterKey('LegacyPass!99', pbkdf2Salt);
      expect(legacy1.length, 32);
      expect(CryptoService.constantTimeEquals(legacy1, legacy2), isTrue);

      CryptoService.wipe(k1);
      CryptoService.wipe(k2);
      CryptoService.wipe(kWrong);
      CryptoService.wipe(legacy1);
      CryptoService.wipe(legacy2);
    });

    test('separates auth password and duress verifier domains cleanly', () async {
      final salt = crypto.generateSalt(useArgon2id: true);
      final key = await crypto.deriveMasterKey('TestMaster123!', salt);

      final authPass = crypto.deriveAuthPassword(key);
      final duressVer = crypto.deriveDuressVerifier(key);

      expect(authPass, isNotEmpty);
      expect(duressVer, isNotEmpty);
      expect(authPass, isNot(duressVer));

      final pinKey1 = await crypto.derivePinWrappingKey('482910', 'c2FsdF92MQ==');
      final pinKey2 = await crypto.derivePinWrappingKey('482910', 'c2FsdF92MQ==');
      final pinKeyWrong = await crypto.derivePinWrappingKey('482911', 'c2FsdF92MQ==');
      expect(CryptoService.constantTimeEquals(pinKey1, pinKey2), isTrue);
      expect(CryptoService.constantTimeEquals(pinKey1, pinKeyWrong), isFalse);

      CryptoService.wipe(key);
      CryptoService.wipe(pinKey1);
      CryptoService.wipe(pinKey2);
      CryptoService.wipe(pinKeyWrong);
    });
  });

  group('CryptoService AES-256-GCM', () {
    test('encryptData and decryptData roundtrip Unicode and reject tampering/wrong key', () async {
      final salt = crypto.generateSalt(useArgon2id: true);
      final key = await crypto.deriveMasterKey('CorrectHorseBatteryStaple!', salt);
      final wrongKey = await crypto.deriveMasterKey('AnotherPassword!2026', salt);

      const plaintext = '{"title":"Türkçe Şifreli Not 🔐","secret":"p@ssw0rd_ğüşiöç"}';
      final enc = await crypto.encryptData(plaintext, key);

      final decrypted = await crypto.decryptData(
        ciphertextBase64: enc.ciphertext,
        ivBase64: enc.iv,
        macBase64: enc.mac,
        masterKey: key,
      );
      expect(decrypted, plaintext);

      await expectLater(
        () => crypto.decryptData(
          ciphertextBase64: enc.ciphertext,
          ivBase64: enc.iv,
          macBase64: enc.mac,
          masterKey: wrongKey,
        ),
        throwsA(anything),
      );

      // Tamper with MAC tag
      final badMac = enc.mac == 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
          ? 'BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
          : '${enc.mac.substring(0, enc.mac.length - 2)}AA';
      await expectLater(
        () => crypto.decryptData(
          ciphertextBase64: enc.ciphertext,
          ivBase64: enc.iv,
          macBase64: badMac,
          masterKey: key,
        ),
        throwsA(anything),
      );

      CryptoService.wipe(key);
      CryptoService.wipe(wrongKey);
    });

    test('encryptBytes and decryptBytes protect binary attachments with integrity check', () async {
      final key = Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 3) & 0xff));
      final rawBytes = Uint8List.fromList(List<int>.generate(256, (i) => i));

      final enc = await crypto.encryptBytes(rawBytes, key);
      final dec = await crypto.decryptBytes(
        ciphertextBase64: enc.ciphertext,
        ivBase64: enc.iv,
        macBase64: enc.mac,
        masterKey: key,
      );
      expect(dec, orderedEquals(rawBytes));

      CryptoService.wipe(key);
      expect(key.every((b) => b == 0), isTrue);
    });

    test('wipe safely handles both mutable lists and UnmodifiableUint8ListView without throwing', () {
      final backing = Uint8List.fromList([1, 2, 3, 4, 5]);
      final unmodifiable = backing.asUnmodifiableView();
      expect(() => CryptoService.wipe(unmodifiable), returnsNormally);

      final mutable = Uint8List.fromList([9, 8, 7]);
      CryptoService.wipe(mutable);
      expect(mutable, orderedEquals([0, 0, 0]));
    });
  });

  group('Bitwarden KDF, Subkey derivation & CipherString Decryption', () {
    test('hkdfExpandSha256 produces deterministic 32-byte subkeys from PRK and info', () {
      final prk = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final encKey = CryptoService.hkdfExpandSha256(prk, 'enc', 32);
      final macKey = CryptoService.hkdfExpandSha256(prk, 'mac', 32);
      final encKey2 = CryptoService.hkdfExpandSha256(prk, 'enc', 32);

      expect(encKey.length, 32);
      expect(macKey.length, 32);
      expect(CryptoService.constantTimeEquals(encKey, encKey2), isTrue);
      expect(CryptoService.constantTimeEquals(encKey, macKey), isFalse);
    });

    test('deriveBitwardenSubKeys derives encKey and macKey via PBKDF2 and Argon2id', () async {
      final pbkdf2Keys = await crypto.deriveBitwardenSubKeys(
        password: 'TestPassword123!',
        salt: 'alice@example.com',
        kdfType: 0,
        iterations: 1000,
      );
      expect(pbkdf2Keys.encKey.length, 32);
      expect(pbkdf2Keys.macKey.length, 32);
      expect(CryptoService.constantTimeEquals(pbkdf2Keys.encKey, pbkdf2Keys.macKey), isFalse);

      final argonKeys = await crypto.deriveBitwardenSubKeys(
        password: 'TestPassword123!',
        salt: 'bob@example.com',
        kdfType: 1,
        iterations: 1,
        memoryKib: 1024,
        parallelism: 1,
      );
      expect(argonKeys.encKey.length, 32);
      expect(argonKeys.macKey.length, 32);
      expect(CryptoService.constantTimeEquals(argonKeys.encKey, argonKeys.macKey), isFalse);
    });

    test('encryptBitwardenCipherString and decryptBitwardenCipherString round-trip cleanly', () async {
      final subkeys = await crypto.deriveBitwardenSubKeys(
        password: 'ValidPassword!2026',
        salt: 'user@domain.com',
        iterations: 1000,
      );

      const plaintext = '{"title":"Kasa Öğesi 🔑","username":"admin","notes":"Önemli veri"}';
      final cipherString = await crypto.encryptBitwardenCipherString(
        plaintext: plaintext,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );

      expect(cipherString.startsWith('2.'), isTrue);
      final parts = cipherString.substring(2).split('|');
      expect(parts.length, 3);

      final decrypted = await crypto.decryptBitwardenCipherString(
        cipherString: cipherString,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );
      expect(decrypted, equals(plaintext));
    });

    test('decryptBitwardenCipherString detects MAC tampering and protects integrity', () async {
      final subkeys = await crypto.deriveBitwardenSubKeys(
        password: 'ValidPassword!2026',
        salt: 'user@domain.com',
        iterations: 1000,
      );

      final cipherString = await crypto.encryptBitwardenCipherString(
        plaintext: 'Top Secret Information',
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );

      // Tamper MAC by modifying first character of MAC base64 string
      final parts = cipherString.split('|');
      final mac = parts[2];
      final tamperedMac = '${mac[0] == 'A' ? 'B' : 'A'}${mac.substring(1)}';
      final tampered = '${parts[0]}|${parts[1]}|$tamperedMac';

      await expectLater(
        () => crypto.decryptBitwardenCipherString(
          cipherString: tampered,
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('decryptBitwardenCipherString validates structure and throws FormatException on invalid inputs', () async {
      final subkeys = await crypto.deriveBitwardenSubKeys(
        password: 'Pass',
        salt: 'salt@example.com',
        iterations: 1000,
      );

      // Wrong type prefix (1. instead of 2.)
      await expectLater(
        () => crypto.decryptBitwardenCipherString(
          cipherString: '1.aXY=|Y2lwaGVy|bWFj',
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );

      // Missing mac part
      await expectLater(
        () => crypto.decryptBitwardenCipherString(
          cipherString: '2.YWJjZGVmZ2hpamtsbW5vcA==|Y2lwaGVydGV4dA==',
          encKey: subkeys.encKey,
          macKey: subkeys.macKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('decryptBitwardenJson end-to-end parses envelope and decrypts inner folders and items', () async {
      const innerPlaintext = '''
      {
        "folders": [{"id": "f1", "name": "Work"}],
        "items": [
          {
            "id": "i1",
            "name": "Cloud Portal",
            "login": {"username": "admin@work.com", "password": "SecretPass!99"}
          }
        ]
      }
      ''';

      final subkeys = await crypto.deriveBitwardenSubKeys(
        password: 'ExportPassword!2026',
        salt: 'user@work.com',
        iterations: 1000,
      );

      final cipher = await crypto.encryptBitwardenCipherString(
        plaintext: innerPlaintext,
        encKey: subkeys.encKey,
        macKey: subkeys.macKey,
      );

      final rawExport = '''
      {
        "encrypted": true,
        "passwordProtected": true,
        "salt": "user@work.com",
        "kdfType": 0,
        "kdfIterations": 1000,
        "data": "$cipher"
      }
      ''';

      final decrypted = await crypto.decryptBitwardenJson(rawExport, 'ExportPassword!2026');
      expect(decrypted, equals(innerPlaintext));

      // Wrong password throws FormatException
      await expectLater(
        () => crypto.decryptBitwardenJson(rawExport, 'WrongPassword!'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
