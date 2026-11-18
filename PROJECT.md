# Project: MultiPad Security & Ergonomics Enhancement

## Architecture
MultiPad is a cross-platform, zero-knowledge password manager built with Flutter (Dart 3.13 / Flutter 3.47), Kotlin (Android platform channels & AutofillService), Swift (macOS runner), and cryptographic primitives (Argon2id, PBKDF2, AES-256-GCM, AES-256-CBC with HMAC-SHA256).

### System Components
1. **Core Flutter App (`lib/`)**:
   - `AuthProvider`: Master key lifecycle, biometric authentication, quick PIN, 2FA interval enforcement, auto-lock suppression.
   - `VaultProvider`: Item caching, concurrent decryption, offline-first loading, filtering, A-Z sorting, sync reconciliation.
   - `SettingsProvider`: Auto-lock duration, background lock preferences (desktop vs mobile), 2FA re-prompt days.
   - `ImportService` & `CryptoService`: Multi-format vault import, format inspection, Bitwarden encrypted JSON decryption (PBKDF2/Argon2 + HKDF-Expand + AES-256-CBC HMAC-SHA256).
   - `AuditService`: Vault hygiene checks (weak, reused, expired, phishing, compromised credentials) without penalizing absence of 2FA.
   - `BrowserBridgeService`: Local authenticated loopback HTTP/WebSocket bridge (`127.0.0.1:48292`) connecting desktop browser extensions to the unlocked vault.
   - `UI Layer`: `AuthScreen` (startup biometric trigger + bottom-right FAB), `HomeScreen` (3-pane Bitwarden-style master-detail, read-only detail pane, quick actions), `CredentialEditorScreen`, `ImportScreen`, `SettingsScreen`.
2. **Android Platform Subsystem (`android/`)**:
   - `MultiPadAutofillService`: Autofill credential provider with `SaveInfo` and `onSaveRequest` for capturing new logins and password updates.
   - `AutofillCryptoStore`: Secure storage bridge for autofill cache and pending save queue.
   - `MultiPadQuickTileService` & Notification Shortcut: Quick autofill invocation hooks.
3. **Desktop Browser Extension (`extension/`)**:
   - Manifest V3 WebExtension for Chrome/Firefox/Edge.
   - Background service worker communicating with `127.0.0.1:48292` via paired token.
   - Content scripts detecting login forms, performing autofill, and capturing credential submissions.
4. **Documentation & Security (`README.md`, `SECURITY_COMPARISON.md`)**:
   - Polished public English documentation and concise Bitwarden security comparison.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Biometric Auto-Trigger on Startup | Automatically trigger biometric prompt on mobile & macOS upon app launch when biometric unlock is enabled | M1 | R1 |
