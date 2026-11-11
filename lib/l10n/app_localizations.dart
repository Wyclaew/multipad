import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  bool get isEnglish => locale.languageCode == 'en';

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('tr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String tr(String trText, String enText) => isEnglish ? enText : trText;

  // Common labels
  String get appTitle => 'MultiPad';
  String get cancel => tr('İptal', 'Cancel');
  String get save => tr('Kaydet', 'Save');
  String get delete => tr('Sil', 'Delete');
  String get confirm => tr('Onayla', 'Confirm');
  String get close => tr('Kapat', 'Close');
  String get add => tr('Ekle', 'Add');
  String get edit => tr('Düzenle', 'Edit');
  String get copy => tr('Kopyala', 'Copy');
  String get copied => tr('Kopyalandı', 'Copied');
  String get search => tr('Kasanızda arayın...', 'Search your vault...');
  String get settings => tr('Ayarlar', 'Settings');
  String get lockVault => tr('Kasayı Kilitle', 'Lock Vault');
  String get logout => tr('Çıkış Yap', 'Sign Out');
  String get audit => tr('Güvenlik Denetimi', 'Security Audit');
  String get trash => tr('Çöp Kutusu', 'Trash');
  String get backup => tr('Yedekleme ve Geri Yükleme', 'Backup & Restore');
  String get importPasswords =>
      tr('Diğer Yöneticilerden İçe Aktar', 'Import Passwords');
  String get devicePairing => tr('Cihaz Eşleştirme', 'Device Pairing');
  String get authenticator => tr('2FA Kodları', '2FA Authenticator');
  String get securityLogs => tr('Güvenlik Olay Günlüğü', 'Security Event Log');
  String get conflictsTitle =>
      tr('Senkronizasyon Çakışmaları', 'Sync Conflicts');

  // Auth & Unlock
  String get login => tr('Giriş Yap / Kasayı Aç', 'Sign In / Unlock Vault');
  String get register => tr('Yeni Hesap Oluştur', 'Create Account');
  String get quickPin => tr('Hızlı PIN', 'Quick PIN');
  String get unlockWithPin => tr('PIN ile Kasayı Aç', 'Unlock with PIN');
  String get mfaTitle => tr('İki Adımlı Doğrulama (2FA)', 'Two-Factor Verification');
  String get mfaPrompt => tr(
        'Authenticator uygulamanızdaki 6 haneli doğrulama kodunu girin.',
        'Enter the 6-digit code from your authenticator app.',
      );

  // Vault Categories & Organization
  String get catAll => tr('Tümü', 'All');
  String get catNotes => tr('Notlar', 'Notes');
  String get catCredentials => tr('Hesaplar', 'Logins');
  String get catCards => tr('Kartlar', 'Cards');
  String get catSecrets => tr('Gizliler', 'Secrets');
  String get catWifi => tr('Wi-Fi', 'Wi-Fi');
  String get catIdentity => tr('Kimlik/Pasaport', 'ID / Passport');
  String get catLicense => tr('Lisanslar', 'Licenses');
  String get catFavorites => tr('Favoriler', 'Favorites');
  String get folders => tr('Klasörler', 'Folders');
  String get newFolder => tr('Yeni Klasör', 'New Folder');
  String get allFolders => tr('Tüm Klasörler', 'All Folders');

  // Settings sections
  String get secSecurity => tr('Güvenlik ve Gizlilik', 'Security & Privacy');
  String get secAppearance => tr('Görünüm ve Dil', 'Appearance & Language');
  String get secPlatform =>
      tr('Platform ve Sistem Özellikleri', 'Platform & Native Features');
  String get secData =>
      tr('Veri Yönetimi ve Güncellemeler', 'Data & Updates');

  String copiedWithTimeout(String label, int timeoutSeconds) {
    if (timeoutSeconds <= 0) {
      return tr(
        '$label kopyalandı (otomatik pano temizleme kapalı).',
        '$label copied (auto-clear disabled).',
      );
    }
    return tr(
      '$label kopyalandı ($timeoutSeconds sn sonra panodan silinecek).',
      '$label copied (clears from clipboard in ${timeoutSeconds}s).',
    );
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'tr' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension L10nContextExt on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
