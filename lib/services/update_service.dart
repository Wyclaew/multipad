import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  ReleaseAsset({required this.name, required this.downloadUrl, required this.size});
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
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      return assets.firstWhere(
        (a) => a.name.endsWith('.apk'),
        orElse: () => assets.first,
      );
    } else if (Platform.isMacOS) {
      return assets.firstWhere(
        (a) => a.name.endsWith('.dmg') || a.name.endsWith('.zip'),
        orElse: () => assets.first,
      );
    } else if (Platform.isWindows) {
      return assets.firstWhere(
        (a) => a.name.endsWith('.zip') || a.name.endsWith('.exe'),
        orElse: () => assets.first,
      );
    }
    return assets.isNotEmpty ? assets.first : null;
  }
}

class UpdateService {
  static const String repoOwner = 'Wyclaew';
  static const String repoName = 'multipad';
  static const String currentAppVersion = '1.0.4';

  /// Queries GitHub Releases API to check if a newer release exists.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'MultiPad-App',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final rawTag = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? 'Yeni sürüm yayınlandı.';
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$repoOwner/$repoName/releases';

      final cleanLatest = rawTag.replaceAll('v', '').split('+').first.trim();
      final cleanCurrent = currentAppVersion.replaceAll('v', '').split('+').first.trim();

      final bool isNewer = _isVersionNewer(cleanLatest, cleanCurrent);

      final List<ReleaseAsset> assets = [];
      if (data['assets'] != null) {
        for (final asset in data['assets']) {
          assets.add(ReleaseAsset(
            name: asset['name'] as String? ?? '',
            downloadUrl: asset['browser_download_url'] as String? ?? '',
            size: asset['size'] as int? ?? 0,
          ));
        }
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

  /// Compares semantic version strings e.g. "1.0.3" vs "1.0.2"
  static bool _isVersionNewer(String latest, String current) {
    try {
      final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

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
