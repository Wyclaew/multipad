import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ExtensionInstallerService {
  static const String extensionId = 'multipad@multipad.com';

  /// Resolves the absolute directory path of the extension folder on disk.
  static String? getExtensionDirectoryPath() {
    if (kIsWeb) return null;
    final currentDir = Directory.current.path;
    final candidate = Directory('$currentDir/extension');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    // Check relative to executable on desktop builds
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeCandidate = Directory('$exeDir/extension');
      if (exeCandidate.existsSync()) {
        return exeCandidate.path;
      }
      final dataCandidate = Directory('$exeDir/data/flutter_assets/extension');
      if (dataCandidate.existsSync()) {
        return dataCandidate.path;
      }
    } catch (_) {}
    return candidate.path;
  }

  static String? getManifestPath() {
    final dir = getExtensionDirectoryPath();
    if (dir == null) return null;
    final manifest = File('$dir/manifest.json');
    return manifest.path;
  }

  static String? getXpiPath() {
    final dir = getExtensionDirectoryPath();
    if (dir == null) return null;
    final xpi = File('$dir/multipad-firefox.xpi');
    return xpi.path;
  }

  /// Copies the manifest or XPI path to system clipboard.
  static Future<bool> copyPathToClipboard({bool isFirefox = true}) async {
    final path = isFirefox ? (getManifestPath() ?? getXpiPath()) : getExtensionDirectoryPath();
    if (path == null) return false;
    await Clipboard.setData(ClipboardData(text: path));
    return true;
  }

  /// Launches Firefox directly to about:debugging#/runtime/this-firefox
  static Future<bool> launchFirefoxDebugging() async {
    if (kIsWeb) return false;
    
    // Copy manifest path to clipboard first for convenience
    await copyPathToClipboard(isFirefox: true);

    const url = 'about:debugging#/runtime/this-firefox';
    
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('open', ['-a', 'Firefox', url]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('cmd', ['/c', 'start', 'firefox', url]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    } else if (Platform.isLinux) {
      try {
        final result = await Process.run('firefox', [url]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:48292');
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Launches Chrome / Edge to their extensions page
  static Future<bool> launchChromiumExtensions({bool isEdge = false}) async {
    if (kIsWeb) return false;

    await copyPathToClipboard(isFirefox: false);
    final appName = isEdge ? (Platform.isMacOS ? 'Microsoft Edge' : 'msedge') : (Platform.isMacOS ? 'Google Chrome' : 'chrome');
    final url = isEdge ? 'edge://extensions' : 'chrome://extensions';

    if (Platform.isMacOS) {
      try {
        final result = await Process.run('open', ['-a', appName, url]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('cmd', ['/c', 'start', appName, url]);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Configures Firefox Enterprise Policy (policies.json) so MultiPad extension
  /// loads permanently on every Firefox restart without requiring store approval.
  static Future<bool> installFirefoxPolicy() async {
    if (kIsWeb) return false;
    final xpiPath = getXpiPath();
    if (xpiPath == null || !File(xpiPath).existsSync()) {
      return false;
    }

    final policyData = {
      'policies': {
        'ExtensionSettings': {
          extensionId: {
            'installation_mode': 'normal_installed',
            'install_url': 'file://$xpiPath',
          }
        }
      }
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(policyData);

    try {
      if (Platform.isMacOS) {
        // User-level distribution directory
        final home = Platform.environment['HOME'] ?? '';
        final candidates = [
          Directory('$home/Library/Application Support/Mozilla'),
          Directory('/Library/Application Support/Mozilla'),
        ];
        for (final dir in candidates) {
          try {
            if (!dir.existsSync()) dir.createSync(recursive: true);
            final file = File('${dir.path}/policies.json');
            file.writeAsStringSync(jsonStr);
            return true;
          } catch (_) {}
        }
      } else if (Platform.isWindows) {
        // Standard Firefox distribution dir or local appdata
        final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
        final dir = Directory('$programFiles\\Mozilla Firefox\\distribution');
        try {
          if (!dir.existsSync()) dir.createSync(recursive: true);
          final file = File('${dir.path}\\policies.json');
          file.writeAsStringSync(jsonStr);
          return true;
        } catch (_) {}
      } else if (Platform.isLinux) {
        final dir = Directory('/etc/firefox/policies');
        try {
          if (!dir.existsSync()) dir.createSync(recursive: true);
          final file = File('${dir.path}/policies.json');
          file.writeAsStringSync(jsonStr);
          return true;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('installFirefoxPolicy error: $e');
    }
    return false;
  }
}
