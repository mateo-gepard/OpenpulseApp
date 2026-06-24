# OpenPulse Research Dashboard

Desktop Flutter/macOS dashboard for an asthma exposure study concept.

## Data model

- `Live data` uses real OpenPulse BLE hardware and the current firmware contract.
- `Overview`, `Cohort`, `Correlations`, and `Environment` use deterministic synthetic study data for 50 participants.
- OpenPulse devices advertising as `OpenPulse` or `OpenPulse ...` are accepted, including `OpenPulse Nova`.

## Run

```sh
flutter run -d macos
```

## Build

```sh
flutter build macos
```

The release app is produced at:

```text
build/macos/Build/Products/Release/OpenPulse Research Dashboard.app
```

## BLE live path

The live tab scans, connects, discovers the OpenPulse service, reads battery and puck status, writes time sync, subscribes to live frames, and can explicitly start/stop the high-rate raw PPG diagnostic stream.
