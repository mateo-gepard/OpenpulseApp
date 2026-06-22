import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/openpulse_controller.dart';
import '../models/openpulse_models.dart';
import '../time/openpulse_time.dart';

const _bg = Color(0xff10181c);
const _surface = Color(0xff1c262b);
const _surface2 = Color(0xff263137);
const _line = Color(0xff344148);
const _text = Color(0xfff5f7f8);
const _muted = Color(0xff97a1a8);
const _red = Color(0xfff2353d);
const _navy = Color(0xff081633);
const _blush = Color(0xffc98d80);
const _mint = Color(0xff65f0cd);
const _blue = Color(0xff78bdf8);
const _amber = Color(0xffffc65a);

class OpenPulseApp extends StatelessWidget {
  const OpenPulseApp({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Helvetica',
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _red,
          brightness: Brightness.dark,
          primary: _red,
          secondary: _mint,
          surface: _surface,
        ),
        textTheme: Typography.whiteCupertino.apply(
          fontFamily: 'Helvetica',
          bodyColor: _text,
          displayColor: _text,
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 8,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
        ),
      ),
      home: OpenPulseShell(controller: controller),
    );
  }
}

class OpenPulseShell extends StatefulWidget {
  const OpenPulseShell({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  State<OpenPulseShell> createState() => _OpenPulseShellState();
}

class _OpenPulseShellState extends State<OpenPulseShell> {
  int _tab = 0;

  static const _tabs = [
    (Icons.home_rounded, 'Today'),
    (Icons.monitor_heart_rounded, 'Live'),
    (Icons.calendar_month_rounded, 'History'),
    (Icons.tune_rounded, 'Device'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final pages = [
          TodayView(controller: controller),
          LiveView(controller: controller),
          HistoryView(controller: controller),
          DeviceView(controller: controller),
        ];

        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    controller: controller,
                    title: _tabs[_tab].$2,
                    showDateControls: _tab == 0 || _tab == 2,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 116),
                  sliver: SliverToBoxAdapter(child: pages[_tab]),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _BottomNav(
            selectedIndex: _tab,
            tabs: _tabs,
            onSelected: (index) {
              if (index != 1) {
                unawaited(controller.stopRawPpgDiagnostics());
              }
              setState(() => _tab = index);
            },
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.title,
    required this.showDateControls,
  });

  final OpenPulseController controller;
  final String title;
  final bool showDateControls;

  @override
  Widget build(BuildContext context) {
    final live = controller.phase == ConnectionPhase.streaming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LogoMark(size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      controller.statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                icon: live ? Icons.bluetooth_connected : Icons.bluetooth,
                label: live ? 'Live' : controller.phase.label,
                color: live ? _mint : _amber,
              ),
            ],
          ),
          if (showDateControls) ...[
            const SizedBox(height: 18),
            _DateSwitcher(controller: controller),
          ],
        ],
      ),
    );
  }
}

