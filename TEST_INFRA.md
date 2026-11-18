# MultiPad End-to-End (E2E) Test Infrastructure Specification

## 1. Overview & Architectural Philosophy

MultiPad's End-to-End (E2E) test harness validates the product strictly from an **opaque-box, user-facing perspective**. Tests are derived directly from the canonical user requirements in `ORIGINAL_REQUEST.md` and feature contracts in `PROJECT.md`, without coupling to internal private implementation details.

The test infrastructure is designed for:
1. **Total Isolation & Hermeticity**: Every test manages its own state, memory-backed preferences, secure hardware storage mock buffers, and temporary SQLite databases. Tests run deterministically in any order without side-effect leakage.
2. **Deterministic Platform Simulation**: Hardware enclaves (Touch ID / Face ID / Android BiometricPrompt), system clipboard managers, native Android Autofill daemons, and desktop browser extension loopbacks are exercised through faithful mock harnesses and loopback sockets.
3. **Progressive Testability**: Tests verify observable contracts, user workflows, state machine transitions, and cryptographic invariants across all supported desktop (macOS, Windows) and mobile (Android) platforms.

---

## 2. 4-Tier Test Architecture

```
                                  +---------------------------------------+
                                  |   Tier 4: Real-World Scenarios        |
                                  |   (Multi-step end-to-end workflows)   |
                                  +-------------------+-------------------+
                                                      |
                                  +-------------------v-------------------+
                                  |   Tier 3: Cross-Feature Interactions  |
                                  |   (Pairwise combinations & state)     |
                                  +-------------------+-------------------+
                                                      |
                                  +-------------------v-------------------+
                                  |   Tier 2: Boundary & Corner Cases     |
                                  |   (Extreme values, errors, timeouts)  |
                                  +-------------------+-------------------+
                                                      |
                                  +-------------------v-------------------+
                                  |   Tier 1: Feature Coverage            |
                                  |   (>=5 tests per feature, feats 1-15) |
                                  +---------------------------------------+
```

### Tier 1: Feature Coverage (`tier1_feature_coverage_test.dart`)
- **Requirement**: At least 5 independent, behavior-based test cases for every feature in the `PROJECT.md` Feature Inventory (Features 1 through 15).
- **Scope**: Primary happy paths, essential error feedback, contract verification, and UI state synchronization for all 15 features.
- **Coverage**: 15 features * >=5 test cases = **75+ test cases**.

### Tier 2: Boundary & Corner Cases (`tier2_boundaries_test.dart`)
- **Requirement**: At least 5 boundary/corner test cases for each domain with edge conditions.
- **Scope**: Empty/whitespace inputs, extreme lengths (10,000+ chars), corrupted payloads, tampered cipherstrings, 0/negative durations, boundary Luhn checks, clock skews, and rapid window state switching.
- **Coverage**: 8 boundary groups * >=5 test cases = **40+ test cases**.

### Tier 3: Cross-Feature Interactions (`tier3_cross_feature_test.dart`)
- **Requirement**: Pairwise interactions between multiple distinct features verifying cohesive system behavior.
- **Scope**: Biometric auto-trigger with 2FA intervals, encrypted imports evaluated by calibrated security audit, browser extension bridge under vault lock/unlock, Android settings navigation with disabled timed lock, centralized TOTP ticker feeding read-only detail panes, etc.
- **Coverage**: **20 pairwise interaction test cases**.

### Tier 4: Real-World Application Scenarios (`tier4_real_world_scenarios_test.dart`)
- **Requirement**: End-to-end, multi-stage realistic user journeys.
- **Scope**:
  - Scenario 1: New user onboarding, password generation, credential storage, clipboard auto-clear, and hygiene audit.
  - Scenario 2: Bitwarden vault migration, encrypted JSON import with master password, A-Z browsing, and audit scoring.
  - Scenario 3: Daily desktop workflow: startup biometric auto-trigger, browser extension pairing, domain matching, and capture.
  - Scenario 4: Mobile autofill workflow: Quick PIN unlock, Quick Settings shortcut, Android Autofill index sync, and clean lock wipe.
  - Scenario 5: Enterprise security hardening: 60-day 2FA interval, Argon2id key derivation, offline cold-start cache recovery.
- **Coverage**: **5 comprehensive workflow test scenarios**.

---

## 3. Directory Layout

```
test_e2e/
├── test_helpers.dart                    # Reusable harnesses, mock platform channels, crypto test vectors
├── tier1_feature_coverage_test.dart    # Tier 1: 15 features x >=5 tests (75+ tests)
├── tier2_boundaries_test.dart          # Tier 2: Boundary, corner, and malformed inputs (40+ tests)
├── tier3_cross_feature_test.dart       # Tier 3: Cross-feature pairwise interactions (20 tests)
└── tier4_real_world_scenarios_test.dart # Tier 4: Comprehensive real-world workflows (5 scenarios)
```