| 2 | Circular Biometric Login Button | Render small circular biometric button at bottom-right of login screen for manual biometric invocation | M1 | R1 |
| 3 | macOS Background Lock Setting | Preference to toggle auto-lock on window minimize/background, defaulting to false on macOS | M1 | R2 |
| 4 | Android Navigation Auto-Lock Fix | Prevent unexpected auto-lock during settings navigation when timed auto-lock is disabled via lifecycle-aware suppression | M1 | R2 |
| 5 | Configurable 2FA Re-Prompt Intervals | Support 30, 60, and 90 day intervals for 2FA re-verification when opening the vault | M2 | R2 |
| 6 | Encrypted Vault Import Support | Detect encrypted export files (Bitwarden encrypted JSON), prompt for password, and decrypt credentials | M2 | R3 |
| 7 | Security Audit 2FA Recalibration | Calibrate vault audit so absence of 2FA on stored credentials is not penalized or flagged as a vulnerability | M2 | R3 |
| 8 | Desktop Browser Extension & Bridge | Manifest V3 extension and local authenticated bridge for form detection, autofill, and credential capture | M3 | R4 |
| 9 | Mobile Autofill Save & Update | Capture new credentials and modified passwords via `SaveInfo` and `onSaveRequest` in `MultiPadAutofillService` | M4 | R4 |
| 10 | Android Quick Autofill Shortcuts | Quick Settings tile and notification shortcut for immediate autofill access | M4 | R4 |
| 11 | Bitwarden-Style UX Ergonomics | 3-pane layout, dedicated read-only item detail pane, A-Z sorting, and top-level generator access | M4 | R4 |
| 12 | Background Footprint Optimization | Lightweight CPU/memory footprint; consolidate per-card TOTP timers into centralized ticker | M5 | R5 |
| 13 | Fast Startup Loading Acceleration | Parallel local item decryption and offline-first stale-while-revalidate startup flow | M5 | R5 |
| 14 | Comprehensive English README | Modern, polished English `README.md` for open-source release covering architecture, features, and setup | M5 | R5 |
| 15 | Bitwarden Security Comparison | Concise, objective security evaluation comparing MultiPad against Bitwarden | M5 | R5 |
| 16 | Final Integration & E2E Test Suite | 100% pass across E2E test suite (Tiers 1-4) and Tier 5 adversarial hardening | M6 | Acceptance |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Authentication, Biometrics & Window Lock | R1 (Auto-trigger biometrics, circular button) + R2 (macOS minimize lock preference, Android settings auto-lock fix) | none | PLANNED |
| M2 | Vault Import Decryption, 2FA Intervals & Audit | R2 (30/60/90 day 2FA intervals) + R3 (Bitwarden encrypted JSON import, audit 2FA penalty removal) | none | PLANNED |
| M3 | Desktop Browser Extension & Communication Bridge | R4 (Manifest V3 extension, authenticated local HTTP/WebSocket bridge, form detection, autofill & capture) | none | PLANNED |
| M4 | Mobile Autofill Capture, Shortcuts & UX Ergonomics | R4 (Android Autofill SaveInfo/onSaveRequest, notification shortcut, 3-pane layout, detail pane, A-Z sort, generator) | M1, M2 | PLANNED |
| M5 | Performance Optimization, Documentation & Security Comparison | R5 (Startup loading acceleration, TOTP timer consolidation, English README, Bitwarden comparison report) | M1, M2, M3, M4 | PLANNED |
| M6 | Final Verification & Adversarial Hardening | Phase 1: 100% E2E test suite pass (Tiers 1-4). Phase 2: Tier 5 adversarial coverage hardening. | M1, M2, M3, M4, M5, TEST_READY.md | PLANNED |

---

## Interface Contracts

### 1. `SettingsProvider` ↔ `AuthProvider` (Lock & 2FA)
- `bool get lockOnBackground`: Defaults to `false` on macOS/desktop platforms, `true` on mobile. Exposes `Future<void> setLockOnBackground(bool value)`.
- `int get twoFactorRepromptDays`: Returns configured interval (30, 60, or 90 days). Exposes `Future<void> setTwoFactorRepromptDays(int days)`.
- `bool isTwoFactorPromptDue()`: Returns `true` if `DateTime.now().difference(lastVerified) > Duration(days: repromptDays)`.
- `void suppressAutoLockUntilResumed()`: Suppresses auto-lock across asynchronous external intent launches until the app transitions through `resumed` lifecycle state with a 500ms debounce.

### 2. `ImportService` ↔ `CryptoService` (Encrypted Import)
- `bool isEncryptedExport(String rawContent)`: Returns `true` if JSON parses with `"encrypted": true` or `"passwordProtected": true`.
- `Future<ImportInspectionResult> inspectFile(String path, {String? decryptionPassword})`: If encrypted and password is null, returns status `needsPassword`. If password is provided, decrypts payload and returns parsed items.
- `Future<String> decryptBitwardenJson(String rawJson, String password)`:
  - Parses salt, kdfType (PBKDF2/Argon2id), kdfIterations.
  - Derives 32-byte master key, expands with HKDF-Expand into 32-byte encKey and 32-byte macKey.
  - Verifies HMAC-SHA256 MAC and decrypts AES-256-CBC ciphertext. Returns cleartext JSON string containing `folders` and `items`.

