# Project: MultiPad UI/UX Modernization & Autofill Excellence (v1.4.0)

## Architecture
MultiPad is an open-source, zero-knowledge, cross-platform password manager and digital vault for Android, macOS, Windows, Linux, and Web Browsers (Chrome/Firefox/Edge Extension).
The architecture comprises:
1. **Core Flutter App (`lib/`)**:
   - `Theme & UI`: Refined Material 3 color system (slate/indigo tiers), custom component themes, responsive layouts (mobile `NavigationBar` vs desktop 3-pane master-detail), polished cards with micro-interactions, command palette quick launcher.
   - `Native Bridge & Pending Capture`: Platform channel (`NativeBridgeService`) coordinating between native Android Autofill and the Flutter SQLite vault.
   - `Browser Bridge (`BrowserBridgeService`)`: Local authenticated loopback HTTP server (`127.0.0.1:48292`) connecting browser extensions to the unlocked vault.
   - `Settings`: Inset grouped cards including dedicated Browser Extension & Bridge pairing interface (PIN display, copy, regeneration, token revocation).
2. **Manifest V3 Web Extension (`extension/`)**:
   - Background service worker communicating with local bridge via paired session token.
   - Content script (`content.js`): In-field shield badges, floating fixed-position dropdowns, multi-step form detection, reactive framework (React/Vue/Angular) property descriptor injection, automated TOTP copying, interactive save banners.
   - Modern popup (`popup.html`, `popup.css`, `popup.js`): 380x520px responsive container, SVG icons, inline password generator tab, Copy Username, Reveal Password, live TOTP countdown ticker.
3. **Android Platform Subsystem (`android/`)**:
   - `MultiPadAutofillService`: Android 11+ Inline Suggestions (`InlineSuggestionsRequest`, `InlinePresentation`) and custom branded `RemoteViews` dropdowns.
   - Multi-step context aggregation across `request.fillContexts`, split-field multi-box OTP distribution, browser URL bar fallback domain extraction, and package alias matching.
   - `SaveInfo` generation and `onSaveRequest` capture pipeline feeding `AutofillCryptoStore`.

