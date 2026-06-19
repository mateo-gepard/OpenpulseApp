import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ble/openpulse_controller.dart';
import '../models/openpulse_models.dart';

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
    final steps = live?.stepCount ?? summary?.maxSteps;
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
              footer: live?.hrConfidenceLabel ?? 'warming up',
              progress: ((live?.hrConfidence ?? 0) / 100).clamp(0.0, 1.0),
              color: _red,
            ),
            _MetricRing(
              label: 'SpO2',
              value: live?.spo2Percent == null ? '--' : '${live!.spo2Percent}',
              footer: live?.spo2ConfidenceLabel ?? 'experimental',
              progress: ((live?.spo2Confidence ?? 0) / 100).clamp(0.0, 1.0),
              color: _amber,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _CalibrationPanel(live: live, hrv: hrv, compact: true),
        const SizedBox(height: 18),
        _MetricStrip(
          items: [
            _StripItem(
              icon: Icons.favorite_rounded,
              label: 'HR',
              value: live?.heartRateBpm == null
                  ? 'Not computed'
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
                  ? 'Experimental warmup'
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
                              ? 'Streaming single-channel green PPG at 128 Hz.'
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
              value: live?.hrConfidenceLabel ?? 'Warming up',
            ),
            _StripItem(
              icon: Icons.water_drop_rounded,
              label: 'SpO2 certainty',
              value: live?.spo2ConfidenceLabel ?? 'Experimental',
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
        _CalibrationPanel(live: live, hrv: hrv, compact: false),
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
                    ? 'Waiting'
                    : '${live!.heartRateBpm!.toStringAsFixed(1)} bpm (${live.hrConfidenceLabel})',
              ),
              _FactRow(
                'IBI',
                live?.ibiMs == null ? 'Waiting' : '${live!.ibiMs} ms',
              ),
              _FactRow(
                'SpO2',
                live?.spo2Percent == null
                    ? 'Waiting'
                    : '${live!.spo2Percent}% (${live.spo2ConfidenceLabel})',
              ),
              _FactRow(
                'HRV',
                hrv?.available == true
                    ? 'RMSSD ${hrv!.rmssdMs!.toStringAsFixed(0)} ms, SDNN ${hrv.sdnnMs!.toStringAsFixed(0)} ms (${hrv.confidence}%)'
                    : hrv?.status ?? 'Needs clean IBI',
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
              _FactRow('Max steps', summary?.maxSteps?.toString() ?? '--'),
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
              const SizedBox(height: 16),
              Text(
                'After a connection gap, the app stores new live records and requests backfill. Backfill is still a gap marker until firmware history storage is added.',
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
                  controller.latestLiveRecord?.hrConfidenceLabel ??
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
                  controller.latestLiveRecord?.spo2ConfidenceLabel ??
                  'Experimental',
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
                  label: const Text('Backfill'),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          height: 72,
          backgroundColor: const Color(0xee1b252a),
          indicatorColor: _surface2,
          destinations: [
            for (final tab in tabs)
              NavigationDestination(icon: Icon(tab.$1), label: tab.$2),
          ],
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

class _CalibrationPanel extends StatelessWidget {
  const _CalibrationPanel({
    required this.live,
    required this.hrv,
    required this.compact,
  });

  final LiveRecord? live;
  final HrvSummary? hrv;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final opticalProgress = _normalizedPercent(live?.calibrationProgress);
    final hrProgress = _normalizedPercent(live?.hrConfidence);
    final spo2Progress = _normalizedPercent(live?.spo2Confidence);
    final hrvProgress = _normalizedPercent(hrv?.calibrationProgress);
    final opticalPercent = _percent(live?.calibrationProgress);
    final hrvPercent = _percent(hrv?.calibrationProgress);

    return _Surface(
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
                    Text(
                      'Calibration',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _calibrationPhase(live?.calibrationProgress),
                      style: const TextStyle(color: _muted, height: 1.25),
                    ),
                  ],
                ),
              ),
              Text(
                opticalPercent,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ProgressLine(
            value: opticalProgress,
            color: _mint,
            label: 'Optical profile',
            trailing:
                '$opticalPercent · ${_calibrationShortLabel(live?.calibrationProgress)}',
          ),
          const SizedBox(height: 12),
          _ProgressLine(
            value: hrProgress,
            color: _red,
            label: 'HR confidence',
            trailing: live?.hrConfidenceLabel ?? 'waiting',
          ),
          const SizedBox(height: 12),
          _ProgressLine(
            value: spo2Progress,
            color: _amber,
            label: 'SpO2 confidence',
            trailing: live?.spo2ConfidenceLabel ?? 'waiting',
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            _ProgressLine(
              value: hrvProgress,
              color: _blue,
              label: 'HRV baseline',
              trailing: '$hrvPercent · ${hrv?.status ?? 'needs IBI'}',
            ),
            const SizedBox(height: 14),
            _CalibrationLegend(
              opticalProgress: live?.calibrationProgress,
              hrvProgress: hrv?.calibrationProgress,
            ),
          ],
        ],
      ),
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
              : '2 min warmup, then hourly learning',
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
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _dayLabel(DateTime date) {
  final today = DateTime.now();
  final normalized = DateTime(date.year, date.month, date.day);
  final normalizedToday = DateTime(today.year, today.month, today.day);
  if (normalized == normalizedToday) {
    return 'TODAY';
  }
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) {
    return '${diff.inSeconds}s ago';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  return _clock(date);
}

double _normalizedPercent(int? value) {
  return ((value ?? 0) / 100).clamp(0.0, 1.0).toDouble();
}

String _percent(int? value) {
  return '${(value ?? 0).clamp(0, 100)}%';
}

String _calibrationShortLabel(int? value) {
  if (value == null || value <= 0) {
    return 'waiting';
  }
  if (value < 30) {
    return 'warmup';
  }
  if (value < 100) {
    return 'hourly learning';
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
