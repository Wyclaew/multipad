import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/services/crypto_service.dart';
import 'package:multipad/services/pairing_service.dart';

void main() {
  late CryptoService crypto;
  late PairingService pairing;

  setUp(() {
    crypto = CryptoService();
    pairing = PairingService(crypto);
  });

  PairingPayload samplePayload() => PairingPayload(
    supabaseUrl: 'https://example.supabase.co',
    supabaseAnonKey: 'anon_test_key_123',
    email: 'user@example.com',
    masterSalt: 'argon2id\$v=19\$m=19456,t=2,p=1\$AAAAAAAAAAAAAAAAAAAAAA',
    masterKeyBase64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    offlineItems: [
      {'id': 'item-1', 'encrypted_payload': 'abc', 'item_type': 'note'},
    ],
  );

  group('PairingService Remote Setup Token (MPSETUP)', () {
    test('creates and decrypts setup token cleanly without unmodifiable bytes crash', () async {
      final payload = samplePayload();
      final token = await pairing.createEncryptedSetupToken(
        payload: payload,
        passphrase: 'TransferPin2026!',
      );

      expect(token.startsWith('MPSETUP:'), isTrue);

      final decoded = await pairing.parseEncryptedSetupToken(
        token: token,
        passphrase: 'TransferPin2026!',
      );
      expect(decoded.email, payload.email);
      expect(decoded.supabaseUrl, payload.supabaseUrl);
      expect(decoded.masterSalt, payload.masterSalt);
      expect(decoded.masterKeyBase64, payload.masterKeyBase64);
      expect(decoded.offlineItems.length, 1);
    });

    test('rejects wrong passphrase and malformed setup token', () async {
      final token = await pairing.createEncryptedSetupToken(
        payload: samplePayload(),
        passphrase: 'RightPin99!',
      );

      await expectLater(
        () => pairing.parseEncryptedSetupToken(
          token: token,
          passphrase: 'WrongPin99!',
        ),
        throwsException,
      );

      await expectLater(
        () => pairing.parseEncryptedSetupToken(
          token: 'NOT_A_TOKEN',
          passphrase: 'RightPin99!',
        ),
        throwsException,
      );
    });
  });

  group('PairingService LAN Session & QR URI', () {
    test('pairs over loopback TCP with X25519 + HKDF + AES-GCM without errors', () async {
      final payload = samplePayload();
      PairingHostStatus? lastStatus;

      final session = await pairing.startHostSession(
        payload: payload,
        onStatusChanged: (status, _) => lastStatus = status,
      );

      try {
        expect(session.serverPort, isNotNull);
        expect(session.pin.length, 6);
        expect(session.remainingSeconds, greaterThan(0));

        // Override localIps check via direct loopback test + QR roundtrip test
        final qr = session.buildQrPairingUri();
        expect(qr.startsWith('MPPAIR:v1:'), isTrue);
        final parsedQr = PairingService.parseQrPairingUri(qr);
        expect(parsedQr, isNotNull);
        expect(parsedQr!.port, session.serverPort);
        expect(parsedQr.pin, session.pin);

        final received = await pairing.connectAndPairAny(
          hostIps: ['127.0.0.1'],
          port: session.serverPort!,
          pin: session.pin,
        );

        expect(received.email, payload.email);
        expect(received.masterSalt, payload.masterSalt);
        expect(received.masterKeyBase64, payload.masterKeyBase64);
        expect(received.offlineItems.length, 1);
        expect(lastStatus, PairingHostStatus.paired);
      } finally {
        await session.stop();
      }
    });

    test('locks out host session after 3 wrong PIN attempts', () async {
      PairingHostStatus? lastStatus;
      final session = await pairing.startHostSession(
        payload: samplePayload(),
        onStatusChanged: (status, _) => lastStatus = status,
      );

      try {
        final wrongPin = session.pin == '000000' ? '111111' : '000000';
        for (int attempt = 0; attempt < 3; attempt++) {
          await expectLater(
            () => pairing.connectAndPair(
              hostIp: '127.0.0.1',
              port: session.serverPort!,
              pin: wrongPin,
            ),
            throwsException,
          );
        }
        expect(lastStatus, PairingHostStatus.lockedOut);
        await expectLater(
          () => pairing.connectAndPair(
            hostIp: '127.0.0.1',
            port: session.serverPort!,
            pin: session.pin,
          ),
          throwsException,
        );
      } finally {
        await session.stop();
      }
    });

    test('createEncryptedSetupToken rejects < 6 chars and accepts 6 chars', () async {
      await expectLater(
        () => pairing.createEncryptedSetupToken(
          payload: samplePayload(),
          passphrase: '1234',
        ),
        throwsException,
      );

      final token = await pairing.createEncryptedSetupToken(
        payload: samplePayload(),
        passphrase: '123456',
      );
      expect(token.startsWith('MPSETUP:'), isTrue);

      final decoded = await pairing.parseEncryptedSetupToken(
        token: token,
        passphrase: '123456',
      );
      expect(decoded.email, 'user@example.com');
    });

    test('connectAndPairAny skips unreachable IPs and connects to loopback host', () async {
      final payload = samplePayload();
      final session = await pairing.startHostSession(
        payload: payload,
        onStatusChanged: (_, __) {},
      );

      try {
        // Reserve and immediately close a local port, or pass TEST-NET-2 IP first
        // alongside 127.0.0.1 so concurrent reachability probing picks 127.0.0.1.
        final received = await pairing.connectAndPairAny(
          hostIps: ['192.0.2.1', '127.0.0.1'],
          port: session.serverPort!,
          pin: session.pin,
        );
        expect(received.email, payload.email);
        expect(received.masterKeyBase64, payload.masterKeyBase64);
      } finally {
        await session.stop();
      }
    });

    test('parseQrPairingUri rejects invalid URIs gracefully', () {
      expect(PairingService.parseQrPairingUri('https://example.com'), isNull);
      expect(PairingService.parseQrPairingUri('MPPAIR:v1:onlytwo'), isNull);
      expect(PairingService.parseQrPairingUri('MPPAIR:v1:127.0.0.1:notaport:123456'), isNull);
    });
  });
}
