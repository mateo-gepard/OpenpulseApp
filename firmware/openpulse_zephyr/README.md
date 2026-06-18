# OpenPulse Zephyr Firmware

Real-hardware firmware target for the OpenPulse XIAO nRF52840 Sense path.

## Target

```bash
west build -p always -b xiao_ble/nrf52840/sense firmware/openpulse_zephyr
```

For XIAO UF2 bootloader flashing:

```bash
west flash -r uf2
```

The board must be placed in UF2 bootloader mode physically before flashing.

## BLE Contract

This firmware advertises as `OpenPulse` and exposes:

- Standard Device Information service (`0x180A`)
- Standard Battery service (`0x180F`)
- OpenPulse custom service (`f04d0000-57f5-4f5a-9b80-4f6f2f1d0001`)

The MAXM86161 puck path is detected by probing I2C address `0x62` and reading
Part ID register `0xFF`. Expected value is `0x36`.

Live notifications are sent only after a valid time sync. HR/IBI remain `0`
until a real signal-processing path can produce values from sensor samples.
SpO2 uses the contract sentinel `0xFF` when unavailable.