---

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Modern Material 3 Theme System | Refined surface tiers (`surfaceContainerLow/High`), subtle outlines (`outlineVariant`), customized component themes, and monospace typography | M1 | Survey UI/UX |
| 2 | Responsive Mobile Navigation | Replace drawer-only navigation on < 780px screens with modern `NavigationBar` and streamlined top AppBar | M1 | Survey UI/UX |
| 3 | Polished Vault Item Cards | Subtle borders, hover elevation, compact action rows, unified tag pills, and in-place localized copy micro-interaction | M1 | Survey UI/UX |
| 4 | Desktop Command Palette Keyboard Nav | Full Arrow Up/Down, Enter, Tab, and Escape navigation in `QuickSearchDialog` with visual shortcut badges | M1 | Survey UI/UX |
| 5 | Password Generator Dialog Polish | Responsive dialog/sheet, full localization (`context.l10n`), interactive multi-segment entropy gradient meter | M1 | Survey UI/UX |
| 6 | Desktop Bridge Settings Card | Dedicated section in `SettingsScreen` showing loopback port 48292, active 6-digit PIN with 1-click copy, and PIN rotation | M1 | Survey UI/UX & Web |
| 7 | Reactive Framework Autofill Injection | Use prototype property descriptors and synthetic input/change/blur events in `content.js` for React, Vue, and Angular forms | M2 | Survey Web |
| 8 | Multi-Step Login & Standalone Form Detection | Decouple username search from password existence; detect Step 1 identity fields and 2FA/OTP inputs in `content.js` | M2 | Survey Web |
| 9 | In-Field Badge & Floating Fixed Dropdown | MultiPad shield badge inside input fields (closed Shadow DOM) and viewport-relative fixed dropdown with scroll/resize tracking & keyboard navigation | M2 | Survey Web |
| 10 | Automated TOTP Auto-Copy & Clipboard | Automatically copy live TOTP token to clipboard upon credential autofill with toast notification (`clipboardWrite` permission) | M2 | Survey Web |
| 11 | Extension Popup Modernization & Generator | 380x520px container, SVG icons, inline password generator tab, Copy Username, Reveal Password, and live TOTP ticker | M2 | Survey Web & UI/UX |
| 12 | eTLD+1 Root Domain Matching | Normalize domain matching in `BrowserBridgeService` so subdomains match root credentials | M2 | Survey Web |
| 13 | Connect Pending Capture Pipeline | Wire `NativeBridgeService.getPendingAutofillCredentials()` on Flutter resume/unlock, show bottom sheet / dialog to update or save into vault | M3 | Survey Android |
| 14 | Android 11+ Inline Suggestions | Implement `InlineSuggestionsRequest` and `InlinePresentation` for keyboard suggestion chips (Gboard, SwiftKey) | M3 | Survey Android |
| 15 | Branded Custom RemoteViews Layout | Custom `autofill_dataset_item.xml` layout with MultiPad branding and theme-adaptive colors | M3 | Survey Android |
| 16 | Multi-Step Context Aggregation | Iterate backwards across `request.fillContexts` so Step 1 username is preserved when Step 2 password is submitted | M3 | Survey Android |
| 17 | Split-Field Multi-Box OTP Distribution | Distribute 6-digit TOTP character-by-character into individual single-character boxes | M3 | Survey Android |
| 18 | Browser URL Bar Fallback Domain Extraction | Extract domain from URL bar/omnibox text when `node.webDomain` is null (Firefox, WebViews) | M3 | Survey Android |
| 19 | SaveInfo Configuration & SPA Flags | Prevent false save prompts on username-only forms; add `FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE` for SPA forms | M3 | Survey Android |
| 20 | Package Alias Mapping Dictionary | Map known app package names (Uber, Twitter/X, etc.) to domains | M3 | Survey Android |
| 21 | Version Bump to v1.4.0 & Docs | Synchronize version `1.4.0` across pubspec, constants, bridge, manifest, popup, and README | M4 | Goals |
| 22 | Full Test & Analyzer Verification | 100% pass across `flutter test`, `flutter test test_e2e/`, and 0 `flutter analyze` issues | M4 | Goals |
| 23 | GitHub Actions Release Deployment | Git commit, tag `v1.4.0`, and trigger CI/CD release workflow | M4 | Goals |
| 24 | Desktop Frameless / Modern Window Styling | Frameless window chrome on desktop (macOS: `NSWindow.titleBarStyle = .hidden`, `fullSizeContentView`, traffic lights inset; Windows: custom draggable chrome) | M5 | User Request |
| 25 | Windows Installer (`MultiPad-Windows-Setup.exe`) | Inno Setup script (`windows/installer/multipad_setup.iss`), Start Menu/Desktop shortcuts, Programs registry, and GitHub Actions `iscc` release build | M5 | User Request |
| 26 | Seamless In-Place In-App Updates | In-place updates across platforms without manual re-installation (Android FileProvider intent, macOS helper script replacement, Windows setup update) | M5 | User Request |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Flutter UI/UX Modernization & Desktop Bridge UI | Features 1–6 (Theme, mobile navigation, cards, command palette, generator polish, Settings bridge pairing card) | none | DONE |
| M2 | Web Browser Extension & Desktop Bridge Autofill | Features 7–12 (MV3 manifest, reactive autofill, multi-step detection, in-field badge, floating dropdown, TOTP copy, popup generator, eTLD+1) | M1 (Bridge UI) | DONE |
| M3 | Android Mobile Autofill Excellence & Capture | Features 13–20 (Capture pipeline connection, inline suggestions, custom RemoteViews, multi-step context, split OTP, URL bar fallback, SaveInfo flags) | M1 (Theme/UI) | DONE |
| M5 | Desktop Frameless, Windows Installer & In-Place Updates | Features 24–26 (Frameless window styling, Inno Setup Windows installer, and in-place update pipelines across Android/macOS/Windows) | none (independent desktop/infra track) | DONE |
| M4 | Verification, Version Bump (v1.4.0) & CI/CD Deployment | Features 21–23 (v1.4.0 bump across all files, full test suite pass, analyzer 0 issues, tag, and deployment) | M1, M2, M3, M5 | DONE |

