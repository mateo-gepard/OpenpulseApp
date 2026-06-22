# OpenPulse Metrics Algorithms

This document describes the current real-data v1 implementation. These metrics
are wellness/prototype metrics, not medical measurements.

## Where Computation Happens

| Metric | Computed on | Reason |
|---|---|---|
| Heart rate | XIAO firmware | Avoids streaming raw PPG continuously over BLE. |
| IBI | XIAO firmware | Needed for low-power HRV storage and reconnect backfill. |
| SpO2 | XIAO firmware | Uses red/IR AC/DC values before BLE compression. |
| HRV RMSSD/SDNN | iPhone app | Needs artifact filtering over stored IBI windows. |
| Confidence/calibration | Firmware + iPhone app | Firmware reports optical confidence; app reports HRV baseline progress. |

## Optical Sampling

The MAXM86161 is configured for green, IR, and red LED slots. The firmware drains
the optical FIFO every 250 ms and sends one compact live BLE record per second.
This keeps the sensor FIFO from overflowing without streaming raw PPG by default.

Raw high-frequency FIFO bytes are only sent when the app's live diagnostics view
explicitly requests a raw PPG window.

## Heart Rate And IBI

Heart rate uses green PPG because it usually gives the strongest short-path wrist
or finger perfusion signal.

The firmware uses a lightweight HeartPy-style adaptive threshold pipeline:

1. Maintains a circular green PPG window.
2. Computes adaptive min, max, mean, and dynamic range over the recent window.
3. Learns a rolling AC/DC baseline for the user's current optical fit.
4. Finds local maxima above an adaptive threshold.
5. Enforces a physiological IBI range of 333-2000 ms.
6. Uses the median IBI from recent accepted peaks.
7. Rejects sudden HR jumps as likely spikes unless confidence is already high.
8. Smooths accepted HR/IBI values and holds the last good value through brief bad
   windows instead of blinking to unavailable.
9. Converts IBI to heart rate with `bpm = 60000 / ibi_ms`.

Confidence ramps during the first 2 minutes, increases with clean beat count and
calibration progress, and drops under motion artifact or low perfusion. During
calibration the app still receives the current provisional value, but the quality
flag marks it as calibrating.

## HRV

The app computes HRV from stored IBI values, not from fake daily summaries.

The app:

1. Reads the last 5 minutes of IBI samples.
2. Rejects samples with low HR confidence, motion artifact, low perfusion,
   clipping, or out-of-range IBI.
3. Rejects abrupt IBI jumps that are likely missed/extra beats.
4. Computes RMSSD from successive IBI differences.
5. Computes SDNN from the clean IBI standard deviation.

Current HRV can appear after a clean 5-minute window. Baseline calibration
progress uses a 14-day target and counts days with enough clean IBI samples.
Before baseline completion, the UI still shows available live HRV but marks the
baseline as building.

## SpO2

SpO2 uses the standard red/IR ratio-of-ratios estimate:

```text
R = (AC_red / DC_red) / (AC_ir / DC_ir)
SpO2 = 110 - 25 * R
```

The firmware derives AC from the recent min/max range and DC from the mean for
red and IR samples. It learns a rolling red/IR ratio baseline, filters accepted
ratios, rejects implausible ratio spikes, and holds the last good SpO2 value
through brief noisy windows. It only reports `0xFF` when no recent usable value is
available or the sensor path is unavailable.

This is an empirical estimate. Real clinical-grade SpO2 requires device-specific
calibration against a reference pulse oximeter or controlled desaturation data.
The current implementation therefore caps SpO2 confidence below 100 and marks
the optical metric as calibrating/experimental.

## Calibration And Confidence

| Signal | First usable output | Full local window | Baseline target | Max confidence |
|---|---:|---:|---:|---:|
| HR | After enough clean peaks | 2 minutes | 6-hour optical learning window | 100 |
| SpO2 | After red/IR windows are stable | 10 minutes | 6-hour optical learning window plus external reference for true accuracy | 95 |
| HRV | After 5 clean minutes | 5 minutes | 14 clean days | 95 |

The optical calibration profile updates in two layers:

1. A fast rolling baseline updates on every good FIFO drain so the display stops
   flickering during the first minutes.
2. A slow calibration profile commits once per hour when enough clean windows
   were observed. The optical calibration percentage reaches 30% during the
   initial warmup, then moves continuously toward 100% across a 6-hour optical
   learning window. If an hour is noisy, the time progress still advances, but
   HR/SpO2 confidence remains lower until clean optical windows return.

Confidence is an algorithm-quality score. It is not a medical accuracy guarantee.
Charging the prototype between sessions is fine; stored app data is kept, and the
baseline progress is based on clean days rather than one uninterrupted battery
run.
