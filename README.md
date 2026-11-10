# MultiPad 🔐
### Sıfır-Bilgi (Zero-Knowledge) Uçtan Uca Şifreli Not Defteri ve Şifre Kasası

MultiPad; **Android**, **macOS** ve **Windows** platformlarında çalışan, cihazlar arasında anlık canlı senkronizasyon (Realtime Sync) sağlayan ve **Uçtan Uca Şifreleme (E2EE)** mimarisiyle verilerinizin asla başkaları veya sunucular tarafından okunamayacağı güvenli bir not ve parola yöneticisidir.

---

## 🛡️ Güvenlik & Şifreleme Mimarisi

MultiPad verilerinizi **Sıfır-Bilgi (Zero-Knowledge)** prensibiyle korur:

1. **Ana Şifre (Master Password):**
   - Belirlediğiniz ana şifre **cihazınızdan asla çıkmaz** ve hiçbir sunucuya gönderilmez.
   - Cihazınızda PBKDF2-HMAC-SHA256 (100.000 tur) algoritması ve 32-baytlık kriptografik salt kullanılarak 256-bitlik bir Ana Kasa Şifreleme Anahtarı türetilir.
2. **AES-256-GCM ile Veri Şifreleme:**
   - Her not, parola veya hesap bilgisi sunucuya gönderilmeden önce cihazınızda AES-256-GCM ile şifrelenir.
   - Her işlemde rastgele 12-baytlık tek kullanımlık vektör (IV/Nonce) ve veri bütünlüğünü garanti eden kimlik doğrulama etiketi (MAC) oluşturulur.
   - Supabase bulut veritabanında **yalnızca anlamsız rastgele baytlar (ciphertext)** saklanır. Supabase çalışanları veya veritabanını ele geçiren bir saldırgan verilerinizi asla çözemez.
3. **Biyometrik Kilit (Touch ID / Parmak İzi / Windows Hello):**
   - Ana şifrenizi bir kez girdikten sonra Ayarlar'dan biyometrik kilidi açabilirsiniz.
   - Şifreleme anahtarınız Apple Keychain (macOS) veya Android Keystore donanım güvenlik çipinde saklanır.
   - Uygulamayı açtığınızda parmak izinizi okutarak saniyeler içinde kasanın kilidini açabilirsiniz.
4. **Güvenli Pano (Auto-Clear Clipboard):**
   - Bir şifreyi panoya kopyaladığınızda, 30 saniye sonra sistem panosu otomatik olarak temizlenir. Bu sayede başka uygulamaların şifrenizi panodan okuması engellenir.

---

## 🚀 Kurulum & Başlangıç Rehberi (Senin Yapman Gerekenler)

Uygulamanın cihazların arasında anında senkronize olabilmesi için ücretsiz bir Supabase projesi oluşturman yeterlidir (1-2 dakika sürer, hiçbir kredi kartı gerekmez):

### Adım 1: Ücretsiz Supabase Projesi Açma
1. [supabase.com](https://supabase.com) adresine gidip ücretsiz bir hesap oluşturun.
2. **New Project** butonuna tıklayın, projeye bir isim verin (Örn: `multipad-vault`) ve bir veritabanı şifresi belirleyin.
3. Projeniz 30 saniyede hazır olacaktır.

### Adım 2: Veritabanı Tablolarını Oluşturma
1. Supabase kontrol panelinde sol menüden **SQL Editor** sekmesine tıklayın.
2. **New Query** butonuna basın.
3. Bu projedeki [`supabase/schema.sql`](file:///Users/erne/Desktop/MultiPad/supabase/schema.sql) dosyasının içeriğini kopyalayıp SQL Editor'e yapıştırın ve sağ alttaki **Run** butonuna tıklayın.
*(Bu işlem, şifreli verileri tutacak tabloyu, erişim kuralı politikalarını (RLS) ve anlık senkronizasyonu (Realtime) aktif eder).*

### Adım 3: API Bilgilerini Alma
1. Supabase sol menüsünden **Project Settings** (Dişli çark) -> **API** bölümüne gidin.
2. Burada yer alan:
   - **Project URL** (`https://xxxxxxxxxxxx.supabase.co`)
   - **anon public Key** (`eyJhbGciOiJIUzI1NiIsInR5cCI6...`)
   bilgilerini kopyalayın.
3. Uygulamayı ilk kez açtığınızda bu iki bilgiyi ekrana yapıştırıp **"Kaydet ve Bağlan"** butonuna basmanız yeterlidir. (İsterseniz bu bilgileri `lib/constants.dart` içerisindeki `defaultSupabaseUrl` ve `defaultSupabaseAnonKey` alanlarına da yazabilirsiniz).

---

## 📱 & 💻 Uygulamayı Çalıştırma ve Derleme

### macOS'ta Çalıştırma:
```bash
# Bağımlılıkları yükle
flutter pub get

# macOS masaüstü uygulamasını başlat
flutter run -d macos

# Dağıtım için macOS .app / .dmg derle
flutter build macos --release
```

### Android Telefonda Çalıştırma:
Telefonunuzu USB kablosuyla bağlayın veya emülatörü başlatın:
```bash
# Bağlı cihazları listele
flutter devices

# Android cihazda başlat
flutter run -d <cihaz_id>

# Android APK dosyası oluştur
flutter build apk --release
# Oluşan dosya: build/app/outputs/flutter-apk/app-release.apk
```

### Windows'ta Çalıştırma:
Projeyi Windows bilgisayarınıza kopyaladıktan sonra:
```cmd
flutter pub get
flutter run -d windows
flutter build windows --release
```

---

## 📁 Proje Dizin Yapısı

```
MultiPad/
├── lib/
│   ├── main.dart                       # Uygulama başlangıcı, tema ve kök yönlendirme
│   ├── constants.dart                  # Sabitler ve Supabase varsayılan anahtarları
│   ├── models/
│   │   └── vault_item.dart             # Şifreli Not ve Hesap/Parola veri modeli
│   ├── services/
│   │   ├── crypto_service.dart         # AES-256-GCM ve PBKDF2 kriptografik motor
│   │   ├── biometric_service.dart      # Touch ID / Parmak İzi ve Donanım Anahtarlığı
│   │   ├── supabase_service.dart       # Supabase kimlik doğrulama & Realtime senkronizasyon
│   │   └── clipboard_service.dart      # 30 saniye sonra otomatik temizlenen güvenli pano
│   ├── providers/
│   │   ├── auth_provider.dart          # Kasa kilit durumu ve oturum yönetimi
│   │   └── vault_provider.dart         # Şifreli öğelerin yönetimi, arama ve realtime dinleyici
│   ├── screens/
│   │   ├── auth_screen.dart            # Kasa açılış ekranı (Ana Şifre / Touch ID)
│   │   ├── home_screen.dart            # Ana sayfa (Masaüstü bölünmüş görünüm / Mobil liste)
│   │   ├── note_editor_screen.dart     # Şifreli zengin not editörü
│   │   ├── credential_editor_screen.dart # Şifre/Hesap kartı editörü
│   │   └── settings_screen.dart        # Biyometrik kilit, güvenlik detayları ve ayarlar
│   └── widgets/
│       ├── vault_item_card.dart        # Not ve şifre kartı bileşeni
│       └── password_generator_dialog.dart # Ayarlanabilir güçlü parola üretici
├── supabase/
│   └── schema.sql                      # Supabase SQL kurulum şeması
└── pubspec.yaml                        # Flutter paket bağımlılıkları
```
