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
        (a) => a.name.toLowerCase().endsWith('.dmg'),
        orElse: () => assets.firstWhere(
          (a) =>
              (a.name.toLowerCase().contains('mac') &&
                  a.name.toLowerCase().endsWith('.zip')) ||
              a.name.toLowerCase().endsWith('.zip'),
          orElse: () => assets.first,
        ),
      );
    } else if (Platform.isWindows) {
      return assets.firstWhere(
        (a) =>
            a.name.toLowerCase().endsWith('-setup.exe') ||
            a.name.toLowerCase().endsWith('.exe'),
        orElse: () => assets.firstWhere(
          (a) => a.name.toLowerCase().endsWith('.zip'),
          orElse: () => assets.first,
        ),
      );
    }
    return assets.first;
  }
}

class UpdateService {
  static const String repoOwner = 'Wyclaew';
  static const String repoName = 'multipad';
  static const String currentAppVersion = AppConstants.appVersion;
  static String? lastErrorMessage;

  /// Queries GitHub Releases API to check if a newer release exists and resolves SHA-256 digests.
  static Future<UpdateInfo?> checkForUpdate({String? customToken}) async {
    lastErrorMessage = null;
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'MultiPad-App',
      };
      if (customToken != null && customToken.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${customToken.trim()}';
      }

      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          lastErrorMessage =
              'Sunucuda sürüm bulunamadı (404 Not Found). GitHub deposu gizli (Private) moddaysa genel güncelleme denetimi yapılamaz.';
        } else if (response.statusCode == 403) {
          lastErrorMessage =
              'GitHub API istek sınırı aşıldı (403 Forbidden). Lütfen birkaç dakika sonra tekrar deneyin.';
        } else {
          lastErrorMessage =
              'Güncelleme sunucusu hata verdi (HTTP ${response.statusCode}).';
        }
        return null;
      }

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
    } on TimeoutException {
      lastErrorMessage =
          'Güncelleme sunucusuna bağlanırken zaman aşımı oluştu. Lütfen internet bağlantınızı kontrol edin.';
      return null;
    } on SocketException {
      lastErrorMessage =
          'İnternet bağlantısı kurulamadı. Lütfen ağ bağlantınızı kontrol edin.';
      return null;
    } catch (e) {
      debugPrint('Update check error: $e');
      lastErrorMessage = 'Güncelleme denetlenirken hata oluştu: $e';
      return null;
    }
  }

  /// Downloads the platform release asset, verifies its SHA-256 checksum if available,
  /// and triggers the native installer (Android FileProvider APK / macOS DMG / Windows ZIP updater).
  static Future<String> downloadAndInstall(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool inPlace = false,
    bool installImmediately = true,
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
    bool usedCachedFile = false;
    final hasExpectedSha =
        asset.expectedSha256 != null && asset.expectedSha256!.isNotEmpty;

    // Cache verification: if file exists and SHA-256 matches, reuse it directly
    if (destFile.existsSync()) {
      if (hasExpectedSha) {
        try {
          final existingBytes = await destFile.readAsBytes();
          final existingSha = CryptoService.sha256HexBytes(existingBytes).toLowerCase();
          if (existingSha == asset.expectedSha256!.toLowerCase()) {
            usedCachedFile = true;
            onStatus?.call('Doğrulanmış dosya önbellekten yükleniyor...');
            onProgress?.call(1.0);
          }
        } catch (_) {}
      }
      if (!usedCachedFile) {
        await destFile.delete();
      }
    }

    if (!usedCachedFile) {
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
      if (hasExpectedSha) {
        if (actualSha != asset.expectedSha256!.toLowerCase()) {
          await destFile.delete();
          throw Exception(
            'SHA-256 doğrulama hatası! İndirilen dosya bozuk veya değiştirilmiş olabilir.',
          );
        }
      }
    }

    if (!installImmediately) {
      return destFile.path;
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
      if (inPlace) {
        return installMacOsInPlace(
          destFile.path,
          shaNote: shaNote,
          detachedStarter: detachedProcessStarter,
          tempDirProvider: tempDirProvider,
        );
      }
      return openMacOsInstaller(
        destFile.path,
        shaNote: shaNote,
        startDetached: detachedProcessStarter,
      );
    } else if (isMacOsOverride != true && Platform.isWindows) {
      if (inPlace) {
        return installWindowsInPlace(
          destFile.path,
          shaNote: shaNote,
          detachedStarter: detachedProcessStarter,
          tempDirProvider: tempDirProvider,
        );
      }
      if (destFile.path.toLowerCase().endsWith('.exe')) {
        await _launchWindowsInstaller(
          destFile.path,
          detachedStarter: detachedProcessStarter,
          tempDirProvider: tempDirProvider,
        );
      } else {
        await _launchWindowsUpdater(
          destFile.path,
          detachedStarter: detachedProcessStarter,
          tempDirProvider: tempDirProvider,
        );
      }
      Timer(const Duration(milliseconds: 350), () => exit(0));
      return 'Güncelleme hazırlandı$shaNote; uygulama yeniden başlatılıyor...';
    }

    return destFile.path;
  }

  /// Detects the running .app bundle path by traversing parent directories of [Platform.resolvedExecutable],
  /// or falls back to '/Applications/MultiPad.app'.
  static String getMacOsAppBundlePath({String? executablePath}) {
    final exePath = executablePath ?? Platform.resolvedExecutable;
    var dir = Directory(exePath);
    while (dir.path != '/' && dir.path != '.') {
      if (dir.path.endsWith('.app')) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return '/Applications/MultiPad.app';
  }

  /// Installs an update in-place on macOS via a detached bash helper script:
  /// mounts DMG quietly, strips quarantine (xattr -cr), copies with ditto to staging,
  /// moves atomically into place (mv), detaches DMG, and relaunches with open -a.
  static Future<String> installMacOsInPlace(
    String dmgOrZipPath, {
    String shaNote = '',
    Future<void> Function(String executable, List<String> arguments)?
        detachedStarter,
    String? targetAppPath,
    int? processPid,
    bool exitOnComplete = true,
    @visibleForTesting Future<Directory> Function()? tempDirProvider,
  }) async {
    final currentPid = processPid ?? pid;
    final targetApp = targetAppPath ?? getMacOsAppBundlePath();
    final tmpDir = (await (tempDirProvider != null
            ? tempDirProvider()
            : getTemporaryDirectory()))
        .path;
    final scriptFile = File(p.join(tmpDir, 'multipad_mac_update.sh'));

    final scriptContent = '''
#!/bin/bash
set -e
PID="$currentPid"
PKG="$dmgOrZipPath"
TARGET="$targetApp"

if [ -n "\$PID" ] && [ "\$PID" -gt 0 ] 2>/dev/null; then
  while kill -0 "\$PID" 2>/dev/null; do
    sleep 0.2
  done
fi

MOUNT_DIR="/tmp/multipad_dmg_mount_\$\$"
mkdir -p "\$MOUNT_DIR"

cleanup() {
  if [ -d "\$MOUNT_DIR" ]; then
    hdiutil detach "\$MOUNT_DIR" -force 2>/dev/null || true
    rm -rf "\$MOUNT_DIR"
  fi
}
trap cleanup EXIT

SRC_APP=""
if [[ "\$PKG" == *.dmg ]]; then
  hdiutil attach "\$PKG" -mountpoint "\$MOUNT_DIR" -nobrowse -readonly -quiet
  SRC_APP="\$MOUNT_DIR/MultiPad.app"
  if [ ! -d "\$SRC_APP" ]; then
    SRC_APP=\$(find "\$MOUNT_DIR" -maxdepth 2 -name "*.app" | head -n 1)
  fi
elif [[ "\$PKG" == *.zip ]]; then
  unzip -q -o "\$PKG" -d "\$MOUNT_DIR"
  SRC_APP=\$(find "\$MOUNT_DIR" -maxdepth 2 -name "*.app" | head -n 1)
fi

if [ -z "\$SRC_APP" ] || [ ! -d "\$SRC_APP" ]; then
  open "\$PKG"
  exit 1
fi

xattr -cr "\$SRC_APP" 2>/dev/null || true

TARGET_DIR=\$(dirname "\$TARGET")
STAGE_DIR="\$TARGET_DIR/.MultiPad_updating.app"
rm -rf "\$STAGE_DIR"
ditto "\$SRC_APP" "\$STAGE_DIR"

BACKUP_DIR="\$TARGET_DIR/.MultiPad_old.app"
rm -rf "\$BACKUP_DIR"
if [ -d "\$TARGET" ]; then
  mv "\$TARGET" "\$BACKUP_DIR"
fi

if mv "\$STAGE_DIR" "\$TARGET"; then
  rm -rf "\$BACKUP_DIR"
else
  if [ -d "\$BACKUP_DIR" ]; then
    mv "\$BACKUP_DIR" "\$TARGET"
  fi
  open "\$PKG"
  exit 1
fi

cleanup
open -a "\$TARGET"
''';

    await scriptFile.writeAsString(scriptContent);
    try {
      await Process.run('chmod', ['+x', scriptFile.path]);
    } catch (_) {}

    if (detachedStarter != null) {
      await detachedStarter('/bin/bash', [scriptFile.path]);
    } else {
      await Process.start('/bin/bash', [scriptFile.path],
          mode: ProcessStartMode.detached);
      if (exitOnComplete) {
        Timer(const Duration(milliseconds: 350), () => exit(0));
      }
    }
    return 'MultiPad güncelleniyor ve yeniden başlatılıyor$shaNote...';
  }

  /// Installs an update in-place on Windows.
  /// If the file is an .exe installer, launches Inno Setup installer silently and relaunches.
  /// If .zip, falls back to archive extraction into executable directory.
  static Future<String> installWindowsInPlace(
    String installerOrZipPath, {
    String shaNote = '',
    Future<void> Function(String executable, List<String> arguments)?
        detachedStarter,
    int? processPid,
    bool exitOnComplete = true,
    @visibleForTesting Future<Directory> Function()? tempDirProvider,
  }) async {
    if (installerOrZipPath.toLowerCase().endsWith('.exe')) {
      await _launchWindowsInstaller(
        installerOrZipPath,
        detachedStarter: detachedStarter,
        processPid: processPid,
        tempDirProvider: tempDirProvider,
      );
    } else {
      await _launchWindowsUpdater(
        installerOrZipPath,
        detachedStarter: detachedStarter,
        processPid: processPid,
        tempDirProvider: tempDirProvider,
      );
    }
    if (detachedStarter == null && exitOnComplete) {
      Timer(const Duration(milliseconds: 350), () => exit(0));
    }
    return 'MultiPad güncelleniyor ve yeniden başlatılıyor$shaNote...';
  }

  static Future<void> _launchWindowsInstaller(
    String installerPath, {
    Future<void> Function(String executable, List<String> arguments)?
        detachedStarter,
    int? processPid,
    @visibleForTesting Future<Directory> Function()? tempDirProvider,
  }) async {
    final currentPid = processPid ?? pid;
    final tmpDir = (await (tempDirProvider != null
            ? tempDirProvider()
            : getTemporaryDirectory()))
        .path;
    final scriptFile = File(p.join(tmpDir, 'multipad_run_installer.ps1'));
    final psInstaller = _psQuote(installerPath);

    final psScript = '''
\$ErrorActionPreference = 'SilentlyContinue'
if ($currentPid -gt 0) {
  Wait-Process -Id $currentPid -Timeout 15 -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 500
Start-Process -FilePath $psInstaller -ArgumentList '/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'
''';
    await scriptFile.writeAsString(psScript);
    if (detachedStarter != null) {
      await detachedStarter('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ]);
    } else {
      await Process.start(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
        mode: ProcessStartMode.detached,
      );
    }
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

  static Future<void> _launchWindowsUpdater(
    String zipPath, {
    Future<void> Function(String executable, List<String> arguments)?
        detachedStarter,
    int? processPid,
    @visibleForTesting Future<Directory> Function()? tempDirProvider,
  }) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final tmpDir = (await (tempDirProvider != null
            ? tempDirProvider()
            : getTemporaryDirectory()))
        .path;
    final extractDir = p.join(tmpDir, 'multipad_win_stage');
    final scriptFile = File(p.join(tmpDir, 'multipad_self_update.ps1'));
    final currentPid = processPid ?? pid;
    final exePath = Platform.resolvedExecutable;

    final psExtract = _psQuote(extractDir);
    final psZip = _psQuote(zipPath);
    final psExeDir = _psQuote(exeDir);
    final psExePath = _psQuote(exePath);

    final psScript = '''
\$ErrorActionPreference = 'Stop'
if ($currentPid -gt 0) {
  Wait-Process -Id $currentPid -Timeout 15 -ErrorAction SilentlyContinue
}
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
    if (detachedStarter != null) {
      await detachedStarter('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ]);
    } else {
      await Process.start(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
        mode: ProcessStartMode.detached,
      );
    }
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
