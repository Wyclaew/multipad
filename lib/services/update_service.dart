import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants.dart';
import 'crypto_service.dart';
import 'native_bridge_service.dart';

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;
  final String? expectedSha256;

  ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    this.expectedSha256,
  });
}

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.assets,
  });

  /// Helper to get the platform-specific download asset
  ReleaseAsset? get platformAsset {
    if (kIsWeb || assets.isEmpty) return null;
    if (Platform.isAndroid) {
      return assets.firstWhere(
        (a) => a.name.toLowerCase().endsWith('.apk'),
        orElse: () => assets.first,
      );
    } else if (Platform.isMacOS) {
      return assets.firstWhere(
        (a) =>
            a.name.toLowerCase().endsWith('.dmg') ||
            a.name.toLowerCase().endsWith('.zip'),
        orElse: () => assets.first,
      );
    } else if (Platform.isWindows) {
      return assets.firstWhere(
        (a) =>
            a.name.toLowerCase().endsWith('.zip') ||
            a.name.toLowerCase().endsWith('.exe'),
        orElse: () => assets.first,
      );
    }
    return assets.first;
  }
}

class UpdateService {
  static const String repoOwner = 'Wyclaew';
  static const String repoName = 'multipad';
  static const String currentAppVersion = AppConstants.appVersion;

  /// Queries GitHub Releases API to check if a newer release exists and resolves SHA-256 digests.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'MultiPad-App',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTag = data['tag_name'] as String? ?? '';
      final releaseNotes =
          data['body'] as String? ?? 'Yeni sürüm yayınlandı.';
      final htmlUrl = data['html_url'] as String? ??
          'https://github.com/$repoOwner/$repoName/releases';

      final cleanLatest = rawTag.replaceAll('v', '').split('+').first.trim();
      final cleanCurrent =
          currentAppVersion.replaceAll('v', '').split('+').first.trim();
      final bool isNewer = isVersionNewer(cleanLatest, cleanCurrent);

      // Parse SHA256SUMS.txt if present in release assets
      final Map<String, String> shaSums = {};
      final rawAssets = (data['assets'] as List<dynamic>?) ?? const [];
      String? shaSumsUrl;
      for (final raw in rawAssets) {
        final name = (raw['name'] as String? ?? '').trim();
        if (name.toUpperCase() == 'SHA256SUMS.TXT') {
          shaSumsUrl = raw['browser_download_url'] as String?;
          break;
        }
      }
      if (shaSumsUrl != null && shaSumsUrl.isNotEmpty) {
        try {
          final sumsRes = await http
              .get(Uri.parse(shaSumsUrl))
              .timeout(const Duration(seconds: 6));
          if (sumsRes.statusCode == 200) {
            shaSums.addAll(parseSha256Sums(sumsRes.body));
          }
        } catch (_) {}
      }

      final List<ReleaseAsset> assets = [];
      for (final asset in rawAssets) {
        final name = asset['name'] as String? ?? '';
        if (name.toUpperCase() == 'SHA256SUMS.TXT') continue;
        String? digest = asset['digest'] as String?;
        if (digest != null && digest.startsWith('sha256:')) {
          digest = digest.substring('sha256:'.length).toLowerCase();
        } else {
          digest = shaSums[name];
        }
        assets.add(ReleaseAsset(
          name: name,
          downloadUrl: asset['browser_download_url'] as String? ?? '',
          size: asset['size'] as int? ?? 0,
          expectedSha256: digest,
        ));
      }

