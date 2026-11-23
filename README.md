# MultiPad 🔐
### Zero-Knowledge, Cross-Platform Password Manager & Encrypted Vault

[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg?style=flat-square)](https://github.com/Wyclaew/multipad/releases/tag/v1.4.0)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg?style=flat-square)](https://github.com/Wyclaew/multipad)
[![E2E Test Suite](https://img.shields.io/badge/e2e%20tests-140%2F140%20passing-success.svg?style=flat-square)](test_e2e/)
[![Security](https://img.shields.io/badge/cryptography-Argon2id%20%7C%20AES--256--GCM-blue.svg?style=flat-square)](#-cryptographic-architecture--security-model)
[![Zero-Knowledge](https://img.shields.io/badge/privacy-zero--knowledge-blueviolet.svg?style=flat-square)](#-security-principles)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20WebExtension-orange.svg?style=flat-square)](#-quick-start--installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)

**MultiPad** is a modern, privacy-first, zero-knowledge password manager and digital vault engineered for **Android**, **macOS**, **Windows**, **Linux**, and **Desktop Web Browsers (Chrome, Firefox, Edge)**. Built with Flutter, Kotlin, and Swift, MultiPad combines enterprise-grade cryptographic primitives with a seamless, Bitwarden-familiar user experience.

Your master password and unencrypted credentials **never leave your device**. All encryption and decryption operations occur strictly client-side using memory-hard **Argon2id** key derivation and authenticated **AES-256-GCM** encryption.

---

## 📑 Table of Contents

- [v1.4.0 Release Highlights](#-v140-release-highlights)
- [Key Highlights](#-key-highlights)
- [System Architecture](#-system-architecture)
- [Cryptographic Architecture & Security Model](#-cryptographic-architecture--security-model)
- [Core Feature Showcase](#-core-feature-showcase)
  - [Biometric Authentication & Startup Login](#1-biometric-authentication--startup-login)
  - [Intelligent Auto-Lock & 2FA Intervals](#2-intelligent-auto-lock--configurable-2fa-re-prompt-intervals)
  - [Universal Vault Import & Calibrated Security Audit](#3-universal-vault-import--calibrated-security-audit)
  - [Desktop Browser Extension & Authenticated Loopback Bridge](#4-desktop-browser-extension--authenticated-loopback-bridge)
  - [Native Android Autofill & Quick Settings Shortcut](#5-native-android-autofill--quick-settings-shortcut)
  - [Bitwarden-Familiar UX & Ergonomics](#6-bitwarden-familiar-ux--ergonomics)
  - [Performance & Background Footprint Optimization](#7-performance--background-footprint-optimization)
- [Quick Start & Installation](#-quick-start--installation)
  - [Prerequisites](#prerequisites)
  - [Running Desktop & Mobile](#running-desktop--mobile)
  - [Production Builds](#production-builds)
  - [Android Autofill Setup Guide](#android-autofill-setup-guide)
  - [Desktop Browser Extension Installation](#desktop-browser-extension-installation)
- [Comprehensive Testing](#-comprehensive-testing)
- [Project Directory Structure](#-project-directory-structure)
- [MultiPad vs. Bitwarden Security Summary](#-multipad-vs-bitwarden-security-summary)
- [Contributing & License](#-contributing--license)

---

## 🚀 v1.4.0 Release Highlights

MultiPad **v1.4.0** represents a comprehensive modernization of the user interface across all platforms, enterprise-grade autofill enhancements on Android and Desktop Web Extensions, desktop frameless window styling, a dedicated Windows Inno Setup installer, and seamless in-place updates:

1. **Material 3 UI Modernization**:
   - Modernized responsive user experience across Android, macOS, and Windows.
   - Refined slate/indigo color tokens with surface elevation tiers (`surfaceContainerLow/High`), subtle outlines (`outlineVariant`), and monospace secret typography.
   - Responsive mobile navigation featuring a bottom `NavigationBar` on screens $< 780\text{px}$ and 3-pane master-detail layout on desktop.
   - Polished vault item cards with hover elevation, category pills, and in-place localized copy micro-interactions.
   - Responsive password generator with interactive 4-segment entropy gauge and EFF Diceware passphrase support.
   - Fast desktop command palette (`QuickSearchDialog`) with full keyboard navigation (Arrow Up/Down, Enter, Tab, Escape).

2. **Android 11+ Inline Suggestions & RemoteViews Autofill**:
   - Upgraded `MultiPadAutofillService` supporting Android 11+ `InlineSuggestionsRequest` with IME keyboard chip presentation (Gboard, SwiftKey).
   - Branded custom `RemoteViews` dropdown layouts (`autofill_dataset_item.xml`) with theme-adaptive colors.
   - Multi-step context aggregation across backwards fill contexts for seamless 2-step login flows.
   - Split-field multi-box OTP distribution distributing 6-digit TOTP character-by-character into single-character input boxes.
   - Browser URL bar fallback domain extraction for web browsers where `webDomain` is null.
   - Dynamic package alias dictionary mapping popular Android applications to their vault domains.

3. **Manifest V3 Web Browser Extension**:
   - In-field MultiPad shield badge with closed Shadow DOM style isolation.
   - Viewport-relative fixed floating dropdown with live scroll and resize coordinate tracking.
   - Prototype property descriptor injection with synthetic event dispatching for reactive single-page frameworks (React, Vue, Angular).
   - Automated live TOTP clipboard copy upon credential autofill with toast notifications (`clipboardWrite` permission).
   - Modernized 380x520px extension popup with SVG iconography, inline password generator tab, and live TOTP ticker countdown.

4. **Desktop Frameless Window Chrome**:
   - Modern borderless frameless window styling on macOS AppKit (`NSWindow.titleBarStyle = .hidden`, `fullSizeContentView`, inset traffic light controls).
   - Custom borderless chrome on Windows Win32 with custom draggable titlebar, minimize, maximize/restore, and close buttons (`lib/widgets/desktop_title_bar.dart`).

5. **Windows Installer (`MultiPad-Windows-Setup.exe`)**:
   - Production Inno Setup installer script (`windows/installer/multipad_setup.iss`).
   - Supports both per-user AppData installation (no admin privileges required) and administrative Program Files installation.
   - Automatically registers in Windows Add/Remove Programs, creates Start Menu and Desktop shortcuts, and supports silent flags (`/VERYSILENT /SUPPRESSMSGBOXES`).

6. **Seamless In-Place In-App Updates**:
   - Automated in-place updates without manual deletion:
     - **Android**: FileProvider APK install intent triggers in-place package updates preserving SQLite vault and Keystore credentials.
     - **macOS**: In-place helper script replaces `MultiPad.app` directly in `/Applications/` and relaunches seamlessly.
     - **Windows**: Setup installer executes in-place update directly over the existing installation.

---

## 🌟 Key Highlights

- **Zero-Knowledge by Design**: The master password is never transmitted across the network. All vault items are encrypted and decrypted locally off the main isolate.
- **Modern Cryptography**: Argon2id (RFC 9106) memory-hard key derivation and AES-256-GCM authenticated encryption with 128-bit MAC tags.
- **Universal Bitwarden Interoperability**: Seamlessly imports both plaintext and password-protected encrypted Bitwarden JSON exports (PBKDF2/Argon2 + HKDF-Expand + AES-256-CBC HMAC-SHA256).
- **Passkey (FIDO2 / WebAuthn) Management**: Securely stores and organizes WebAuthn/FIDO2 credentials linked to login accounts, with full import interoperability from Bitwarden (`fido2Credentials`).
- **Desktop Browser Extension**: Native-grade autofill and credential capture for Chrome, Edge, and Firefox via a hardened local loopback bridge (`127.0.0.1:48292`).
- **Native Android AutofillService**: System-level autofill with inline dataset matching, direct TOTP delivery, save/update prompts (`SaveInfo`), and a Quick Settings tile.
- **Bitwarden-Style 3-Pane UI**: Ergonomic desktop navigation with collapsible folder sidebar, fast credential search list, and dedicated read-only item detail inspector.
- **Cryptographic Diceware Generator**: Full 7,776-word EFF wordlist ($12.92\text{ bits/word}$) with 50-entry secure history buffer.
- **Lightweight Footprint**: Centralized lifecycle-aware TOTP ticker (0% CPU wakeups in background) and offline-first Stale-While-Revalidate startup (<50ms local render).

---

## 🏗️ System Architecture

MultiPad bridges cross-platform Flutter UI with native OS subsystems and browser extensions:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             MultiPad Architecture                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
     ┌─────────────────────────────────┼─────────────────────────────────┐
     │                                 │                                 │
     ▼                                 ▼                                 ▼
┌───────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
│     Desktop / Mobile UI   │ │   Local Loopback Bridge   │ │  Native OS Subsystems       │
│    (Flutter & Dart 3.13)  │ │   (127.0.0.1:48292 HTTP)  │ │  (Android & macOS Runners)  │
├───────────────────────────┤ ├───────────────────────────┤ ├───────────────────────────┤
│ • 3-Pane Responsive Layout│ │ • Strict Loopback Binding │ │ • Android AutofillService │
│ • Startup Biometric Auto  │ │ • Origin Verification     │ │ • Quick Settings Tile     │
│ • Bottom-Right Quick FAB  │ │ • Constant-Time Auth      │ │ • FLAG_SECURE Blanking    │
│ • Diceware Passphrase Gen │ │ • Routes: /status, /query,│ │ • macOS Window Shield     │
│ • Offline-First SQLite    │ │   /capture, /pair         │ │ • Enclave Keychain Store  │
└───────────────────────────┘ └─────────────┬─────────────┘ └───────────────────────────┘
                                            │
                                            ▼
                              ┌───────────────────────────┐
                              │  Desktop Browser Extension│
                              │     (Manifest V3 WebExt)  │
                              ├───────────────────────────┤
                              │ • Chrome, Firefox, Edge   │
                              │ • Background ServiceWorker│
                              │ • Content Script Autofill │
                              │ • Form Submit Capture     │
                              └───────────────────────────┘
```

---

## 🛡️ Cryptographic Architecture & Security Model

MultiPad is built on zero-knowledge cryptographic foundations:

| Primitive | Parameter / Standard | Purpose |
|---|---|---|
| **Primary KDF** | **Argon2id** (RFC 9106), $m=19456\text{ KiB}$ (19 MiB), $t=2$, $p=1$ (configurable to 64 MiB, $t=3$, $p=4$) | Memory-hard master key derivation resilient against GPU/ASIC brute-force attacks |
| **Fallback / Interop KDF** | **PBKDF2-HMAC-SHA256** (100,000 iterations) | Interoperability with standard imports and low-resource devices |
| **Vault Encryption** | **AES-256-GCM** (AEAD, 256-bit key, 12-byte random IV/nonce, 128-bit MAC) | Authenticated encryption guaranteeing both confidentiality and ciphertext integrity |
| **Bitwarden Interop** | **PBKDF2 / Argon2id** + **RFC 5869 HKDF-Expand** + **AES-256-CBC with HMAC-SHA256** (`2.<iv>\|<cipher>\|<mac>`) | Direct decryption and generation of password-protected Bitwarden vault exports |
| **Side-Channel Defense** | Constant-time comparison (`constantTimeEquals`, `constantTimeStringEquals`) | Eliminates timing side-channel leakage during MAC and token evaluations |
| **Memory Hygiene** | Explicit zero-wiping (`CryptoService.wipe`) of byte buffers upon vault lock | Prevents plaintexts from lingering in memory heap or swapped RAM |
| **Hardware Key Sealing** | Android Keystore & Apple Keychain (`flutter_secure_storage`) | Biometric unlock keys protected within hardware Secure Enclave / TEE |
| **Screen Privacy** | `FLAG_SECURE` (Android) and `NSWindow.sharingType = .none` (macOS) | Prevents screen recording, screenshots, and switcher snapshot capture |

---

## 🚀 Core Feature Showcase

### 1. Biometric Authentication & Startup Login
- **Automatic Biometric Prompt**: When biometric unlock is enabled on mobile or macOS, the biometric prompt triggers automatically on application startup without requiring manual interaction.
- **Circular Biometric Button**: A dedicated, floating biometric button positioned at the bottom-right of the login screen allows users to re-trigger biometric authentication at any time if the initial prompt was dismissed or canceled.
- **PIN Unlock & Duress Vault**: Supports quick 4–6 digit PIN authentication wrapped with PBKDF2, plus a secondary Duress/Panic password that unlocks a decoy vault under coercion.

### 2. Intelligent Auto-Lock & Configurable 2FA Re-Prompt Intervals
- **macOS Background Lock Control**: A dedicated setting in macOS preferences controls whether the vault automatically locks when the application window is minimized or placed in the background (defaults to `false` on desktop, preventing disruptive re-locks).
- **Android Settings Auto-Lock Fix**: Suppresses unexpected auto-locking during settings navigation when timed auto-lock is disabled.
- **Configurable 2FA Re-Prompt Intervals**: Users can select two-factor authentication re-verification frequency presets of **30**, **60**, or **90 days**. Timestamps are sealed with tamper-proof HMAC signatures.

### 3. Universal Vault Import & Calibrated Security Audit
- **Encrypted Bitwarden JSON Import**: Automatically inspects and detects password-protected Bitwarden encrypted JSON files (`"encrypted": true`). The app prompts the user for their export password and decrypts folders and credentials client-side.
- **Multi-Format Ingestion**: Supports Bitwarden CSV/JSON, KeePass 2 XML, KeePass CSV, Chrome/Edge CSV, and generic delimited formats.
- **Calibrated Security Audit**: Analyzes vault hygiene (weak passwords, reused passwords across accounts, expired credentials, phishing lookalikes, and credit card Luhn checksum validation) **without penalizing the absence of 2FA**, reflecting realistic web ecosystem adoption.

### 4. Desktop Browser Extension & Authenticated Loopback Bridge
- **Manifest V3 WebExtension**: Compatible with Google Chrome, Microsoft Edge, Brave, and Mozilla Firefox.
- **Hardened Loopback Bridge**: MultiPad hosts an authenticated local bridge strictly bound to `127.0.0.1:48292`.
- **Zero-Knowledge Inter-Process Security**: Enforces extension origin validation (`chrome-extension://`, `moz-extension://`), constant-time Bearer token authorization, and returns HTTP 423 Locked when the vault is closed.
- **Inline Autofill & Submission Capture**: Automatically matches credentials by domain and prompts to capture new or modified passwords upon form submission.

### 5. Native Android Autofill & Quick Settings Shortcut
- **System Autofill Provider**: `MultiPadAutofillService` integrates with Android 8.0+ Autofill Framework, delivering instant login credentials and 2FA TOTP codes directly to native apps and browsers.
- **Automatic Credential Capture**: Uses Android `SaveInfo` and `onSaveRequest` to detect new registrations and updated passwords on mobile devices.
- **Quick Settings Tile**: Android Quick Settings tile (`MultiPadQuickTileService`) enables instant vault access and credential search from the notification shade.

### 6. Bitwarden-Familiar UX & Ergonomics
- **Responsive 3-Pane Layout**: On displays $\ge 1000\text{px}$, MultiPad renders a full 3-pane workstation view: Category/Folder Sidebar (256px), Credential List (340px), and a dedicated read-only `CredentialDetailPane`.
- **Read-Only Detail Pane**: View passwords, custom fields, and notes with one-click copy buttons and a radial TOTP countdown ring.
- **Diceware Password & Passphrase Generator**: Full 7,776-word EFF wordlist ($12.92\text{ bits/word}$) supporting configurable length, separator characters, capitalization, digit injection, and a 50-entry history ring buffer.
- **Polymorphic Item Support**: First-class handling for Logins, Secure Notes, Payment Cards (with Luhn validation), Bank Accounts (with IBAN validation), Servers (SSH), Databases, Crypto Wallets (BIP-39), Wi-Fi Credentials, Identities, and Software Licenses.

### 7. Performance & Background Footprint Optimization
- **Centralized TOTP Ticker**: A single broadcast stream timer replaces independent 1-second timers across all cards, automatically pausing when the window is minimized or unfocused (0% idle CPU wakeups).
- **2-Phase Stale-While-Revalidate (SWR)**: Unlocked vaults load local SQLite items in <50ms while background delta-sync reconciles changes asynchronously.
- **Parallel Chunk Decryption**: Offloads item decryption into worker isolates via `Isolate.run` for ultra-fast startup performance.

### 8. Passkey (FIDO2 / WebAuthn) Credential Vault
- **Email & Account-Linked Passkeys**: Store FIDO2/WebAuthn public keys, credential IDs, and Relying Party metadata (RP ID/Domain) directly alongside your accounts, just like Bitwarden.
- **Automated Passkey Ingestion**: Automatically extracts and imports passkeys from Bitwarden unencrypted and encrypted JSON exports (`fido2Credentials` and `passkeys`).
- **Interactive Management**: Add, inspect, and manage passkeys in the Credential Editor, complete with quick-copy chips and badges in the vault list and detail inspector.

---

## 💻 Quick Start & Installation

### Prerequisites

- **Flutter SDK**: `v3.47.0` or higher
- **Dart SDK**: `v3.13.0` or higher
- **Android**: Android SDK (API Level 26+ for Autofill, API Level 24+ for Quick Settings Tile)
- **macOS / iOS**: Xcode 15.0+ with CocoaPods

### Running Desktop & Mobile

Clone the repository and fetch dependencies:

```bash
git clone https://github.com/multipad/multipad.git
cd multipad
flutter pub get
```

Run on your target platform:

```bash
# Run on macOS Desktop
flutter run -d macos

# Run on Android (Physical Device or Emulator)
flutter run -d <device_id>

# Run on Windows Desktop
flutter run -d windows

# Run on Linux Desktop
flutter run -d linux
```

### Production Builds

Generate production release artifacts:

```bash
# Android Release APK & App Bundle
flutter build apk --release
flutter build appbundle --release

# macOS Application Bundle (.app / .dmg)
flutter build macos --release

# Windows Executable & Inno Setup Installer
flutter build windows --release
iscc /DAppVersion=1.4.0 windows/installer/multipad_setup.iss

# Linux Binary
flutter build linux --release
```

### Android Autofill Setup Guide

To enable system-wide autofill on Android 8.0+:

1. Open your device **Settings** $\rightarrow$ **System** (or **General Management**) $\rightarrow$ **Languages & input**.
2. Tap **Autofill service**.
3. Select **MultiPad** and confirm the system dialog.
4. *(Optional)* Add the Quick Settings Tile: Swipe down the notification shade twice, tap the **Edit** (pencil) icon, and drag the **MultiPad** tile into your active quick settings.

### Desktop Browser Extension Installation

To install the browser extension on Chrome, Brave, or Microsoft Edge:

1. Open your browser and navigate to `chrome://extensions` (or `edge://extensions`).
2. Toggle on **Developer mode** in the top-right corner.
3. Click **Load unpacked** and select the `/extension` directory inside the MultiPad repository.
4. Ensure MultiPad desktop app is running and unlocked.
5. Click the MultiPad extension icon in your browser toolbar to confirm bridge connectivity (`127.0.0.1:48292`).

---

## 🧪 Comprehensive Testing

MultiPad includes an exhaustive, tiered test suite guaranteeing cryptographic correctness, UI ergonomics, and boundary resilience:

```bash
# Run standard unit and widget test suite
flutter test

# Run the complete End-to-End (E2E) Test Suite (140/140 Tests Passing)
flutter test test_e2e/

# Run specific E2E test tiers
flutter test test_e2e/tier1_feature_coverage_test.dart
flutter test test_e2e/tier2_boundaries_test.dart
flutter test test_e2e/tier3_cross_feature_test.dart
flutter test test_e2e/tier4_real_world_scenarios_test.dart
```

---

## 📁 Project Directory Structure

```
MultiPad/
├── lib/
│   ├── main.dart                          # Application entry point & lifecycle observer
│   ├── constants.dart                     # Design tokens (AppThemeConstants) & app version (1.4.0)
│   ├── models/
│   │   ├── vault_item.dart                # Polymorphic vault items & custom fields model
│   │   ├── vault_folder.dart              # Folder hierarchy model
│   │   └── sync_conflict.dart             # Sync reconciliation model
│   ├── providers/
│   │   ├── auth_provider.dart             # Master key lifecycle, biometrics & auto-lock
│   │   ├── settings_provider.dart         # Preferences (lockOnBackground, 2FA intervals)
│   │   └── vault_provider.dart            # Fast SWR loading, parallel decryption, pending capture
│   ├── services/
│   │   ├── crypto_service.dart            # Argon2id, AES-256-GCM, PBKDF2 & Bitwarden cipher
│   │   ├── totp_ticker_service.dart       # Centralized lifecycle-aware broadcast TOTP ticker
│   │   ├── browser_bridge_service.dart    # Authenticated 127.0.0.1:48292 loopback HTTP bridge
│   │   ├── biometric_service.dart         # Local authentication & hardware key sealing
│   │   ├── import_service.dart            # Encrypted Bitwarden JSON, CSV & XML parser
│   │   ├── audit_service.dart             # Calibrated vault audit (no 2FA deduction)
│   │   ├── totp_service.dart              # RFC 6238 TOTP generator (SHA1/SHA256/SHA512)
│   │   ├── clipboard_service.dart         # Secure auto-clearing clipboard
│   │   ├── update_service.dart            # In-place updates (APK, macOS helper, Windows setup)
│   │   ├── pending_capture_coordinator.dart # Autofill credential capture lifecycle coordinator
│   │   └── native_bridge_service.dart     # Platform channels for FLAG_SECURE & autofill
│   ├── screens/
│   │   ├── auth_screen.dart               # Startup biometric trigger & bottom-right circular FAB
│   │   ├── home_screen.dart               # Modern Material 3 responsive layout & NavigationBar
│   │   ├── import_screen.dart             # Encrypted file inspection & password prompt
│   │   ├── settings_screen.dart           # Extension bridge pairing card & preferences
│   │   └── credential_editor_screen.dart  # Multi-field credential editor
│   └── widgets/
│       ├── credential_detail_pane.dart    # Dedicated read-only inspector with radial TOTP
│       ├── password_generator_dialog.dart # Modern responsive generator with 4-segment entropy gauge
│       ├── quick_search_dialog.dart       # Command palette with full keyboard navigation
│       ├── desktop_title_bar.dart         # Custom frameless window titlebar for desktop
│       ├── update_dialog.dart             # In-place update prompt with SHA-256 verification
│       ├── pending_capture_dialog.dart    # In-app credential save & update prompt
│       └── vault_item_card.dart           # Polished card with in-place copy micro-interactions
├── android/
│   └── app/src/main/
│       ├── res/layout/
│       │   └── autofill_dataset_item.xml  # Branded custom RemoteViews layout
│       └── kotlin/com/multipad/multipad/
│           ├── MainActivity.kt            # Cold-boot FLAG_SECURE window protection
│           ├── MultiPadAutofillService.kt # Android 11+ inline suggestions, split OTP, multi-step
│           ├── AutofillCryptoStore.kt     # Secure Keystore store for cached autofill entries
│           └── MultiPadQuickTileService.kt # Android Quick Settings tile service
├── extension/
│   ├── manifest.json                      # Manifest V3 browser extension configuration (v1.4.0)
│   ├── background.js                      # Service worker communicating with 127.0.0.1:48292
│   ├── content.js                         # In-field badge, floating dropdown, reactive injection
│   └── popup.html / popup.js / popup.css  # 380x520px popup UI & inline password generator
├── windows/
│   └── installer/
│       └── multipad_setup.iss             # Inno Setup Windows installer script (MultiPad-Windows-Setup.exe)
├── test/                                  # Comprehensive unit, widget, and platform tests
├── test_e2e/                              # 140/140 E2E tests across Tiers 1-4
├── README.md                              # This documentation file
└── SECURITY_COMPARISON.md                 # Concise Bitwarden security comparison report
```

---

## 🔒 MultiPad vs. Bitwarden Security Summary

| Feature / Metric | MultiPad | Bitwarden |
|---|---|---|
| **Default Master KDF** | **Argon2id** ($m=19.45\text{ MB}$, $t=2$, $p=1$) default | PBKDF2 (600,000 iters) default (Argon2id optional) |
| **Symmetric Vault Encryption** | **AES-256-GCM** (AEAD, built-in integrity tag) | AES-256-CBC with HMAC-SHA256 (EtM) |
| **Database Architecture** | **Offline-First Local SQLite** with optional cloud sync | Cloud-First Server Database synchronization |
| **Browser Extension Bridge** | Local Loopback HTTP (`127.0.0.1:48292`) with origin & bearer auth | Native Messaging Host binary bridge |
| **RAM Hygiene** | Explicit zero-wiping (`wipe()`) on vault lock | Standard garbage collector deallocation |
| **Screen Capture Defenses** | Native `FLAG_SECURE` (Android) + window blanking (macOS) | Native screen protections vary by platform |

> 📖 **Read the full comparative analysis in [`SECURITY_COMPARISON.md`](SECURITY_COMPARISON.md).**

---

## 📄 Contributing & License

Contributions are welcome! Please check our test suite before submitting pull requests:

```bash
flutter test
flutter test test_e2e/
```

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
