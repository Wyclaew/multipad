import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multipad/l10n/app_localizations.dart';
import 'package:multipad/models/vault_item.dart';
import 'package:multipad/providers/auth_provider.dart';
import 'package:multipad/providers/vault_provider.dart';
import 'package:multipad/screens/authenticator_screen.dart';
import 'package:multipad/services/audit_service.dart';
import 'package:multipad/services/totp_migration_service.dart';
import 'package:multipad/services/totp_service.dart';
import 'package:provider/provider.dart';

/// Encodes a synthetic Google Authenticator `otpauth-migration://offline?data=...`
/// payload for testing binary Protobuf wire decoding.
String _buildGoogleMigrationUri({
  required List<_TestOtpEntry> entries,
  int version = 1,
  int batchSize = 1,
  int batchIndex = 0,
  int batchId = 42,
  bool urlSafe = false,
  bool replacePlusWithSpace = false,
}) {
  final root = BytesBuilder();

  for (final e in entries) {
    final msg = BytesBuilder();
    _writeBytesField(msg, 1, e.secretBytes);
    if (e.name.isNotEmpty) _writeBytesField(msg, 2, utf8.encode(e.name));
    if (e.issuer.isNotEmpty) _writeBytesField(msg, 3, utf8.encode(e.issuer));
    _writeVarintField(msg, 4, e.algorithmCode);
    _writeVarintField(msg, 5, e.digitsCode);
    _writeVarintField(msg, 6, e.typeCode);
    _writeBytesField(root, 1, msg.toBytes());
  }

  _writeVarintField(root, 2, version);
  _writeVarintField(root, 3, batchSize);
  _writeVarintField(root, 4, batchIndex);
  _writeVarintField(root, 5, batchId);

  var b64 = urlSafe
      ? base64UrlEncode(root.toBytes())
      : base64Encode(root.toBytes());
  if (replacePlusWithSpace) {
    b64 = b64.replaceAll('+', ' ');
  }
  return 'otpauth-migration://offline?data=${Uri.encodeQueryComponent(b64)}';
}

void _writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.addByte(v & 0x7f);
}

void _writeVarintField(BytesBuilder out, int fieldNum, int value) {
  _writeVarint(out, (fieldNum << 3) | 0);
  _writeVarint(out, value);
}

void _writeBytesField(BytesBuilder out, int fieldNum, List<int> bytes) {
  _writeVarint(out, (fieldNum << 3) | 2);
  _writeVarint(out, bytes.length);
  out.add(bytes);
}

class _TestOtpEntry {
  final List<int> secretBytes;
  final String name;
  final String issuer;
  final int algorithmCode; // 1=SHA1, 2=SHA256, 3=SHA512, 4=MD5
  final int digitsCode; // 1=6, 2=8
  final int typeCode; // 1=HOTP, 2=TOTP

  const _TestOtpEntry({
    required this.secretBytes,
    this.name = '',
    this.issuer = '',
    this.algorithmCode = 1,
    this.digitsCode = 1,
    this.typeCode = 2,
  });
}

