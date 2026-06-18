# OpenPulse Companion

OpenPulse is a local-first companion app and firmware project for the OpenPulse wearable.

This repository currently contains:

- `MASTERPLAN.md` - the product, architecture, BLE, data, UX, and firmware masterplan.
- `src/` - a runnable React/TypeScript prototype of the companion app UI.
- `docs/CODEX_MAC_HANDOFF.md` - instructions for continuing this on macOS into a real iOS/Android app.
- `docs/BLE_CONTRACT.md` - the initial app/firmware BLE interface contract.

The production app target from the masterplan is Flutter for iOS and Android, with Zephyr RTOS firmware for the XIAO nRF52840 Sense hardware.

## Prototype

```bash
npm install
npm run dev
```

The prototype is not the final mobile implementation. It is a working visual and interaction reference for the production Flutter app.

## Production Direction

Use the macOS handoff document to continue with Codex on a Mac:

1. Build the Flutter mobile app.
2. Implement real BLE scan/connect/stream/backfill.
3. Build the Zephyr firmware exposing the shared BLE contract.
4. Test on physical iPhone, Android phone, and OpenPulse hardware.
