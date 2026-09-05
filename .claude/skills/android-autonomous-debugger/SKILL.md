---
layer: peripheral
name: android-autonomous-debugger
description: Usar cuando se depuran o testean apps Android contra dispositivos físicos via USB/ADB.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.context: fork
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Depuracion autonoma de apps Android contra dispositivos fisicos via USB/ADB. Detecta crashes, ANRs, memory leaks. Ejecuta tests instrumentados. Output: informe con screenshots, logs y sugerencias de fix."
  savia.tags: "android, debugging, adb, mobile-testing"
---

# Android Autonomous Debugger

**Trigger**: When the user asks to debug, test, or verify an Android app on a physical device, or when a build-and-test cycle is needed against a connected Android device.

**Keywords**: android debug, test on device, install apk, check crash, mobile testing, e2e test, verify on phone, run on device, screen capture device.

## CRITICAL: Use adb-run.sh for All Commands

**NEVER use `source scripts/lib/adb-wrapper.sh && cmd1 && cmd2`** — Claude Code's shell-aware permission system blocks compound `&&`/`||` chains, causing permission popups that break autonomous operation.

**ALWAYS use `./scripts/adb-run.sh`** which wraps everything in a single command:

```bash
# WRONG — causes permission popups:
source scripts/lib/adb-wrapper.sh && adb_auto_select && adb_screenshot /tmp/s.png

# CORRECT — single command, no popups:
./scripts/adb-run.sh adb_auto_select "adb_screenshot /tmp/s.png"
```

Each argument is one function call. Quote arguments with spaces:
```bash
./scripts/adb-run.sh adb_auto_select "adb_tap 500 900" "adb_screenshot /tmp/after.png"
./scripts/adb-run.sh adb_auto_select "adb_install ./app.apk" "adb_launch com.savia.mobile"
./scripts/adb-run.sh adb_auto_select "adb_logcat_errors 30 com.savia.mobile"
```

## Prerequisites

- Android device connected via USB with USB debugging enabled
- ADB available (auto-detected from Android SDK)
- APK built and ready (or source available to build)

## Core Capabilities

### 1. Device Discovery
```bash
./scripts/adb-run.sh adb_auto_select adb_device_info
./scripts/adb-run.sh adb_devices
```

### 2. APK Lifecycle
```bash
./scripts/adb-run.sh adb_auto_select "adb_install ./path/to/app.apk"
./scripts/adb-run.sh adb_auto_select "adb_uninstall com.package.name"
./scripts/adb-run.sh adb_auto_select "adb_launch com.package.name"
./scripts/adb-run.sh adb_auto_select "adb_stop com.package.name"
./scripts/adb-run.sh adb_auto_select "adb_clear_data com.package.name"
```

### 3. Visual Inspection
```bash
./scripts/adb-run.sh adb_auto_select "adb_screenshot /tmp/screen.png"
./scripts/adb-run.sh adb_auto_select "adb_hierarchy /tmp/ui.xml"
./scripts/adb-run.sh adb_auto_select "adb_snapshot /tmp/prefix"
```

### 4. UI Interaction
```bash
./scripts/adb-run.sh adb_auto_select "adb_tap 500 900"
./scripts/adb-run.sh adb_auto_select "adb_tap_id login_button"
./scripts/adb-run.sh adb_auto_select "adb_tap_text Conectar"
./scripts/adb-run.sh adb_auto_select "adb_swipe 500 1200 500 400 300"
./scripts/adb-run.sh adb_auto_select adb_scroll_down
./scripts/adb-run.sh adb_auto_select "adb_type hello_world"
./scripts/adb-run.sh adb_auto_select "adb_key back"
```

### 5. Debugging
```bash
./scripts/adb-run.sh adb_auto_select adb_logcat_clear
./scripts/adb-run.sh adb_auto_select "adb_logcat_errors 30"
./scripts/adb-run.sh adb_auto_select "adb_logcat_errors 60 com.savia.mobile"
./scripts/adb-run.sh adb_auto_select "adb_detect_crash 60"
./scripts/adb-run.sh adb_auto_select "adb_meminfo com.savia.mobile"
```

### 6. Element Finding & Waiting
```bash
./scripts/adb-run.sh adb_auto_select "adb_find_by_id btn_send"
./scripts/adb-run.sh adb_auto_select "adb_find_by_text Savia"
./scripts/adb-run.sh adb_auto_select "adb_wait_for_text Welcome 15"
./scripts/adb-run.sh adb_auto_select "adb_wait_for_id main_screen 10"
```

## Autonomous Debug Cycle

When asked to verify an app on device, follow this cycle:

### Phase 1: Setup
```bash
./scripts/adb-run.sh adb_auto_select adb_device_info adb_logcat_clear
```

### Phase 2: Install & Launch
```bash
./scripts/adb-run.sh adb_auto_select "adb_install <path>" "adb_launch <package>" "adb_wait_for_text MainScreen 15" "adb_screenshot /tmp/baseline.png"
```

### Phase 3: Interact & Verify
For each screen/feature to test:
```bash
./scripts/adb-run.sh adb_auto_select "adb_tap_text FeatureName" "adb_wait_for_text ExpectedText 10" "adb_screenshot /tmp/feature-X.png" "adb_logcat_errors 10"
```

If a crash is detected:
```bash
./scripts/adb-run.sh adb_auto_select "adb_detect_crash 30" "adb_logcat_errors 60 com.package"
```

### Phase 4: Report
Summarize: PASS/FAIL per screen tested. Include screenshots as evidence. Include crash logs if any. Suggest fixes based on stack traces.

## Security Model

Operations are classified into three security levels:

| Level | Examples | Behavior |
|-------|----------|----------|
| **Safe** | screenshot, logcat, hierarchy, tap, type | Auto-approved |
| **Risky** | install, uninstall, force-stop, clear data | Logged, allowed |
| **Blocked** | rm -rf, format, su, dd | Always rejected |
The `android-adb-validate.sh` hook enforces this classification.
## Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `ADB_PATH` | auto-detect | Path to ADB binary |
| `ADB_DEVICE` | auto-select | Target device serial |
| `ADB_RETRIES` | 3 | Max retries per command |
| `ADB_TIMEOUT` | 30 | Command timeout (seconds) |
## Tips for Agents
- **ALWAYS use `./scripts/adb-run.sh`** — never `source wrapper.sh && ...`
- Always start with `adb_auto_select`; chain many functions in one call
- Screenshots BEFORE and AFTER each interaction; use `adb_wait_for_text` instead of `sleep`