void main() {
  group('TotpService RFC 6238 SHA-1 / SHA-256 / SHA-512 & URI support', () {
    // RFC 6238 Appendix B exact seeds
    final sha1Seed = utf8.encode('12345678901234567890');
    final sha256Seed = utf8.encode('12345678901234567890123456789012');
    final sha512Seed = utf8.encode(
      '1234567890123456789012345678901234567890123456789012345678901234',
    );

    test('Base32 encode and decode round-trip', () {
      final encoded = TotpService.encodeBase32(sha1Seed);
      expect(encoded, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(TotpService.decodeBase32(encoded), equals(sha1Seed));
    });

    test('RFC 6238 exact test vectors for SHA1, SHA256, SHA512', () {
      final b32Sha1 = TotpService.encodeBase32(sha1Seed);
      final b32Sha256 = TotpService.encodeBase32(sha256Seed);
      final b32Sha512 = TotpService.encodeBase32(sha512Seed);

      expect(
        TotpService.generateCode(
          b32Sha1,
          digits: 8,
          algorithm: TotpAlgorithm.sha1,
          timeMs: 59 * 1000,
        ),
        '94287082',
      );
      expect(
        TotpService.generateCode(
          b32Sha256,
          digits: 8,
          algorithm: TotpAlgorithm.sha256,
          timeMs: 59 * 1000,
        ),
        '46119246',
      );
      expect(
        TotpService.generateCode(
          b32Sha512,
          digits: 8,
          algorithm: TotpAlgorithm.sha512,
          timeMs: 59 * 1000,
        ),
        '90693936',
      );

      expect(
        TotpService.generateCode(
          b32Sha256,
          digits: 8,
          algorithm: TotpAlgorithm.sha256,
          timeMs: 1111111109 * 1000,
        ),
        '68084774',
      );
      expect(
        TotpService.generateCode(
          b32Sha512,
          digits: 8,
          algorithm: TotpAlgorithm.sha512,
          timeMs: 1234567890 * 1000,
        ),
        '93441116',
      );
    });

    test('otpauth URI round-trip & generateDetailed preserves custom parameters', () {
      final b32Sha256 = TotpService.encodeBase32(sha256Seed);
      final stored = TotpService.formatForVaultStorage(
        secret: b32Sha256,
        issuer: 'Binance',
        accountName: 'trader@example.com',
        period: 60,
        digits: 8,
        algorithm: TotpAlgorithm.sha256,
      );
      expect(stored.startsWith('otpauth://totp/'), isTrue);

      final detailed = TotpService.generateDetailed(stored, timeMs: 59 * 1000);
      expect(detailed.isValid, isTrue);
      expect(detailed.algorithm, TotpAlgorithm.sha256);
      expect(detailed.digits, 8);
      expect(detailed.period, 60);
      expect(detailed.formattedCode.length, 9); // "1234 5678"
      expect(detailed.remainingSeconds, 1);
      expect(
        detailed.nextCode,
        TotpService.generateCode(
          stored,
          timeMs: (59 + 60) * 1000,
        ),
      );
    });
  });

  group('TotpMigrationService multi-app parsing & smart merge', () {
    final seed1 = utf8.encode('12345678901234567890');
    final seed2 = utf8.encode('12345678901234567890123456789012');

    test('Decodes Google Authenticator Protobuf single & multi-batch QR exports', () {
      final uriPart1 = _buildGoogleMigrationUri(
        entries: [
          _TestOtpEntry(
            secretBytes: seed1,
            name: 'GitHub:alice@example.com',
            issuer: 'GitHub',
            algorithmCode: 1, // SHA1
            digitsCode: 1, // 6 digits
            typeCode: 2, // TOTP
          ),
          _TestOtpEntry(
            secretBytes: seed1,
            name: 'CounterToken',
            issuer: 'Yubi',
            typeCode: 1, // HOTP -> should skip with warning
          ),
        ],
        batchSize: 2,
        batchIndex: 0,
        urlSafe: true,
      );

      final res1 = TotpMigrationService.parseInput(uriPart1);
      expect(res1.hasError, isFalse);
      expect(res1.googleBatch?.isMultiPart, isTrue);
      expect(res1.googleBatch?.batchSize, 2);
      expect(res1.googleBatch?.batchIndex, 0);
      expect(res1.accounts.length, 1);
      expect(res1.warnings.length, 1);
      expect(res1.accounts.first.issuer, 'GitHub');
      expect(res1.accounts.first.accountName, 'alice@example.com');
      expect(res1.accounts.first.secret, TotpService.encodeBase32(seed1));

      final uriPart2 = _buildGoogleMigrationUri(
        entries: [
          _TestOtpEntry(
            secretBytes: seed2,
            name: 'bob@exchange.io',
            issuer: 'Kraken',
            algorithmCode: 2, // SHA256
            digitsCode: 2, // 8 digits
            typeCode: 2,
          ),
        ],
        batchSize: 2,
        batchIndex: 1,
      );

      final combined = TotpMigrationService.parseInput('$uriPart1\n$uriPart2');
      expect(combined.accounts.length, 2);
      expect(combined.accounts[1].algorithm, TotpAlgorithm.sha256);
      expect(combined.accounts[1].digits, 8);
    });

    test('Parses Aegis plain JSON and rejects encrypted Aegis with actionable message', () {
      final aegisPlain = jsonEncode({
        'version': 1,
        'header': {'slots': null, 'params': null},
        'db': {
          'version': 2,
          'entries': [
            {
              'type': 'totp',
              'name': 'dev@proton.me',
              'issuer': 'Proton',
              'note': 'Recovery kept in vault',
              'info': {
                'secret': 'JBSWY3DPEHPK3PXP',
                'algo': 'SHA512',
                'digits': 6,
                'period': 45,
              },
            },
          ],
        },
      });

      final res = TotpMigrationService.parseInput(aegisPlain);
      expect(res.hasError, isFalse);
      expect(res.accounts.length, 1);
      expect(res.accounts.first.issuer, 'Proton');
      expect(res.accounts.first.algorithm, TotpAlgorithm.sha512);
      expect(res.accounts.first.period, 45);
      expect(res.accounts.first.note, 'Recovery kept in vault');

      final aegisEncrypted = jsonEncode({
        'version': 1,
        'header': {
          'slots': [{'type': 1}],
        },
        'db': 'base64EncryptedPayload==',
      });
      final encRes = TotpMigrationService.parseInput(aegisEncrypted);
      expect(encRes.hasError, isTrue);
      expect(encRes.error, contains('Aegis'));
    });

    test('Parses 2FAS .2fas JSON and Bitwarden JSON', () {
      final twoFas = jsonEncode({
        'schemaVersion': 4,
        'services': [
          {
            'name': 'Cloudflare',
            'secret': 'MFRGGZDFMZTWQ2LK',
            'otp': {
              'account': 'ops@corp.com',
              'digits': 6,
              'period': 30,
              'algorithm': 'SHA256',
              'tokenType': 'TOTP',
            },
          },
        ],
      });
      final twoFasRes = TotpMigrationService.parseInput(twoFas);
      expect(twoFasRes.hasError, isFalse);
      expect(twoFasRes.accounts.length, 1);
      expect(twoFasRes.accounts.first.issuer, 'Cloudflare');
      expect(twoFasRes.accounts.first.algorithm, TotpAlgorithm.sha256);

      final bitwarden = jsonEncode({
        'items': [
          {
            'type': 1,
            'name': 'Discord',
            'login': {
              'username': 'gamer@discord.com',
              'totp':
                  'otpauth://totp/Discord:gamer@discord.com?secret=JBSWY3DPEHPK3PXP&issuer=Discord',
            },
          },
        ],
      });
      final bwRes = TotpMigrationService.parseInput(bitwarden);
      expect(bwRes.hasError, isFalse);
      expect(bwRes.accounts.length, 1);
      expect(bwRes.accounts.first.issuer, 'Discord');
      expect(bwRes.accounts.first.accountName, 'gamer@discord.com');
    });

    test('Smart merge links matching accounts, skips duplicates, and avoids wrong username merges', () {
      final existing = [
        VaultItem(
          id: 'dup-1',
          type: VaultItemType.credential,
          title: 'Google Personal',
          username: 'me@gmail.com',
          password: 'StrongPassword#123',
          totpSecret: 'JBSWY3DPEHPK3PXP',
        ),
        VaultItem(
          id: 'merge-1',
          type: VaultItemType.credential,
          title: 'GitHub',
          username: 'alice@example.com',
          website: 'https://github.com',
          password: 'StrongPassword#456',
        ),
      ];

      const imported = [
        MigratedTotpAccount(
          secret: 'JBSWY3DPEHPK3PXP',
          issuer: 'Google',
          accountName: 'me@gmail.com',
          source: TotpMigrationSource.otpAuthUri,
        ),
        MigratedTotpAccount(
          secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
          issuer: 'GitHub',
          accountName: 'alice@example.com',
          source: TotpMigrationSource.googleAuthenticatorQr,
        ),
        MigratedTotpAccount(
          secret: 'MFRGGZDFMZTWQ2LK',
          issuer: 'GitHub',
          accountName: 'bob@example.com', // Must NOT merge onto Alice
          source: TotpMigrationSource.googleAuthenticatorQr,
        ),
      ];

      final plan = TotpMigrationService.planImport(imported, existing);
      expect(plan.length, 3);

      expect(plan[0].disposition, TotpImportDisposition.skipDuplicate);
      expect(plan[0].selected, isFalse);

      expect(plan[1].disposition, TotpImportDisposition.mergeIntoExisting);
      expect(plan[1].suggestedMergeTarget?.id, 'merge-1');
      expect(plan[1].selected, isTrue);

      expect(plan[2].disposition, TotpImportDisposition.createStandalone);
      expect(plan[2].suggestedMergeTarget, isNull);
      expect(plan[2].selected, isTrue);
    });
  });

  group('AuditService standalone 2FA score immunity', () {
    test('Standalone migrated 2FA entries are not penalized as weak passwords', () {
      final items = [
        VaultItem(
          id: 'p1',
          type: VaultItemType.credential,
          title: 'Main Account',
          username: 'user@site.com',
          password: 'V3ry!Str0ng#UniquePassword99',
          totpSecret: 'JBSWY3DPEHPK3PXP',
          website: 'https://site.com',
        ),
        VaultItem(
          id: 't1',
          type: VaultItemType.credential,
          title: 'Google Authenticator Import 1',
          username: 'alice@example.com',
          totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
          tags: const ['2FA'],
        ),
        VaultItem(
          id: 't2',
          type: VaultItemType.credential,
          title: '2FAS Import 2',
          username: 'bob@example.com',
          totpSecret: 'MFRGGZDFMZTWQ2LK',
          tags: const ['2FA'],
        ),
      ];

      expect(items[1].isTotpOnly, isTrue);
      final report = AuditService.analyzeVault(items);
      expect(report.totalAccounts, 1);
      expect(report.weakPasswordsCount, 0);
      expect(report.missing2faCount, 0);
      expect(report.overallScore, 100);
    });
  });

  group('AuthenticatorScreen widget & migration UI flow', () {
    testWidgets('AuthenticatorScreen imports Google Authenticator URI via Paste and shows live code', (tester) async {
      final auth = AuthProvider();
      final vault = VaultProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider.value(value: vault),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('tr'), Locale('en')],
            home: AuthenticatorScreen(),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('No 2FA Authenticator Codes Yet'), findsOneWidget);

      await tester.tap(find.text('Import from Other Apps'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      final migrationUri = _buildGoogleMigrationUri(
        entries: [
          _TestOtpEntry(
            secretBytes: utf8.encode('12345678901234567890'),
            name: 'alice@multipad.dev',
            issuer: 'MultiPad Test',
          ),
        ],
      );

      await tester.enterText(find.byType(TextField).last, migrationUri);
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();

      expect(find.text('MultiPad Test'), findsOneWidget);
      expect(find.text('alice@multipad.dev'), findsOneWidget);
      expect(find.text('Import 1 2FA Accounts'), findsOneWidget);
    });
  });
}
