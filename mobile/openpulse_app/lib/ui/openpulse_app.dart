import 'package:flutter/material.dart';

import '../ble/openpulse_controller.dart';
import '../models/openpulse_models.dart';

const _brand = Color(0xffd33e43);
const _ink = Color(0xff1c1f33);
const _muted = Color(0xff6d7280);
const _line = Color(0xffe4e7ee);
const _panel = Color(0xffffffff);
const _green = Color(0xff22a699);
const _yellow = Color(0xfff2b84b);

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
        fontFamily: 'Helvetica',
        scaffoldBackgroundColor: const Color(0xfff6f7fb),
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brand,
          primary: _brand,
          secondary: _green,
          surface: _panel,
        ),
        textTheme: Typography.blackCupertino.apply(
          fontFamily: 'Helvetica',
          bodyColor: _ink,
          displayColor: _ink,
        ),
        cardTheme: const CardThemeData(
          color: _panel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: _line),
          ),
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
    (Icons.speed_rounded, 'Home'),
    (Icons.favorite_rounded, 'Recovery'),
    (Icons.bedtime_rounded, 'Sleep'),
    (Icons.directions_run_rounded, 'Activity'),
    (Icons.watch_rounded, 'Device'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final pages = [
          HomePage(controller: controller),
          RecoveryPage(controller: controller),
          SleepPage(controller: controller),
          ActivityPage(controller: controller),
          DevicePage(controller: controller),
        ];

        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                final content = Column(
                  children: [
                    _TopBar(controller: controller, title: _tabs[_tab].$2),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: pages[_tab],
                      ),
                    ),
                  ],
                );

                if (!wide) {
                  return content;
                }

                return Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: (index) {
                        setState(() => _tab = index);
                      },
                      backgroundColor: Colors.transparent,
                      leading: const _BrandMark(),
                      destinations: [
                        for (final tab in _tabs)
                          NavigationRailDestination(
                            icon: Icon(tab.$1),
                            selectedIcon: Icon(tab.$1),
                            label: Text(tab.$2),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1, color: _line),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
          bottomNavigationBar: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 860) {
                return const SizedBox.shrink();
              }
              return NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (index) => setState(() => _tab = index),
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(icon: Icon(tab.$1), label: tab.$2),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.title});

  final OpenPulseController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    final live = controller.phase == ConnectionPhase.streaming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortDate(DateTime.now()),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: live ? controller.disconnect : controller.scanAndConnect,
            icon: Icon(live ? Icons.bluetooth_connected : Icons.bluetooth),
            label: Text(live ? 'Disconnect' : 'Scan'),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLiveRecord;
    final battery = controller.latestBattery;
    final puck = controller.latestPuckStatus;
    final raw = controller.latestRawPpgFrame;
    return _Grid(
      children: [
        _StatusCard(controller: controller),
        _Panel(
          title: 'Live stream',
          eyebrow: 'OpenPulse BLE',
          trailing: _Dot(live: controller.phase == ConnectionPhase.streaming),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricTile(
                label: 'HR',
                value: live?.heartRateBpm == null
                    ? 'Unavailable'
                    : live!.heartRateBpm!.toStringAsFixed(1),
                unit: live?.heartRateBpm == null ? '' : 'bpm',
              ),
              _MetricTile(
                label: 'IBI',
                value: live?.ibiMs?.toString() ?? 'Unavailable',
                unit: live?.ibiMs == null ? '' : 'ms',
              ),
              _MetricTile(
                label: 'SpO2',
                value: live?.spo2Percent?.toString() ?? 'Unavailable',
                unit: live?.spo2Percent == null ? '' : '%',
              ),
              _MetricTile(
                label: 'Quality',
                value: live?.qualityLabel ?? 'Unavailable',
                unit: '',
              ),
              _MetricTile(
                label: 'Raw PPG',
                value: raw == null
                    ? 'Unavailable'
                    : raw.payloadLength > 0
                    ? raw.payloadLength.toString()
                    : raw.sensorLabel,
                unit: raw != null && raw.payloadLength > 0 ? 'bytes' : '',
              ),
            ],
          ),
        ),
        _MetricCard(
          icon: Icons.battery_charging_full,
          title: 'Battery',
          value: battery?.display ?? 'Unavailable',
          footer: battery?.available == true ? 'Standard BLE Battery' : '',
          color: _yellow,
        ),
        _MetricCard(
          icon: Icons.memory_rounded,
          title: 'Puck',
          value: puck == null
              ? 'Unavailable'
              : puck.attached
              ? 'Attached'
              : puck.eventLabel,
          footer: puck?.sensorLabel ?? '',
          color: _brand,
        ),
        _MetricCard(
          icon: Icons.schedule_rounded,
          title: 'Last packet',
          value: live == null ? 'Unavailable' : _clock(live.receivedAt),
          footer: live == null ? '' : 'Stored locally',
          color: _green,
        ),
        _Panel(
          title: 'Device',
          eyebrow: controller.deviceName ?? 'No connected device',
          child: Row(
            children: [
              DeviceSilhouette(attached: puck?.attached == true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      puck?.puckLabel ?? 'Waiting for puck status',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.statusMessage,
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return const _UnavailablePage(
      icon: Icons.favorite_rounded,
      title: 'Recovery unavailable',
      body: 'Requires real overnight HR/IBI records and baseline history.',
    );
  }
}

class SleepPage extends StatelessWidget {
  const SleepPage({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return const _UnavailablePage(
      icon: Icons.bedtime_rounded,
      title: 'Sleep unavailable',
      body: 'Requires real overnight records from the wearable.',
    );
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return const _UnavailablePage(
      icon: Icons.directions_run_rounded,
      title: 'Activity unavailable',
      body: 'Requires real HR and motion records before strain is calculated.',
    );
  }
}

class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    final puck = controller.latestPuckStatus;
    return _Grid(
      children: [
        _Panel(
          title: controller.phase.label,
          eyebrow: controller.deviceName ?? 'OpenPulse device',
          trailing: IconButton(
            tooltip: 'Reconnect',
            onPressed: controller.scanAndConnect,
            icon: const Icon(Icons.refresh_rounded),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: DeviceSilhouette(attached: puck?.attached == true)),
              const SizedBox(height: 18),
              _FactRow('GATT', controller.gattReady ? 'Ready' : 'Unavailable'),
              _FactRow(
                'OpenPulse',
                controller.customServiceReady ? 'Ready' : 'Unavailable',
              ),
              _FactRow(
                'Battery',
                controller.batteryServiceReady ? 'Ready' : 'Unavailable',
              ),
              _FactRow(
                'Control notify',
                controller.controlNotifyReady ? 'Ready' : 'Unavailable',
              ),
              _FactRow(
                'Bulk backfill',
                controller.bulkBackfillReady ? 'Ready' : 'Unavailable',
              ),
              _FactRow(
                'Raw PPG',
                controller.rawPpgReady ? 'Ready' : 'Unavailable',
              ),
              _FactRow(
                'Puck',
                puck == null
                    ? 'Unavailable'
                    : '${puck.eventLabel} / ${puck.sensorLabel}',
              ),
            ],
          ),
        ),
        _Panel(
          title: 'Hardware',
          eyebrow: 'Device information',
          child: Column(
            children: [
              _FactRow(
                'Manufacturer',
                controller.deviceInformation.manufacturer ?? 'Unavailable',
              ),
              _FactRow(
                'Model',
                controller.deviceInformation.model ?? 'Unavailable',
              ),
              _FactRow(
                'Firmware',
                controller.deviceInformation.firmware ?? 'Unavailable',
              ),
              _FactRow(
                'Hardware',
                controller.deviceInformation.hardware ?? 'Unavailable',
              ),
            ],
          ),
        ),
        _Panel(
          title: 'Mode',
          eyebrow: 'Control characteristic',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in DeviceMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: controller.selectedMode == mode,
                  onSelected: controller.customServiceReady
                      ? (_) => controller.writeMode(mode)
                      : null,
                ),
            ],
          ),
        ),
        _Panel(
          title: 'PPG controls',
          eyebrow: 'Hardware writes',
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
            ],
          ),
        ),
        _Panel(
          title: 'Data',
          eyebrow: controller.storageReady
              ? 'SQLite local'
              : 'Storage unavailable',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniStatus(
                label: 'Control ACK',
                value: controller.latestControlAck == null
                    ? 'Unavailable'
                    : '${controller.latestControlAck!.commandLabel} / ${controller.latestControlAck!.statusLabel}',
              ),
              _MiniStatus(
                label: 'Backfill',
                value: controller.latestBackfillFrame == null
                    ? 'Unavailable'
                    : '${controller.latestBackfillFrame!.kindLabel} #${controller.latestBackfillFrame!.sequence}',
              ),
              _MiniStatus(
                label: 'Raw PPG',
                value: controller.latestRawPpgFrame == null
                    ? 'Unavailable'
                    : controller.latestRawPpgFrame!.payloadLength > 0
                    ? '${controller.latestRawPpgFrame!.payloadLength} bytes'
                    : controller.latestRawPpgFrame!.sensorLabel,
              ),
              OutlinedButton.icon(
                onPressed: controller.customServiceReady
                    ? controller.requestBackfill
                    : null,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Backfill'),
              ),
              OutlinedButton.icon(
                onPressed: controller.customServiceReady
                    ? controller.requestRawPpgWindow
                    : null,
                icon: const Icon(Icons.show_chart_rounded),
                label: const Text('Raw PPG'),
              ),
              OutlinedButton.icon(
                onPressed: controller.customServiceReady
                    ? controller.enterShipMode
                    : null,
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text('Ship mode'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final OpenPulseController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: controller.phase.label,
      eyebrow: 'Connection',
      trailing: _Dot(live: controller.phase == ConnectionPhase.streaming),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.statusMessage,
            style: const TextStyle(color: _muted, fontSize: 15),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: 'Storage', active: controller.storageReady),
              _StatusChip(label: 'GATT', active: controller.gattReady),
              _StatusChip(
                label: 'Custom BLE',
                active: controller.customServiceReady,
              ),
              _StatusChip(
                label: 'Battery',
                active: controller.batteryServiceReady,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      eyebrow: 'Real data only',
      child: Row(
        children: [
          Icon(icon, color: _muted, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              body,
              style: const TextStyle(color: _muted, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 980 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: columns == 1 ? 1.65 : 1.55,
          children: children,
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.eyebrow,
    required this.child,
    this.trailing,
  });

  final String title;
  final String eyebrow;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        eyebrow.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.footer,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String footer;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      eyebrow: 'Current',
      trailing: Icon(icon, color: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            footer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xfff2f4f8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit, style: const TextStyle(color: _muted)),
                  ),
                ],
              ],
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
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
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff2f4f8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
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
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${value.round()} $suffix'),
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
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 18,
        color: active ? _green : _muted,
      ),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class DeviceSilhouette extends StatelessWidget {
  const DeviceSilhouette({super.key, required this.attached});

  final bool attached;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 42,
              height: 44,
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 42,
              height: 44,
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Container(
            width: 72,
            height: 86,
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  color: _ink.withValues(alpha: 0.16),
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: attached ? 34 : 18,
                height: attached ? 34 : 18,
                decoration: BoxDecoration(
                  color: attached ? _brand : _muted,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: live ? _green : _muted,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      margin: const EdgeInsets.only(bottom: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'OP',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

String _shortDate(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}

String _clock(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
