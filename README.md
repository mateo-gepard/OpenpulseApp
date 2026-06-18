# OpenPulse Companion

OpenPulse is a local-first companion app and firmware project for the OpenPulse wearable.

This repository currently contains:

- `MASTERPLAN.md` - the product, architecture, BLE, data, UX, and firmware masterplan.
- `src/` - a runnable React/TypeScript prototype of the companion app UI.
- `mobile/openpulse_app/` - the production Flutter companion app with real BLE and local SQLite storage.
- `firmware/openpulse_zephyr/` - Zephyr firmware for XIAO nRF52840 Sense and the OpenPulse BLE contract.
- `docs/CODEX_MAC_HANDOFF.md` - instructions for continuing this on macOS into a real iOS/Android app.
- `docs/BLE_CONTRACT.md` - the initial app/firmware BLE interface contract.

The production app target from the masterplan is Flutter for iOS and Android, with Zephyr RTOS firmware for the XIAO nRF52840 Sense hardware.

## Prototype

```bash
npm install
npm run dev
```

The prototype is not the final mobile implementation. It is a working visual and interaction reference for the production Flutter app.

## Production App

```bash
cd mobile/openpulse_app
flutter pub get
flutter analyze
flutter test
flutter build ios --no-codesign
```

The app scans for the real BLE advertising name `OpenPulse` and uses the BLE contract in `docs/BLE_CONTRACT.md`. It does not generate demo device data.

## Firmware

```bash
west build -p always -b xiao_ble/nrf52840/sense firmware/openpulse_zephyr
```

The firmware advertises as `OpenPulse`, exposes Device Information, Battery, and the OpenPulse custom service, and probes MAXM86161 at I2C `0x62` before reporting puck attachment.

## Production Direction

Use the macOS handoff document to continue with Codex on a Mac:

1. Build the Flutter mobile app.
2. Implement real BLE scan/connect/stream/backfill.
3. Build the Zephyr firmware exposing the shared BLE contract.
4. Test on physical iPhone, Android phone, and OpenPulse hardware.
