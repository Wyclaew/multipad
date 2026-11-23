import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/vault_provider.dart';
import '../widgets/pending_capture_dialog.dart';
import 'native_bridge_service.dart';

class PendingCaptureCoordinator {
  static bool _isChecking = false;

  /// Inspects native autofill capture storage when the vault is unlocked.
  /// Shows responsive capture confirmation UI if pending credentials exist,
  /// and clears the native queue afterwards.
  static Future<void> checkAndShow(BuildContext context) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (_isChecking) return;

    try {
      final auth = context.read<AuthProvider>();
      if (!auth.isUnlocked) return;

      final vault = context.read<VaultProvider>();
      if (vault.isLoading) return;

      _isChecking = true;

      final pending = await NativeBridgeService.getPendingAutofillCredentials();
      if (pending.isEmpty) return;

      for (final captured in pending) {
        if (!context.mounted) break;

        final website = (captured['website'] as String? ?? '').trim();
        final username = (captured['username'] as String? ?? '').trim();
        final password = (captured['password'] as String? ?? '').trim();
        final packageName = (captured['packageName'] as String? ?? '').trim();

        final existing = vault.findMatchingCredential(
          website: website,
          username: username,
          packageName: packageName.isNotEmpty ? packageName : null,
        );

        // If existing credential has identical password, skip prompt
        if (existing != null && existing.password == password) {
          continue;
        }

        if (context.mounted) {
          await PendingCaptureDialog.show(
            context,
            captured: captured,
            existingItem: existing,
          );
        }
      }

      await NativeBridgeService.clearPendingAutofillCredentials();
    } catch (e) {
      debugPrint('PendingCaptureCoordinator.checkAndShow error: $e');
    } finally {
      _isChecking = false;
    }
  }
}
