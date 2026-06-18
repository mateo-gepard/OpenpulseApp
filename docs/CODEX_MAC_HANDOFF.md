# Codex macOS Handoff

Use this repository on a Mac to turn the prototype and masterplan into installable iOS and Android software plus OpenPulse firmware.

## Goal

Build a real OpenPulse companion app, not a browser PWA:

- iOS installable through Xcode/TestFlight/App Store tooling.
- Android installable as APK/AAB.
- Local-first storage and BLE operation.
- Zephyr firmware for XIAO nRF52840 Sense + Puck 1 MAXM86161.
- Shared BLE contract from `docs/BLE_CONTRACT.md`.
- Helvetica typography throughout the app.

## Required macOS Tooling

- Xcode with iOS SDK.
- Apple ID for device install; paid Apple Developer account for TestFlight/App Store.
- Android Studio or Android command-line tools.
- Flutter stable channel.
- CocoaPods.
- Zephyr SDK and `west`.
- A physical iPhone, Android phone, and OpenPulse device for BLE testing.

## Recommended Build Sequence

1. Create a Flutter app under `mobile/openpulse_app`.
2. Port the prototype UI from `src/` into Flutter screens:
   - Home
   - Recovery
   - Sleep
   - Activity
   - Device
3. Use Helvetica everywhere:
   - iOS: system Helvetica/SF fallback.
   - Android: bundle or map to a Helvetica-compatible font only if required by licensing/tooling.
4. Add app modules:
   - `ble`
   - `storage`
   - `processing`
   - `models`
   - `ui`
   - `settings`
5. Implement BLE with a native-first reliability path:
   - Flutter UI.
   - Flutter plugin layer for ordinary BLE.
   - Native iOS CoreBluetooth state restoration if background behavior becomes a blocker.
   - Android foreground service for long-running connection/backfill.
6. Implement local storage:
   - Drift/SQLite for time-series aggregates.
   - Raw IBI windows for recent nights.
   - Score tables for recovery, sleep, strain, and calibration state.
7. Create Zephyr firmware under `firmware/openpulse_zephyr`.
8. Implement firmware services from `docs/BLE_CONTRACT.md`.
9. Validate end-to-end:
   - Pairing.
   - Time sync.
   - Live HR/IBI stream.
   - Battery notifications.
   - Backfill after phone disconnect.
   - Puck hotswap event.
   - Safe shutdown marker.

## First Codex Prompt On Mac

Use this prompt in Codex on macOS:

```text
Read MASTERPLAN.md, docs/CODEX_MAC_HANDOFF.md, and docs/BLE_CONTRACT.md.
Create a production Flutter app under mobile/openpulse_app for iOS and Android,
porting the existing prototype UI from src/ and using Helvetica everywhere.
Then scaffold Zephyr firmware under firmware/openpulse_zephyr for XIAO nRF52840
Sense with the BLE services in docs/BLE_CONTRACT.md. Build iOS simulator,
Android debug APK, and firmware compile targets if local tools are installed.
```

## Reality Check

Codex on a Mac can build the iOS project and run it on simulator immediately. Installing on a physical iPhone requires Xcode signing with your Apple ID. Shipping to other people requires the Apple Developer Program.