---

## 4. Test Runner & Execution Commands

All tests execute cleanly via the official Flutter test runner installed on the environment (`/opt/homebrew/share/flutter/bin/flutter`):

### Execute Entire E2E Test Suite
```bash
/opt/homebrew/share/flutter/bin/flutter test test_e2e/
```

### Execute Individual Tiers
```bash
# Tier 1: Feature Coverage (75+ tests)
/opt/homebrew/share/flutter/bin/flutter test test_e2e/tier1_feature_coverage_test.dart

# Tier 2: Boundary & Corner Cases (40+ tests)
/opt/homebrew/share/flutter/bin/flutter test test_e2e/tier2_boundaries_test.dart

# Tier 3: Cross-Feature Interactions (20 tests)
/opt/homebrew/share/flutter/bin/flutter test test_e2e/tier3_cross_feature_test.dart

# Tier 4: Real-World Application Scenarios (5 scenarios)
/opt/homebrew/share/flutter/bin/flutter test test_e2e/tier4_real_world_scenarios_test.dart
```

---

## 5. Feature Inventory Mapping Matrix

| # | Feature Name | Tier 1 Group | Tier 2 Boundary Group | Tier 3 Pairwise Partner | Tier 4 Scenario |
|---|--------------|--------------|-----------------------|-------------------------|-----------------|
| 1 | Biometric Auto-Trigger on Startup | Group 1 (5 tests) | B1: Biometric boundaries | T3.1, T3.2 (2FA interval) | Scenario 3 |
| 2 | Circular Biometric Login Button | Group 2 (5 tests) | B1: Rapid taps & lockouts | T3.18 (Confidential copy) | Scenario 3 |
| 3 | macOS Background Lock Setting | Group 3 (5 tests) | B2: Minimize race conditions | T3.8 (Manual lock override) | Scenario 3 |
| 4 | Android Navigation Auto-Lock Fix | Group 4 (5 tests) | B2: Suppression depths | T3.7 (Timed lock disabled) | Scenario 4 |
| 5 | Configurable 2FA Re-Prompt Intervals | Group 5 (5 tests) | B3: Boundary days & clock | T3.1, T3.2 (Biometric trigger) | Scenario 5 |
| 6 | Encrypted Vault Import Support | Group 6 (5 tests) | B4: Corrupted cipherstrings | T3.3 (Audit evaluation) | Scenario 2 |
| 7 | Security Audit 2FA Recalibration | Group 7 (5 tests) | B5: Card Luhn & empty vault | T3.3, T3.20 (Imported items) | Scenario 1, 2 |
| 8 | Desktop Browser Extension & Bridge | Group 8 (5 tests) | B6: Origin spoofing & bad req | T3.4, T3.5, T3.6 (Vault lock) | Scenario 3 |
| 9 | Mobile Autofill Save & Update | Group 9 (5 tests) | B6: Malformed form structures | T3.13, T3.14 (Autofill index) | Scenario 4 |
| 10 | Android Quick Autofill Shortcuts | Group 10 (5 tests) | B2: Cold-start race handling | T3.11, T3.12 (Quick search) | Scenario 4 |
| 11 | Bitwarden-Style UX Ergonomics | Group 11 (5 tests) | B5: Long text & custom fields | T3.9, T3.19 (Detail pane TOTP) | Scenario 1, 2 |
| 12 | Background Footprint Optimization | Group 12 (5 tests) | B7: RFC 6238 time boundaries | T3.9, T3.17 (Central ticker) | Scenario 1, 3 |
| 13 | Fast Startup Loading Acceleration | Group 13 (5 tests) | B8: Parallel batch limits | T3.10, T3.17 (Cache loading) | Scenario 5 |
| 14 | Comprehensive English README | Group 14 (5 tests) | B8: Formatting & links | System verification | Release docs |
| 15 | Bitwarden Security Comparison | Group 15 (5 tests) | B8: Quantitative assertions | Comparative audit | Security evaluation |

---

## 6. Test Isolation, Mocks, and Safety

- **Storage Isolation**: In-memory `SharedPreferences.setMockInitialValues` and `FlutterSecureStorage.setMockInitialValues` ensure no file or keychain artifacts persist between test executions.
- **Database Isolation**: In-memory SQLite (`sqfliteFfiInit` + temp db paths) ensures clean database tables for every test group.
- **Platform Channel Simulation**: Native channel calls (`com.multipad.multipad/native` and `plugins.flutter.io/local_auth`) are intercepted via `setMockMethodCallHandler` to simulate OS callbacks predictably.
- **Loopback Sockets**: Network bridge tests bind to ephemeral ports on `127.0.0.1` and cleanly close sockets on teardown.
- **Zero Production Code Intrusion**: Test code resides strictly in `test_e2e/` and leaves all production files under `lib/` and `android/` untouched.