### 3. `BrowserBridgeService` ↔ Desktop Extension
- Endpoint: `http://127.0.0.1:48292/api/v1/...`
- Headers: `Authorization: Bearer <pairing_token>`, `Origin: chrome-extension://<id>`
- Routes:
  - `GET /status`: `{ "status": "unlocked" | "locked", "version": "1.0.0" }`
  - `POST /query`: Input `{ "url": "https://example.com" }` → Returns list of matched credentials `{ "id", "title", "username", "password", "totp" }`.
  - `POST /capture`: Input `{ "url", "username", "password" }` → Enqueues or saves new/updated credential into vault.
  - `POST /pair`: Hands off authorization pairing token upon user confirmation in desktop UI.

### 4. `MultiPadAutofillService` (Android) ↔ Vault Store
- `SaveInfo`: `SaveInfo.SAVE_DATA_TYPE_PASSWORD | SaveInfo.SAVE_DATA_TYPE_USERNAME` attached to `FillResponse.Builder`.
- `onSaveRequest(request: SaveRequest, callback: SaveCallback)`:
  - Traverses `request.fillContexts.last().structure`.
  - Extracts filled username, password, and package/web domain.
  - Saves pending captured item into `AutofillCryptoStore.savePendingCredential(...)`.
  - Notifies user via toast/notification; pending credentials import on next MultiPad vault unlock.

---

## Code Layout
```
lib/
├── constants.dart                     # Storage keys, defaults, endpoints
├── main.dart                          # App entry point, lifecycle observer, service initializations
├── models/
│   ├── vault_item.dart                # Credential data model
│   └── audit_issue.dart               # Security audit issues
├── providers/
│   ├── auth_provider.dart             # Master key, biometrics, 2FA intervals, lock suppression
│   ├── settings_provider.dart         # Preferences, lockOnBackground, 2FA intervals
│   └── vault_provider.dart            # Vault state, caching, A-Z sort, fast parallel decryption
├── services/
│   ├── audit_service.dart             # Calibrated audit calculations (no 2FA penalty)
│   ├── biometric_service.dart         # Local_auth biometrics wrapper
│   ├── browser_bridge_service.dart    # Authenticated loopback HTTP bridge for browser extension
│   ├── crypto_service.dart            # Argon2id, PBKDF2, AES-GCM, Bitwarden KDF + AES-CBC
│   ├── import_service.dart            # Import inspection, Bitwarden encrypted JSON decryption
│   └── totp_ticker_service.dart       # Consolidated 1-second TOTP ticker for low CPU footprint
├── screens/
│   ├── auth_screen.dart               # Startup biometric trigger, bottom-right circular button
│   ├── home_screen.dart               # 3-pane master-detail layout, A-Z sort, generator access
│   ├── import_screen.dart             # Encrypted file detection & password prompt dialog
│   └── settings_screen.dart           # macOS background lock toggle, 2FA interval choices (30/60/90)
└── widgets/
    ├── credential_detail_pane.dart    # Dedicated read-only detail view with quick copy
    ├── password_generator_dialog.dart # Top-level generator access
    └── vault_item_card.dart           # Lightweight card hooked to centralized TOTP ticker
android/
└── app/src/main/kotlin/com/multipad/multipad/
    ├── MultiPadAutofillService.kt     # SaveInfo and onSaveRequest implementation
    ├── AutofillCryptoStore.kt         # Secure store for autofill data & pending capture queue
    └── MultiPadQuickTileService.kt    # Android Quick Settings tile
extension/
├── manifest.json                      # Manifest V3 configuration
├── background.js                      # Service worker communicating with local bridge
├── content.js                         # Web login form detection, autofill injection, submit listener
├── popup.html / popup.js              # Extension status, manual search, pairing UI
└── icons/                             # Extension icons
test/
├── audit_and_totp_test.dart           # Calibrated audit tests (no 2FA penalty)
├── import_service_test.dart           # Bitwarden plain & encrypted JSON import tests
├── crypto_service_test.dart           # Bitwarden KDF & AES-256-CBC decryption tests
├── biometric_and_lock_test.dart       # Startup trigger, circular button & lock suppression tests
└── browser_bridge_test.dart           # Extension loopback bridge authentication & query tests
test_e2e/                              # Independent E2E test suite (Tiers 1-4)
README.md                              # Modern public English documentation
SECURITY_COMPARISON.md                 # Concise Bitwarden security comparison report
```