class TodayView extends StatelessWidget {
  const TodayView({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLiveRecord;
    final battery = controller.latestBattery;
    final puck = controller.latestPuckStatus;
    final summary = controller.selectedDaySummary;
    final hrv = controller.latestHrvSummary;
    final steps = controller.selectedDayStepCount;
    final stepProgress = steps == null
        ? 0.0
        : (steps / controller.stepGoal).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroPanel(
          controller: controller,
          steps: steps,
          stepProgress: stepProgress,
        ),
        const SizedBox(height: 18),
        _StepGoalPanel(
          controller: controller,
          steps: steps,
          stepProgress: stepProgress,
        ),
        const SizedBox(height: 18),
        _RingRow(
          children: [
            _MetricRing(
              label: 'Steps',
              value: steps?.toString() ?? '--',
              footer: '${controller.stepGoal} goal',
              progress: stepProgress,
              color: _mint,
            ),
            _MetricRing(
              label: 'Live',
              value: controller.livePacketCount.toString(),
              footer: 'packets',
              progress: controller.livePacketCount == 0
                  ? 0
                  : (controller.livePacketCount / 120).clamp(0.0, 1.0),
              color: _blue,
            ),
            _MetricRing(
              label: 'HR',
              value: live?.heartRateBpm == null
                  ? '--'
                  : live!.heartRateBpm!.toStringAsFixed(0),
              footer: live?.hrStatusLabel ?? 'warming up',
              progress: ((live?.hrConfidence ?? 0) / 100).clamp(0.0, 1.0),
              color: _red,
            ),
            _MetricRing(
              label: 'SpO2',
              value: live?.spo2Percent == null ? '--' : '${live!.spo2Percent}',
              footer: live?.spo2StatusLabel ?? 'stillness only',
              progress: ((live?.spo2Confidence ?? 0) / 100).clamp(0.0, 1.0),
              color: _amber,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _CalibrationPanel(
          live: live,
          hrv: hrv,
          timeline: controller.calibrationTimeline,
          compact: true,
        ),
        const SizedBox(height: 18),
        _MetricStrip(
          items: [
            _StripItem(
              icon: Icons.favorite_rounded,
              label: 'HR',
              value: live?.heartRateBpm == null
                  ? live?.hrStatusLabel ?? 'Not computed'
                  : '${live!.heartRateBpm!.toStringAsFixed(1)} bpm · ${live.hrConfidenceLabel}',
            ),
            _StripItem(
              icon: Icons.timeline_rounded,
              label: 'HRV',
              value: hrv?.available == true
                  ? 'RMSSD ${hrv!.rmssdMs!.toStringAsFixed(0)} ms · ${hrv.confidence}%'
                  : hrv?.status ?? 'Needs clean IBI',
            ),
            _StripItem(
              icon: Icons.water_drop_rounded,
              label: 'SpO2',
              value: live?.spo2Percent == null
                  ? live?.spo2StatusLabel ?? 'Stillness only'
                  : '${live!.spo2Percent}% · ${live.spo2ConfidenceLabel}',
            ),
            _StripItem(
              icon: Icons.memory_rounded,
              label: 'Puck',
              value: puck == null
                  ? 'Waiting'
                  : puck.attached
                  ? 'Attached'
                  : puck.sensorLabel,
            ),
            _StripItem(
              icon: Icons.battery_5_bar_rounded,
              label: 'Battery',
              value: battery?.display ?? 'Unavailable',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle('Today'),
        _Surface(
          child: Column(
            children: [
              _FactRow(
                'Live records',
                summary?.liveRecords.toString() ?? 'Waiting',
              ),
              _FactRow(
                'Last sync',
                summary?.lastLiveAt == null
                    ? 'Waiting'
                    : _timeAgo(summary!.lastLiveAt!),
              ),
              _FactRow(
                'Backfill requests',
                summary?.controlWrites.toString() ?? 'Waiting',
              ),
              _FactRow(
                'Metric calibration',
                '${_percent(live?.calibrationProgress)} optical · ${_percent(hrv?.calibrationProgress)} HRV baseline',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.controller,
    required this.steps,
    required this.stepProgress,
  });

  final OpenPulseController controller;
  final int? steps;
  final double stepProgress;

  @override
  Widget build(BuildContext context) {
    final live = controller.phase == ConnectionPhase.streaming;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  live ? 'OpenPulse is streaming' : 'Waiting for OpenPulse',
                  style: const TextStyle(
                    fontSize: 25,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: live
                    ? controller.disconnect
                    : controller.scanAndConnect,
                icon: Icon(live ? Icons.bluetooth_disabled : Icons.bluetooth),
                label: Text(live ? 'Stop' : 'Scan'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      steps?.toString() ?? '--',
                      style: const TextStyle(
                        fontSize: 58,
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'hardware steps',
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              _LogoMark(size: 84),
            ],
          ),
          const SizedBox(height: 22),
          _ProgressLine(
            value: stepProgress,
            color: _mint,
            label: 'Step goal',
            trailing: '${(stepProgress * 100).round()}%',
          ),
        ],
      ),
    );
  }
}

class _StepGoalPanel extends StatelessWidget {
  const _StepGoalPanel({
    required this.controller,
    required this.steps,
    required this.stepProgress,
  });

  final OpenPulseController controller;
  final int? steps;
  final double stepProgress;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: _mint),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Daily step goal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${controller.stepGoal}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProgressLine(
            value: stepProgress,
            color: _mint,
            label: steps == null ? 'Waiting for IMU steps' : '$steps steps',
            trailing: '${(stepProgress * 100).round()}%',
          ),
          const SizedBox(height: 14),
          _SliderRow(
            label: 'Goal',
            value: controller.stepGoal.toDouble(),
            min: 500,
            max: 50000,
            divisions: 99,
            suffix: 'steps',
            onChanged: (value) => controller.setStepGoal(_snapStepGoal(value)),
          ),
        ],
      ),
    );
  }
}

class LiveView extends StatelessWidget {
  const LiveView({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLiveRecord;
    final raw = controller.latestRawPpgFrame;
    final rawEnabled = controller.rawPpgDiagnosticEnabled;
    final hrv = controller.latestHrvSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('High-rate optical'),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rawEnabled
                              ? 'Raw sensor mode is active'
                              : 'Raw sensor mode is off',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rawEnabled
                              ? 'Streaming green PPG at 128 Hz; red/IR stay on for SpO2.'
                              : 'Tap Start only when you want to inspect the optical waveform.',
                          style: const TextStyle(color: _muted, height: 1.25),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: controller.customServiceReady
                        ? rawEnabled
                              ? controller.stopRawPpgDiagnostics
                              : controller.startRawPpgDiagnostics
                        : null,
                    icon: Icon(rawEnabled ? Icons.stop_rounded : Icons.bolt),
                    label: Text(rawEnabled ? 'Stop' : 'Start'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProgressLine(
                value: rawEnabled ? 1 : 0,
                color: rawEnabled ? _red : _line,
                label: 'Battery-heavy diagnostic',
                trailing: rawEnabled ? 'on' : 'off',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Raw PPG output'),
        _Surface(
          child: SizedBox(
            height: 250,
            child: _PpgPlot(
              samples: rawEnabled ? controller.recentRawPpgSamples : const [],
              emptyLabel: rawEnabled
                  ? 'Waiting for high-rate PPG samples'
                  : 'Start raw sensor mode to plot PPG',
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Motion output'),
        _Surface(
          child: SizedBox(
            height: 166,
            child: _LinePlot(
              values: controller.recentLiveRecords
                  .map((record) => record.accelMilliG ?? 0)
                  .where((value) => value > 0)
                  .toList(growable: false),
              color: _mint,
              emptyLabel: 'Waiting for accelerometer records',
            ),
          ),
        ),
        const SizedBox(height: 18),
        _MetricStrip(
          items: [
            _StripItem(
              icon: Icons.numbers_rounded,
              label: 'Live packets',
              value: controller.livePacketCount.toString(),
            ),
            _StripItem(
              icon: Icons.straighten_rounded,
              label: 'Frame bytes',
              value: controller.latestLiveFrameByteCount == 0
                  ? '--'
                  : controller.latestLiveFrameByteCount.toString(),
            ),
            _StripItem(
              icon: Icons.directions_walk_rounded,
              label: 'Pedometer',
              value: live?.motionLabel ?? 'Waiting',
            ),
            _StripItem(
              icon: Icons.favorite_rounded,
              label: 'HR certainty',
              value: live?.hrStatusLabel ?? 'Warming up',
            ),
            _StripItem(
              icon: Icons.water_drop_rounded,
              label: 'SpO2 certainty',
              value: live?.spo2StatusLabel ?? 'Stillness only',
            ),
            _StripItem(
              icon: Icons.timeline_rounded,
              label: 'HRV RMSSD',
              value: hrv?.available == true
                  ? '${hrv!.rmssdMs!.toStringAsFixed(0)} ms'
                  : hrv?.status ?? 'Needs IBI',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _CalibrationPanel(
          live: live,
          hrv: hrv,
          timeline: controller.calibrationTimeline,
          compact: false,
        ),
        const SizedBox(height: 18),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FactRow('Live sequence', live?.sequence.toString() ?? 'Waiting'),
              _FactRow(
                'Device uptime',
                live == null ? 'Waiting' : '${live.deviceUptimeMs} ms',
              ),
              _FactRow(
                'Accel magnitude',
                live?.accelMilliG == null
                    ? 'Waiting'
                    : '${live!.accelMilliG} mg',
              ),
              _FactRow(
                'Raw PPG',
                raw == null
                    ? 'Waiting'
                    : raw.payloadLength > 0
                    ? '${raw.payloadLength} bytes'
                    : raw.sensorLabel,
              ),
              _FactRow(
                'HR',
                live?.heartRateBpm == null
                    ? live?.hrStatusLabel ?? 'Waiting'
                    : '${live!.heartRateBpm!.toStringAsFixed(1)} bpm (${live.hrConfidenceLabel})',
              ),
              _FactRow(
                'IBI',
                live?.ibiMs == null ? 'Waiting' : '${live!.ibiMs} ms',
              ),
              _FactRow(
                'SpO2',
                live?.spo2Percent == null
                    ? live?.spo2StatusLabel ?? 'Waiting'
                    : '${live!.spo2Percent}% (${live.spo2ConfidenceLabel})',
              ),
              _FactRow(
                'HRV',
                hrv?.available == true
                    ? hrv!.sdnnMs != null
                          ? 'RMSSD ${hrv.rmssdMs!.toStringAsFixed(0)} ms, SDNN ${hrv.sdnnMs!.toStringAsFixed(0)} ms (${hrv.confidence}%)'
                          : 'RMSSD ${hrv.rmssdMs!.toStringAsFixed(0)} ms (${hrv.confidence}%)'
                    : hrv?.status ?? 'Needs clean beats',
              ),
              const SizedBox(height: 12),
              _HexBox(text: _hexPreview(controller.latestLiveFrameHex)),
            ],
          ),
        ),
      ],
    );
  }
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final summary = controller.selectedDaySummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Surface(
          child: Column(
            children: [
              _FactRow('Date', _dayLabel(controller.selectedDay)),
              _FactRow('Live records', summary?.liveRecords.toString() ?? '0'),
              _FactRow(
                'Raw PPG frames',
                summary?.rawPpgFrames.toString() ?? '0',
              ),
              _FactRow('Puck events', summary?.puckEvents.toString() ?? '0'),
              _FactRow('Steps', summary?.stepCount?.toString() ?? '--'),
              _FactRow(
                'Raw max counter',
                summary?.maxSteps?.toString() ?? '--',
              ),
              _FactRow(
                'Last live sync',
                summary?.lastLiveAt == null
                    ? 'No live records'
                    : _clock(summary!.lastLiveAt!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Sync state'),
        _Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressLine(
                value: summary?.hasData == true ? 1 : 0,
                color: _blue,
                label: 'Day data',
                trailing: summary?.hasData == true ? 'present' : 'empty',
              ),
              const SizedBox(height: 12),
              _ProgressLine(
                value: controller.phase == ConnectionPhase.streaming ? 1 : 0,
                color: _mint,
                label: 'Current link',
                trailing: controller.phase.label,
              ),
              const SizedBox(height: 12),
              _ProgressLine(
                value: controller.deviceRestoreInProgress ? 0.5 : 1,
                color: _amber,
                label: 'Device restore',
                trailing: controller.deviceRestoreInProgress
                    ? '${controller.deviceRestoreRecordCount} records'
                    : controller.lastDeviceRestoreAt == null
                    ? 'waiting'
                    : '${controller.deviceRestoreRecordCount} restored',
              ),
              const SizedBox(height: 16),
              Text(
                'On connect, OpenPulse asks only for device-local records newer than the latest matching local sample, then stores the new rows locally.',
                style: const TextStyle(color: _muted, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Calibration'),
        _MetricStrip(
          items: [
            _StripItem(
              icon: Icons.favorite_rounded,
              label: 'HR',
              value:
                  controller.latestLiveRecord?.hrStatusLabel ??
                  'Needs 15-30s signal',
            ),
            _StripItem(
              icon: Icons.timeline_rounded,
              label: 'HRV',
              value:
                  '${controller.latestHrvSummary?.calibrationProgress ?? 0}% baseline',
            ),
            _StripItem(
              icon: Icons.water_drop_rounded,
              label: 'SpO2',
              value:
                  controller.latestLiveRecord?.spo2StatusLabel ??
                  'Stillness only',
            ),
          ],
        ),
      ],
    );
  }
}

class DeviceView extends StatelessWidget {
  const DeviceView({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final puck = controller.latestPuckStatus;
    final battery = controller.latestBattery;
    final batteryEstimate = controller.batteryEstimate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Surface(
          child: Column(
            children: [
              _FactRow('GATT', controller.gattReady ? 'Ready' : 'Waiting'),
              _FactRow(
                'OpenPulse BLE',
                controller.customServiceReady ? 'Ready' : 'Waiting',
              ),
              _FactRow(
                'Puck',
                puck == null
                    ? 'Waiting'
                    : puck.attached
                    ? 'Attached'
                    : puck.sensorLabel,
              ),
              _FactRow('Battery', battery?.display ?? 'Unavailable'),
              _FactRow(
                'Notifications',
                controller.notificationPermissionGranted
                    ? 'Allowed'
                    : 'Needs permission',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Power'),
        _Surface(
          child: batteryEstimate == null
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FactRow('Remaining', 'Waiting for battery sample'),
                    _FactRow('Estimated draw', 'Unavailable'),
                    Text(
                      'OpenPulse reports battery percentage over BLE. Runtime and current need a battery sample before the app can estimate them.',
                      style: TextStyle(color: _muted, height: 1.35),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProgressLine(
                      value: batteryEstimate.level / 100,
                      color: batteryEstimate.level <= 15 ? _red : _mint,
                      label: 'Battery',
                      trailing: '${batteryEstimate.level}%',
                    ),
                    const SizedBox(height: 14),
                    _FactRow('Runtime left', batteryEstimate.runtimeLabel),
                    _FactRow('Power left', batteryEstimate.remainingLabel),
                    _FactRow('Estimated draw', batteryEstimate.currentLabel),
                    _FactRow(
                      'Mode',
                      controller.rawPpgDiagnosticEnabled
                          ? 'Raw diagnostic'
                          : controller.selectedMode.label,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      batteryEstimate.basis,
                      style: const TextStyle(color: _muted, height: 1.35),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('PPG controls'),
        _Surface(
          child: Column(
            children: [
              _SliderRow(
                label: 'Sampling',
                value: controller.samplingHz.toDouble(),
                min: 25,
                max: 128,
                divisions: 103,
                suffix: 'Hz',
                onChanged: controller.customServiceReady
                    ? (value) => controller.writeSampling(value.round())
                    : null,
              ),
              _SliderRow(
                label: 'Green LED',
                value: controller.ledGreenMa.toDouble(),
                min: 0,
                max: 24,
                divisions: 24,
                suffix: 'mA',
                onChanged: controller.customServiceReady
                    ? (value) => controller.writeLed(
                        greenMa: value.round(),
                        redMa: controller.ledRedMa,
                        irMa: controller.ledIrMa,
                      )
                    : null,
              ),
              _SliderRow(
                label: 'Red LED',
                value: controller.ledRedMa.toDouble(),
                min: 0,
                max: 24,
                divisions: 24,
                suffix: 'mA',
                onChanged: controller.customServiceReady
                    ? (value) => controller.writeLed(
                        greenMa: controller.ledGreenMa,
                        redMa: value.round(),
                        irMa: controller.ledIrMa,
                      )
                    : null,
              ),
              _SliderRow(
                label: 'IR LED',
                value: controller.ledIrMa.toDouble(),
                min: 0,
                max: 24,
                divisions: 24,
                suffix: 'mA',
                onChanged: controller.customServiceReady
                    ? (value) => controller.writeLed(
                        greenMa: controller.ledGreenMa,
                        redMa: controller.ledRedMa,
                        irMa: value.round(),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.customServiceReady
                      ? controller.requestBackfill
                      : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync missing data'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Debug export'),
        _Surface(
          child: Column(
            children: [
              _FactRow(
                'Last export',
                controller.latestDebugExport?.fileName ?? 'Not exported',
              ),
              _FactRow(
                'Rows',
                controller.latestDebugExport?.summary ?? 'Waiting',
              ),
              if (controller.debugExportError != null)
                _FactRow('Error', controller.debugExportError!),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.debugExportInProgress
                      ? null
                      : controller.exportDebugData,
                  icon: Icon(
                    controller.debugExportInProgress
                        ? Icons.hourglass_top_rounded
                        : Icons.ios_share_rounded,
                  ),
                  label: Text(
                    controller.debugExportInProgress
                        ? 'Exporting'
                        : 'Export debug data',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionTitle('Device information'),
        _Surface(
          child: Column(
            children: [
              _FactRow('Name', controller.deviceName ?? 'OpenPulse'),
              _FactRow(
                'Firmware',
                controller.deviceInformation.firmware ?? 'Unavailable',
              ),
              _FactRow(
                'Hardware',
                controller.deviceInformation.hardware ?? 'Unavailable',
              ),
              _FactRow(
                'Battery path',
                battery?.available == true
                    ? 'Standard BLE Battery'
                    : 'ADC not mapped',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateSwitcher extends StatelessWidget {
  const _DateSwitcher({required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: controller.selectPreviousDay,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Text(
                _dayLabel(controller.selectedDay),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: controller.selectNextDay,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.selectedIndex,
    required this.tabs,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<(IconData, String)> tabs;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        height: 74,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xf01b252a),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: _BottomNavButton(
                  icon: tabs[i].$1,
                  label: tabs[i].$2,
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _text : _muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 25, color: color),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RingRow extends StatelessWidget {
  const _RingRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final child in children) ...[child, const SizedBox(width: 14)],
        ],
      ),
    );
  }
}

class _MetricRing extends StatelessWidget {
  const _MetricRing({
    required this.label,
    required this.value,
    required this.footer,
    required this.progress,
    required this.color,
  });

  final String label;
  final String value;
  final String footer;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Column(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CustomPaint(
              painter: _RingPainter(progress: progress, color: color),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            footer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CalibrationPanel extends StatefulWidget {
  const _CalibrationPanel({
    required this.live,
    required this.hrv,
    required this.timeline,
    required this.compact,
  });

  final LiveRecord? live;
  final HrvSummary? hrv;
  final CalibrationTimeline? timeline;
  final bool compact;

  @override
  State<_CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<_CalibrationPanel> {
  bool _expanded = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opticalProgress = _normalizedPercent(
      widget.live?.calibrationProgress,
    );
    final hrProgress = _normalizedPercent(widget.live?.hrConfidence);
    final spo2Progress = _normalizedPercent(widget.live?.spo2Confidence);
    final hrvProgress = _normalizedPercent(widget.hrv?.calibrationProgress);
    final opticalPercent = _percent(widget.live?.calibrationProgress);
    final hrvPercent = _percent(widget.hrv?.calibrationProgress);

    return _Surface(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _surface2,
                  ),
                  child: const Icon(Icons.auto_graph_rounded, color: _mint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Calibration',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _calibrationPhase(widget.live?.calibrationProgress),
                        style: const TextStyle(color: _muted, height: 1.25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _nextCalibrationLabel(widget.timeline),
                        style: const TextStyle(
                          color: _mint,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      opticalPercent,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: _expanded ? 'Collapse' : 'Expand',
                      onPressed: () {
                        setState(() => _expanded = !_expanded);
                      },
                      icon: Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ProgressLine(
              value: opticalProgress,
              color: _mint,
              label: 'Optical profile',
              trailing:
                  '$opticalPercent · ${_calibrationShortLabel(widget.live?.calibrationProgress)}',
            ),
            const SizedBox(height: 12),
            _ProgressLine(
              value: hrProgress,
              color: _red,
              label: 'HR confidence',
              trailing: widget.live?.hrStatusLabel ?? 'waiting',
            ),
            const SizedBox(height: 12),
            _ProgressLine(
              value: spo2Progress,
              color: _amber,
              label: 'SpO2 confidence',
              trailing: widget.live?.spo2StatusLabel ?? 'waiting',
            ),
            if (!widget.compact || _expanded) ...[
              const SizedBox(height: 12),
              _ProgressLine(
                value: hrvProgress,
                color: _blue,
                label: 'HRV baseline',
                trailing: '$hrvPercent · ${widget.hrv?.status ?? 'needs IBI'}',
              ),
              const SizedBox(height: 14),
              _CalibrationLegend(
                opticalProgress: widget.live?.calibrationProgress,
                hrvProgress: widget.hrv?.calibrationProgress,
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 360,
                child: _CalibrationTimelinePlot(timeline: widget.timeline),
              ),
              const SizedBox(height: 12),
              const _CalibrationPlotLegend(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalibrationTimelinePlot extends StatelessWidget {
  const _CalibrationTimelinePlot({required this.timeline});

  final CalibrationTimeline? timeline;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CalibrationTimelinePainter(timeline: timeline),
      child: const SizedBox.expand(),
    );
  }
}

class _CalibrationTimelinePainter extends CustomPainter {
  const _CalibrationTimelinePainter({required this.timeline});

  final CalibrationTimeline? timeline;

  @override
  void paint(Canvas canvas, Size size) {
    final points = timeline?.points ?? const <CalibrationTimelinePoint>[];
    if (points.length < 2) {
      _paintCenteredLabel(canvas, size, 'Waiting for calibration samples');
      return;
    }

    final start = points.first.time.millisecondsSinceEpoch;
    final end = points.last.time.millisecondsSinceEpoch;
    final spanMs = math.max(1, end - start);
    final plot = Rect.fromLTWH(
      58,
      10,
      math.max(20, size.width - 86),
      math.max(20, size.height - 40),
    );
    final hrvUpper = _hrvUpperBound(points);
    final lanes = [
      _CalibrationLane(
        label: 'HR',
        unit: 'bpm',
        min: 40,
        max: 190,
        color: _red,
        valueFor: (point) => point.heartRateBpm,
        format: (value) => value.toStringAsFixed(0),
      ),
      _CalibrationLane(
        label: 'SpO2',
        unit: '%',
        min: 70,
        max: 100,
        color: _amber,
        valueFor: (point) => point.spo2Percent?.toDouble(),
        format: (value) => value.toStringAsFixed(0),
      ),
      _CalibrationLane(
        label: 'HRV',
        unit: 'ms',
        min: 0,
        max: hrvUpper,
        color: _blue,
        valueFor: (point) => point.hrvRmssdMs,
        format: (value) => value.toStringAsFixed(0),
      ),
      _CalibrationLane(
        label: 'Profile',
        unit: '%',
        min: 0,
        max: 100,
        color: _mint,
        valueFor: (point) => point.calibrationProgress?.toDouble(),
        format: (value) => value.toStringAsFixed(0),
      ),
    ];
    const laneGap = 12.0;
    final laneHeight =
        (plot.height - laneGap * (lanes.length - 1)) / lanes.length;

    double xFor(DateTime time) {
      final offset = time.millisecondsSinceEpoch - start;
      return plot.left + (offset / spanMs) * plot.width;
    }

    final laneRects = <Rect>[];
    for (var i = 0; i < lanes.length; i++) {
      final lane = Rect.fromLTWH(
        plot.left,
        plot.top + i * (laneHeight + laneGap),
        plot.width,
        laneHeight,
      );
      laneRects.add(lane);
      _drawLaneFrame(canvas, lane, lanes[i]);
    }

    final marks = timeline?.updateMarks ?? const <CalibrationUpdateMark>[];
    _drawCalibrationMarks(
      canvas: canvas,
      marks: marks,
      first: points.first.time,
      last: points.last.time,
      plot: plot,
      profileLane: laneRects.last,
      xFor: xFor,
    );

    for (var i = 0; i < lanes.length; i++) {
      _drawLaneSeries(
        canvas: canvas,
        points: points,
        lane: lanes[i],
        rect: laneRects[i],
        xFor: xFor,
      );
    }

    _paintAxisLabel(canvas, size, points.first.time, Alignment.bottomLeft);
    _paintAxisLabel(canvas, size, points.last.time, Alignment.bottomRight);
    _paintRangeLabel(canvas, size, points.first.time, points.last.time);
  }

  double _hrvUpperBound(List<CalibrationTimelinePoint> points) {
    final values = [
      for (final point in points)
        if (point.hrvRmssdMs != null && point.hrvRmssdMs!.isFinite)
          point.hrvRmssdMs!,
    ]..sort();
    if (values.isEmpty) {
      return 120;
    }
    final index = ((values.length - 1) * 0.9).round();
    final upper = math.max(80.0, values[index] * 1.35);
    return (_ceilToStep(upper, 20)).clamp(80.0, 300.0).toDouble();
  }

  double _ceilToStep(double value, double step) {
    return (value / step).ceil() * step;
  }

  void _drawLaneFrame(Canvas canvas, Rect rect, _CalibrationLane lane) {
    final bandPaint = Paint()..color = _surface2.withValues(alpha: 0.26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      bandPaint,
    );
    final gridPaint = Paint()
      ..color = _line.withValues(alpha: 0.68)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.right, rect.bottom),
      Paint()
        ..color = _line
        ..strokeWidth = 1,
    );

    _paintText(
      canvas,
      lane.label,
      Offset(0, rect.top + 2),
      color: lane.color,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      maxWidth: 52,
    );
    _paintText(
      canvas,
      lane.unit,
      Offset(0, rect.top + 19),
      color: _muted,
      fontSize: 10,
      maxWidth: 52,
    );
    _paintText(
      canvas,
      lane.format(lane.max),
      Offset(rect.right + 6, rect.top - 1),
      color: _muted,
      fontSize: 9,
      maxWidth: 24,
    );
    _paintText(
      canvas,
      lane.format(lane.min),
      Offset(rect.right + 6, rect.bottom - 12),
      color: _muted,
      fontSize: 9,
      maxWidth: 24,
    );
  }

  void _drawCalibrationMarks({
    required Canvas canvas,
    required List<CalibrationUpdateMark> marks,
    required DateTime first,
    required DateTime last,
    required Rect plot,
    required Rect profileLane,
    required double Function(DateTime time) xFor,
  }) {
    final visibleMarks = [
      for (final mark in marks)
        if (!mark.time.isBefore(first) && !mark.time.isAfter(last)) mark,
    ];
    for (var i = 0; i < visibleMarks.length; i++) {
      final mark = visibleMarks[i];
      final x = xFor(mark.time).clamp(plot.left, plot.right).toDouble();
      _drawDashedLine(
        canvas,
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = _mint.withValues(alpha: 0.34)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      final y = _yFor(mark.progress.toDouble(), profileLane, 0, 100);
      canvas.drawCircle(Offset(x, y), 4.2, Paint()..color = _mint);
      canvas.drawCircle(
        Offset(x, y),
        7,
        Paint()
          ..color = _mint.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
      if (visibleMarks.length <= 4 || i == 0 || i == visibleMarks.length - 1) {
        final label = '${mark.progress}%';
        final labelX = (x + 5).clamp(plot.left, plot.right - 24).toDouble();
        _paintText(
          canvas,
          label,
          Offset(labelX, profileLane.top + 3),
          color: _mint,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          maxWidth: 36,
        );
      }
    }
  }

  void _drawLaneSeries({
    required Canvas canvas,
    required List<CalibrationTimelinePoint> points,
    required _CalibrationLane lane,
    required Rect rect,
    required double Function(DateTime time) xFor,
  }) {
    final latest = _latestValue(points, lane);
    final path = Path();
    var drawing = false;
    var sampleCount = 0;

    for (final point in points) {
      final value = lane.valueFor(point);
      if (value == null || !value.isFinite || value <= 0) {
        drawing = false;
        continue;
      }
      sampleCount++;
      final x = xFor(point.time);
      final y = _yFor(value, rect, lane.min, lane.max);
      if (!drawing) {
        path.moveTo(x, y);
        drawing = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (sampleCount < 2) {
      _paintText(
        canvas,
        'No clean samples yet',
        Offset(rect.left + 10, rect.center.dy - 8),
        color: _muted,
        fontSize: 11,
        maxWidth: rect.width - 20,
      );
      return;
    }

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    canvas.drawPath(
      path,
      Paint()
        ..color = lane.color.withValues(alpha: 0.94)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();

    if (latest != null) {
      final latestY = _yFor(latest, rect, lane.min, lane.max);
      final latestLabel = lane.format(latest);
      final chipWidth = math.max(34.0, latestLabel.length * 7.0 + 16);
      final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.right - chipWidth - 6,
          (latestY - 12).clamp(rect.top + 3, rect.bottom - 25).toDouble(),
          chipWidth,
          22,
        ),
        const Radius.circular(11),
      );
      canvas.drawRRect(
        chip,
        Paint()..color = lane.color.withValues(alpha: 0.18),
      );
      canvas.drawRRect(
        chip,
        Paint()
          ..color = lane.color.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      _paintText(
        canvas,
        latestLabel,
        Offset(chip.outerRect.left + 8, chip.outerRect.top + 4),
        color: _text,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        maxWidth: chipWidth - 12,
      );
    }
  }

  double? _latestValue(
    List<CalibrationTimelinePoint> points,
    _CalibrationLane lane,
  ) {
    for (final point in points.reversed) {
      final value = lane.valueFor(point);
      if (value != null && value.isFinite && value > 0) {
        return value;
      }
    }
    return null;
  }

  double _yFor(double value, Rect rect, double min, double max) {
    final span = math.max(1.0, max - min);
    final normalized = ((value - min) / span).clamp(0.0, 1.0);
    return rect.bottom - normalized * rect.height;
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 6.0;
    const gap = 6.0;
    final total = (end - start).distance;
    if (total <= 0) {
      return;
    }
    final direction = (end - start) / total;
    var distance = 0.0;
    while (distance < total) {
      final next = math.min(distance + dash, total);
      canvas.drawLine(
        start + direction * distance,
        start + direction * next,
        paint,
      );
      distance += dash + gap;
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w600,
    double? maxWidth,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.05,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    textPainter.layout(maxWidth: maxWidth ?? double.infinity);
    textPainter.paint(canvas, offset);
  }

  void _paintCenteredLabel(Canvas canvas, Size size, String label) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: _muted, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  void _paintAxisLabel(
    Canvas canvas,
    Size size,
    DateTime time,
    Alignment alignment,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: _clock(time),
        style: const TextStyle(color: _muted, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width / 2);
    final x = alignment == Alignment.bottomLeft
        ? 0.0
        : size.width - textPainter.width;
    textPainter.paint(canvas, Offset(x, size.height - textPainter.height));
  }

  void _paintRangeLabel(
    Canvas canvas,
    Size size,
    DateTime first,
    DateTime last,
  ) {
    final span = last.difference(first);
    final label = span.inHours >= 1
        ? '${span.inHours}h ${span.inMinutes.remainder(60)}m window'
        : '${math.max(1, span.inMinutes)}m window';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: _muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width / 2);
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, size.height - 13),
    );
  }

  @override
  bool shouldRepaint(covariant _CalibrationTimelinePainter oldDelegate) {
    return oldDelegate.timeline != timeline;
  }
}

class _CalibrationLane {
  const _CalibrationLane({
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.color,
    required this.valueFor,
    required this.format,
  });

  final String label;
  final String unit;
  final double min;
  final double max;
  final Color color;
  final double? Function(CalibrationTimelinePoint point) valueFor;
  final String Function(double value) format;
}

class _CalibrationPlotLegend extends StatelessWidget {
  const _CalibrationPlotLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CalibrationChip(
          icon: Icons.favorite_rounded,
          label: 'HR',
          color: _red,
        ),
        _CalibrationChip(
          icon: Icons.opacity_rounded,
          label: 'SpO2',
          color: _amber,
        ),
        _CalibrationChip(
          icon: Icons.monitor_heart_rounded,
          label: 'HRV',
          color: _blue,
        ),
        _CalibrationChip(
          icon: Icons.update_rounded,
          label: 'Calibration update',
          color: _mint,
        ),
      ],
    );
  }
}

class _CalibrationLegend extends StatelessWidget {
  const _CalibrationLegend({
    required this.opticalProgress,
    required this.hrvProgress,
  });

  final int? opticalProgress;
  final int? hrvProgress;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _CalibrationChip(
          icon: Icons.timer_rounded,
          label: opticalProgress == null
              ? 'Waiting for live stream'
              : '2 min warmup, then 6h optical learning',
          color: _mint,
        ),
        _CalibrationChip(
          icon: Icons.update_rounded,
          label: opticalProgress == null
              ? 'No optical profile yet'
              : '${_percent(opticalProgress)} optical profile',
          color: _amber,
        ),
        _CalibrationChip(
          icon: Icons.timeline_rounded,
          label: '${_percent(hrvProgress)} HRV baseline',
          color: _blue,
        ),
      ],
    );
  }
}

class _CalibrationChip extends StatelessWidget {
  const _CalibrationChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.max(120.0, MediaQuery.sizeOf(context).width - 64);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = _line;
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 2,
      math.pi * 2,
      false,
      paint,
    );
    paint.color = color;
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.value,
    required this.color,
    required this.label,
    required this.trailing,
  });

  final double value;
  final Color color;
  final String label;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: _muted)),
            ),
            Text(trailing, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: value.clamp(0.0, 1.0),
            backgroundColor: _surface2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.items});

  final List<_StripItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final item in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48) / 2,
            child: item,
          ),
      ],
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _blue),
            const SizedBox(height: 18),
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: _muted)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${value.round()} $suffix',
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PpgPlot extends StatelessWidget {
  const _PpgPlot({
    required this.samples,
    this.emptyLabel = 'Waiting for PPG FIFO samples',
  });

  final List<int> samples;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePlotPainter(
        values: samples,
        color: samples.isNotEmpty ? _red : _mint,
        emptyLabel: samples.isNotEmpty ? '' : emptyLabel,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePlot extends StatelessWidget {
  const _LinePlot({
    required this.values,
    required this.color,
    required this.emptyLabel,
  });

  final List<int> values;
  final Color color;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePlotPainter(
        values: values,
        color: color,
        emptyLabel: emptyLabel,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LinePlotPainter extends CustomPainter {
  const _LinePlotPainter({
    required this.values,
    required this.color,
    required this.emptyLabel,
  });

  final List<int> values;
  final Color color;
  final String emptyLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _line
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: emptyLabel,
          style: const TextStyle(color: _muted, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final minValue = values.reduce(math.min).toDouble();
    final maxValue = values.reduce(math.max).toDouble();
    final span = math.max(1.0, maxValue - minValue);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalized = (values[i] - minValue) / span;
      final y = size.height - (normalized * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePlotPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.emptyLabel != emptyLabel;
  }
}

class _HexBox extends StatelessWidget {
  const _HexBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          color: _muted,
          fontFamily: 'Helvetica',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: const _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.12;
    final rect = Offset.zero & size;
    void arc(Color color, double start, double sweep) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect.deflate(stroke * 1.15), start, sweep, false, paint);
    }

    arc(_navy, math.pi * 0.92, math.pi * 0.8);
    arc(_blush, math.pi * 1.82, math.pi * 0.62);
    arc(_red, math.pi * 0.35, math.pi * 0.82);

    void dot(Color color, double angle) {
      final radius = size.shortestSide / 2 - stroke * 1.15;
      final center = Offset(size.width / 2, size.height / 2);
      final dotCenter = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(dotCenter, stroke * 0.62, Paint()..color = color);
    }

    dot(_navy, math.pi * 1.72);
    dot(_blush, math.pi * 0.42);
    dot(_red, math.pi * 0.98);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _clock(DateTime date) {
  return OpenPulseTime.clock(date);
}

String _dayLabel(DateTime date) {
  return OpenPulseTime.dayLabel(date);
}

String _timeAgo(DateTime date) {
  final diff = OpenPulseTime.now().difference(date);
  if (diff.isNegative) {
    return 'clock sync pending';
  }
  if (diff.inSeconds < 60) {
    return '${diff.inSeconds}s ago';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  return _clock(date);
}

int _snapStepGoal(double value) {
  return (value / 500).round() * 500;
}

double _normalizedPercent(int? value) {
  return ((value ?? 0) / 100).clamp(0.0, 1.0).toDouble();
}

String _percent(int? value) {
  return '${(value ?? 0).clamp(0, 100)}%';
}

String _nextCalibrationLabel(CalibrationTimeline? timeline) {
  if (timeline == null || !timeline.hasData) {
    return 'Next update in -- min';
  }
  final now = DateTime.now();
  final latestPointAt = timeline.latestPointAt;
  if (latestPointAt != null) {
    final sampleAge = now.difference(latestPointAt);
    if (sampleAge > const Duration(minutes: 3)) {
      return 'Last sample ${_durationLabel(sampleAge)} ago';
    }
    if (sampleAge < const Duration(minutes: -2)) {
      return 'Waiting for fresh board time';
    }
  }
  final progress = timeline.latestProgress;
  if (progress != null && progress >= 100) {
    return 'Profile ready';
  }
  if (progress != null && progress >= 30) {
    return 'Learning continuously';
  }
  final nextUpdateAt = timeline.nextUpdateAt;
  final remaining = nextUpdateAt == null
      ? timeline.nextUpdateRemaining
      : nextUpdateAt.isBefore(now)
      ? Duration.zero
      : nextUpdateAt.difference(now);
  if (remaining == null) {
    return 'Next update in -- min';
  }
  if (remaining > const Duration(minutes: 65)) {
    return 'Next update after fresh sync';
  }
  final minutes = (remaining.inSeconds / 60).ceil().clamp(0, 999);
  if (minutes <= 0) {
    return 'Next update now';
  }
  return 'Next update in $minutes min';
}

String _durationLabel(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  if (safe.inMinutes < 1) {
    return '${safe.inSeconds}s';
  }
  if (safe.inHours < 1) {
    return '${safe.inMinutes}m';
  }
  final hours = safe.inHours;
  final minutes = safe.inMinutes % 60;
  if (minutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${minutes}m';
}

String _calibrationShortLabel(int? value) {
  if (value == null || value <= 0) {
    return 'waiting';
  }
  if (value < 30) {
    return 'warmup';
  }
  if (value < 100) {
    return 'optical learning';
  }
  return 'profile ready';
}

String _calibrationPhase(int? value) {
  if (value == null || value <= 0) {
    return 'Connect and start live data to begin optical calibration.';
  }
  if (value < 30) {
    return 'Initial optical warmup is learning the signal baseline.';
  }
  if (value < 100) {
    return 'Hourly calibration is refining spike rejection and red/IR baselines.';
  }
  return 'Optical profile is fully calibrated for the current hardware path.';
}

String _hexPreview(String? hex) {
  if (hex == null || hex.isEmpty) {
    return 'Waiting for live packet bytes';
  }
  if (hex.length <= 220) {
    return hex;
  }
  return '${hex.substring(0, 220)}...';
}
