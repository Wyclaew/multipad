import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../constants.dart';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    wOptions: WindowsOptions(
      useBackwardCompatibility: true,
    ),
  );

  /// Check whether device hardware supports biometrics (Fingerprint / Touch ID / Face ID)
  Future<bool> canCheckBiometrics() async {
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Get list of available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Authenticate user using biometric prompt (Touch ID / Fingerprint)
  Future<bool> authenticate({String reason = 'MultiPad kasanızı açmak için onaylayın'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Check if user has enabled biometric unlock in the app
  Future<bool> isBiometricUnlockEnabled() async {
    final String? enabled = await _secureStorage.read(key: AppConstants.keyBiometricEnabled);
    return enabled == 'true';
  }

  /// Save Master Key into Hardware Enclave (Keychain / Keystore) protected by biometrics
  Future<void> enableBiometrics(List<int> masterKey) async {
    final String keyBase64 = base64Encode(masterKey);
    await _secureStorage.write(key: AppConstants.keyBiometricMasterKey, value: keyBase64);
    await _secureStorage.write(key: AppConstants.keyBiometricEnabled, value: 'true');
  }

  /// Disable biometric unlock and purge key from secure storage
  Future<void> disableBiometrics() async {
    await _secureStorage.delete(key: AppConstants.keyBiometricMasterKey);
    await _secureStorage.write(key: AppConstants.keyBiometricEnabled, value: 'false');
  }

  /// Retrieve stored Master Key after successful biometric prompt
  Future<List<int>?> retrieveBiometricMasterKey() async {
    final bool isEnabled = await isBiometricUnlockEnabled();
    if (!isEnabled) return null;

    final bool authenticated = await authenticate(
      reason: 'MultiPad kasanızın şifresini çözmek için Touch ID / Parmak izinizi okutun',
    );

    if (authenticated) {
      final String? keyBase64 = await _secureStorage.read(key: AppConstants.keyBiometricMasterKey);
      if (keyBase64 != null) {
        return base64Decode(keyBase64);
      }
    }
    return null;
  }
}