---

## Interface Contracts

### 1. `BrowserBridgeService` ↔ `SettingsScreen` (Bridge Pairing UI)
- `BrowserBridgeService.instance.pairingCode`: Returns the active 6-digit PIN string (e.g. `"849201"`).
- `BrowserBridgeService.instance.isPortBound`: Returns boolean whether port 48292 is bound and listening.
- `BrowserBridgeService.instance.rotatePairingToken()`: Invalidates current token, generates new 6-digit PIN, and notifies listeners.

### 2. `NativeBridgeService` ↔ `VaultProvider` (Android Autofill Capture)
- `NativeBridgeService.getPendingAutofillCredentials()`: Returns `List<Map<String, dynamic>>` representing captured credentials `{ "url", "username", "password", "package" }`.
- `NativeBridgeService.clearPendingAutofillCredentials()`: Flushes the pending SharedPreferences queue.
- `VaultProvider.processPendingAutofillCapture(...)`: Checks for existing domain/username matches. If matched, updates password; if new, creates a `VaultItem` and persists to SQLite.

### 3. `content.js` ↔ `background.js` (Extension Autofill Protocol)
- `QUERY_CREDENTIALS`: `{ action: 'QUERY_CREDENTIALS', url: window.location.href }` → returns matching credentials with live TOTP.
- `AUTOFILL_CREDENTIAL`: Injects credentials using prototype property descriptors and synthetic events.
- `COPY_TO_CLIPBOARD`: Copies live TOTP to clipboard and displays in-page toast notification.
- `CAPTURE_CREDENTIAL`: `{ action: 'CAPTURE_CREDENTIAL', url, username, password }` → presents confirmation banner before submitting to bridge.

---

## Code Layout
```
lib/
├── constants.dart                     # App version (1.4.0), UI constants, endpoints
├── main.dart                          # Modernized theme, app lifecycle resume checks
├── models/
│   └── vault_item.dart                # Credential model
├── providers/
│   ├── auth_provider.dart             # Authentication & biometrics
│   ├── settings_provider.dart         # Preferences & autofill sync
│   └── vault_provider.dart            # Vault state & pending credential capture integration
├── services/
│   ├── browser_bridge_service.dart    # Loopback bridge (eTLD+1 matching, pairing PIN)
│   ├── native_bridge_service.dart     # Android Autofill platform channel bridge
│   └── totp_service.dart              # TOTP generation & countdown
├── screens/
│   ├── home_screen.dart               # Responsive navigation (mobile NavigationBar, desktop 3-pane)
│   ├── settings_screen.dart           # Grouped cards & Browser Extension pairing UI
│   └── authenticator_screen.dart      # TOTP authenticator with smooth animations
├── widgets/
│   ├── quick_search_dialog.dart       # Command palette with full keyboard navigation
│   ├── password_generator_dialog.dart # Modernized responsive generator with entropy bar
│   └── vault_item_card.dart           # Polished card with in-place copy micro-interactions
android/
└── app/src/main/
    ├── AndroidManifest.xml            # Service declarations
    ├── res/
    │   ├── layout/
    │   │   └── autofill_dataset_item.xml # Custom branded RemoteViews layout
    │   └── values/strings.xml         # Localized service labels
    └── kotlin/com/multipad/multipad/
        ├── MultiPadAutofillService.kt # Inline suggestions, multi-step context, split OTP, URL fallback
        ├── AutofillCryptoStore.kt     # Secure Keystore credential store
        └── MainActivity.kt            # Platform channel implementation
extension/
├── manifest.json                      # MV3 permissions (clipboardWrite, contextMenus), v1.4.0
├── background.js                      # Service worker & bridge gateway
├── content.js                         # In-field badge, floating fixed dropdown, reactive injection, TOTP
├── popup.html / popup.js / popup.css  # 380x520px popup, inline generator, live TOTP ticker
└── icons/                             # Extension icons
test/
├── browser_bridge_test.dart           # Bridge pairing & query tests
├── m4_autofill_and_ux_test.dart       # Capture pipeline & UI unit tests
test_e2e/                              # Independent E2E test suite
README.md                              # Public documentation
```