      return UpdateInfo(
        hasUpdate: isNewer,
        currentVersion: 'v$cleanCurrent',
        latestVersion: rawTag.isNotEmpty ? rawTag : 'v$cleanLatest',
        releaseNotes: releaseNotes,
        htmlUrl: htmlUrl,
        assets: assets,
      );
    } catch (e) {
      debugPrint('Update check error: $e');
      return null;
    }
  }

  /// Downloads the platform release asset, verifies its SHA-256 checksum if available,
  /// and triggers the native installer (Android FileProvider APK / macOS DMG / Windows ZIP updater).
  static Future<String> downloadAndInstall(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    @visibleForTesting http.Client? httpClient,
    @visibleForTesting Future<Directory> Function()? tempDirProvider,
    @visibleForTesting
    Future<void> Function(String executable, List<String> arguments)?
        detachedProcessStarter,
    @visibleForTesting bool? isMacOsOverride,
  }) async {
    if (kIsWeb) {
      throw Exception('Web platformunda otomatik güncelleme desteklenmez.');
    }

    onStatus?.call('${asset.name} indiriliyor...');
    final tmpDir = await (tempDirProvider != null
        ? tempDirProvider()
        : getTemporaryDirectory());
    final safeFileName = p.basename(asset.name);
    final destFile = File(p.join(tmpDir.path, 'multipad_update_$safeFileName'));
    if (destFile.existsSync()) {
      await destFile.delete();
    }

    final ownsClient = httpClient == null;
    final client = httpClient ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      request.headers['User-Agent'] = 'MultiPad-Updater';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('İndirme başarısız (HTTP ${response.statusCode}).');
      }

      final totalBytes = response.contentLength ?? asset.size;
      var receivedBytes = 0;
      final sink = destFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call((receivedBytes / totalBytes).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      if (ownsClient) {
        client.close();
      }
    }

    // Verify SHA-256 integrity
    onStatus?.call('SHA-256 bütünlük doğrulaması yapılıyor...');
    final fileBytes = await destFile.readAsBytes();
    final actualSha = CryptoService.sha256HexBytes(fileBytes).toLowerCase();
    final hasExpectedSha =
        asset.expectedSha256 != null && asset.expectedSha256!.isNotEmpty;
    if (hasExpectedSha) {
      if (actualSha != asset.expectedSha256!.toLowerCase()) {
        await destFile.delete();
        throw Exception(
          'SHA-256 doğrulama hatası! İndirilen dosya bozuk veya değiştirilmiş olabilir.',
        );
      }
    }

    final shaNote = hasExpectedSha
        ? ' (SHA-256 doğrulandı)'
        : ' (SHA-256 özeti sağlanmadı)';

    onStatus?.call('Kurulum başlatılıyor...');
    final isMacOs = isMacOsOverride ?? Platform.isMacOS;
    if (isMacOsOverride != true && Platform.isAndroid) {
      await NativeBridgeService.installAndroidApk(destFile.path);
      return 'APK yükleyicisi başlatıldı$shaNote.';
    } else if (isMacOs) {
      return openMacOsInstaller(
        destFile.path,
        shaNote: shaNote,
        startDetached: detachedProcessStarter,
      );
    } else if (isMacOsOverride != true && Platform.isWindows) {
      await _launchWindowsUpdater(destFile.path);
      Timer(const Duration(milliseconds: 350), () => exit(0));
      return 'Güncelleme hazırlandı$shaNote; uygulama yeniden başlatılıyor...';
    }

    return destFile.path;
  }

  @visibleForTesting
  static Future<String> openMacOsInstaller(
    String filePath, {
    String shaNote = '',
    Future<void> Function(String executable, List<String> arguments)?
        startDetached,
  }) async {
    if (startDetached != null) {
      await startDetached('open', [filePath]);
    } else {
      await Process.start('open', [filePath], mode: ProcessStartMode.detached);
    }
    return 'DMG disk kalıbı açıldı$shaNote. MultiPad.app dosyasını Applications klasörüne sürükleyin ve ilk açılışta "Sağ tık -> Aç" veya "Sistem Ayarları -> Gizlilik ve Güvenlik -> Yine de Aç" adımlarını izleyin.';
  }

  static Map<String, String> parseSha256Sums(String body) {
    final Map<String, String> shaSums = {};
    for (final line in body.split('\n')) {
      final m = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (m != null) {
        shaSums[p.basename(m.group(2)!.trim())] = m.group(1)!.toLowerCase();
      }
    }
    return shaSums;
  }

  static String _psQuote(String value) =>
      "'${value.replaceAll("'", "''")}'";

  static Future<void> _launchWindowsUpdater(String zipPath) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final tmpDir = (await getTemporaryDirectory()).path;
    final extractDir = p.join(tmpDir, 'multipad_win_stage');
    final scriptFile = File(p.join(tmpDir, 'multipad_self_update.ps1'));
    final currentPid = pid;
    final exePath = Platform.resolvedExecutable;

    final psExtract = _psQuote(extractDir);
    final psZip = _psQuote(zipPath);
    final psExeDir = _psQuote(exeDir);
    final psExePath = _psQuote(exePath);

    final psScript = '''
\$ErrorActionPreference = 'Stop'
Wait-Process -Id $currentPid -Timeout 15 -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 600
\$extractDir = $psExtract
\$zipPath = $psZip
\$exeDir = $psExeDir
\$exePath = $psExePath
if (Test-Path -LiteralPath \$extractDir) { Remove-Item -LiteralPath \$extractDir -Recurse -Force }
Expand-Archive -LiteralPath \$zipPath -DestinationPath \$extractDir -Force
\$srcRoot = \$extractDir
\$nestedExe = Get-ChildItem -LiteralPath \$extractDir -Filter 'multipad.exe' -Recurse | Select-Object -First 1
if (\$nestedExe) { \$srcRoot = \$nestedExe.Directory.FullName }
Copy-Item -Path (Join-Path \$srcRoot '*') -Destination \$exeDir -Recurse -Force
Start-Process -FilePath \$exePath
''';
    await scriptFile.writeAsString(psScript);
    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
      mode: ProcessStartMode.detached,
    );
  }

  /// Compares semantic version strings e.g. "1.1.0" vs "1.0.4"
  static bool isVersionNewer(String latest, String current) {
    try {
      final lParts =
          latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts =
          current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }
}
