import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const OpenPulseDashboardApp());
}

class OpenPulseDashboardApp extends StatelessWidget {
  const OpenPulseDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenPulse Research Dashboard',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Helvetica',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.blueInk,
          secondary: AppColors.coral,
          surface: AppColors.surface,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blueInk,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.blueInk,
            side: const BorderSide(color: AppColors.lineStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const DashboardShell(),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late final OpenPulseBleController ble;
  final cohort = buildAsthmaCohort();
  DashboardTab selectedTab = DashboardTab.overview;

  @override
  void initState() {
    super.initState();
    ble = OpenPulseBleController();
  }

  @override
  void dispose() {
    ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ble,
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(1360.0, constraints.maxWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Row(
                    children: [
                      _SideNav(
                        selected: selectedTab,
                        onSelected: (tab) => setState(() => selectedTab = tab),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            _TopBar(ble: ble, cohort: cohort),
                            Expanded(
                              child: _DashboardBody(
                                selectedTab: selectedTab,
                                cohort: cohort,
                                ble: ble,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.selectedTab,
    required this.cohort,
    required this.ble,
  });

  final DashboardTab selectedTab;
  final List<StudySubject> cohort;
  final OpenPulseBleController ble;

  @override
  Widget build(BuildContext context) {
    switch (selectedTab) {
      case DashboardTab.overview:
        return OverviewTab(cohort: cohort);
      case DashboardTab.cohort:
        return CohortTab(cohort: cohort);
      case DashboardTab.correlations:
        return CorrelationsTab(cohort: cohort);
      case DashboardTab.environment:
        return EnvironmentTab(cohort: cohort);
      case DashboardTab.live:
        return LiveDataTab(ble: ble);
    }
  }
}

enum DashboardTab {
  overview(Icons.dashboard_rounded, 'Overview'),
  cohort(Icons.groups_rounded, 'Cohort'),
  correlations(Icons.insights_rounded, 'Correlations'),
  environment(Icons.air_rounded, 'Environment'),
  live(Icons.sensors_rounded, 'Live data');

  const DashboardTab(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.selected, required this.onSelected});

  final DashboardTab selected;
  final ValueChanged<DashboardTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const OpenPulseMark(size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'OpenPulse',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Respiratory Lab Console',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              for (final tab in DashboardTab.values)
                _NavItem(
                  tab: tab,
                  selected: selected == tab,
                  onTap: () => onSelected(tab),
                ),
              const Spacer(),
              const _StudyBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final DashboardTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.lineStrong : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                tab.icon,
                size: 21,
                color: selected ? AppColors.mint : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.text : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyBadge extends StatelessWidget {
  const _StudyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'ASTHMA-OP-50',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5),
          ),
          SizedBox(height: 8),
          Text(
            '50 participant cohort',
            style: TextStyle(color: AppColors.muted),
          ),
          SizedBox(height: 12),
          _TinyProgress(value: .68, color: AppColors.amber),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.ble, required this.cohort});

  final OpenPulseBleController ble;
  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final highRisk = cohort.where((subject) => subject.exacerbationRisk > .66);
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'University respiratory exposure dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '50 participants · HR, skin temperature, and air-quality correlation study',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          _TopPill(
            icon: Icons.warning_amber_rounded,
            label: 'Risk flags',
            value: highRisk.length.toString(),
            color: AppColors.amber,
          ),
          const SizedBox(width: 10),
          _TopPill(
            icon: Icons.bluetooth_rounded,
            label: ble.phase.label,
            value: ble.connectedName ?? 'No device',
            color: ble.phase == BlePhase.streaming
                ? AppColors.mint
                : AppColors.coral,
          ),
        ],
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final avgHr = cohort.average((subject) => subject.heartRate);
    final avgTemp = cohort.average((subject) => subject.bodyTemperatureC);
    final avgPm25 = cohort.average((subject) => subject.pm25);
    final hrAir = pearson(
      cohort.map((subject) => subject.heartRate),
      cohort.map((subject) => subject.pm25),
    );
    final tempAir = pearson(
      cohort.map((subject) => subject.bodyTemperatureC),
      cohort.map((subject) => subject.pm25),
    );
    final risk = cohort.average((subject) => subject.exacerbationRisk);

    return DashboardScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MetricPanel(
                  title: 'Mean heart rate',
                  value: '${avgHr.toStringAsFixed(0)} bpm',
                  subtitle: 'Cohort median window',
                  icon: Icons.favorite_rounded,
                  color: AppColors.coral,
                  sparkValues: cohort.map((subject) => subject.heartRate),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricPanel(
                  title: 'Skin temperature',
                  value: '${avgTemp.toStringAsFixed(1)} degC',
                  subtitle: 'Wearable thermal proxy',
                  icon: Icons.thermostat_rounded,
                  color: AppColors.amber,
                  sparkValues: cohort.map(
                    (subject) => subject.bodyTemperatureC,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricPanel(
                  title: 'PM2.5 exposure',
                  value: '${avgPm25.toStringAsFixed(1)} ug/m3',
                  subtitle: 'Indoor/outdoor blend',
                  icon: Icons.air_rounded,
                  color: AppColors.blue,
                  sparkValues: cohort.map((subject) => subject.pm25),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricPanel(
                  title: 'Composite risk',
                  value: '${(risk * 100).round()}%',
                  subtitle: 'Asthma signal score',
                  icon: Icons.health_and_safety_rounded,
                  color: AppColors.mint,
                  sparkValues: cohort.map(
                    (subject) => subject.exacerbationRisk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: SurfacePanel(
                  title: 'Exposure correlation overview',
                  child: SizedBox(
                    height: 330,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ScatterPlot(
                            subjects: cohort,
                            x: (subject) => subject.pm25,
                            y: (subject) => subject.heartRate,
                            xLabel: 'PM2.5',
                            yLabel: 'HR',
                            color: AppColors.coral,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Expanded(
                                child: RingMetric(
                                  label: 'HR vs PM2.5',
                                  value: hrAir.abs().clamp(0, 1),
                                  display: hrAir.toStringAsFixed(2),
                                  color: AppColors.coral,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: RingMetric(
                                  label: 'Temp vs PM2.5',
                                  value: tempAir.abs().clamp(0, 1),
                                  display: tempAir.toStringAsFixed(2),
                                  color: AppColors.amber,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 4,
                child: SurfacePanel(
                  title: 'Signal matrix',
                  child: SizedBox(
                    height: 330,
                    child: CorrelationMatrix(cohort: cohort),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SurfacePanel(
                  title: 'Risk bands',
                  child: RiskBandChart(cohort: cohort),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: SurfacePanel(
                  title: 'Site exposure load',
                  child: SiteLoadChart(cohort: cohort),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CohortTab extends StatelessWidget {
  const CohortTab({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final sorted = [...cohort]
      ..sort((a, b) => b.exacerbationRisk.compareTo(a.exacerbationRisk));
    return DashboardScroll(
      child: SurfacePanel(
        title: 'Participant table',
        child: Column(
          children: [
            const _CohortHeaderRow(),
            const Divider(color: AppColors.line, height: 18),
            for (final subject in sorted) _SubjectRow(subject: subject),
          ],
        ),
      ),
    );
  }
}

class _CohortHeaderRow extends StatelessWidget {
  const _CohortHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _TableHead(width: 92, label: 'Subject'),
          _TableHead(width: 108, label: 'Group'),
          _TableHead(width: 92, label: 'HR'),
          _TableHead(width: 110, label: 'Temp'),
          _TableHead(width: 110, label: 'PM2.5'),
          _TableHead(width: 92, label: 'NO2'),
          _TableHead(width: 92, label: 'VOC'),
          Expanded(child: _TableHead(label: 'Asthma risk')),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject});

  final StudySubject subject;

  @override
  Widget build(BuildContext context) {
    final riskColor = subject.exacerbationRisk > .66
        ? AppColors.coral
        : subject.exacerbationRisk > .42
        ? AppColors.amber
        : AppColors.mint;
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _TableCell(width: 92, value: subject.id),
          _TableCell(width: 108, value: subject.group),
          _TableCell(width: 92, value: '${subject.heartRate.round()}'),
          _TableCell(
            width: 110,
            value: subject.bodyTemperatureC.toStringAsFixed(1),
          ),
          _TableCell(width: 110, value: subject.pm25.toStringAsFixed(1)),
          _TableCell(width: 92, value: subject.no2.toStringAsFixed(0)),
          _TableCell(width: 92, value: subject.vocIndex.toStringAsFixed(0)),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 9,
                      value: subject.exacerbationRisk,
                      backgroundColor: AppColors.track,
                      color: riskColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(subject.exacerbationRisk * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({this.width, required this.label});

  final double? width;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
    return width == null ? text : SizedBox(width: width, child: text);
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell({this.width, required this.value});

  final double? width;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return width == null ? text : SizedBox(width: width, child: text);
  }
}

class CorrelationsTab extends StatelessWidget {
  const CorrelationsTab({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    return DashboardScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CorrelationCard(
                  title: 'PM2.5 and heart rate',
                  xLabel: 'PM2.5 ug/m3',
                  yLabel: 'Heart rate bpm',
                  subjects: cohort,
                  x: (subject) => subject.pm25,
                  y: (subject) => subject.heartRate,
                  color: AppColors.coral,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _CorrelationCard(
                  title: 'PM2.5 and skin temperature',
                  xLabel: 'PM2.5 ug/m3',
                  yLabel: 'Skin temp degC',
                  subjects: cohort,
                  x: (subject) => subject.pm25,
                  y: (subject) => subject.bodyTemperatureC,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _CorrelationCard(
                  title: 'NO2 and symptom score',
                  xLabel: 'NO2 ppb',
                  yLabel: 'Symptom score',
                  subjects: cohort,
                  x: (subject) => subject.no2,
                  y: (subject) => subject.symptomScore,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: SurfacePanel(
                  title: 'Pearson correlation grid',
                  child: SizedBox(
                    height: 345,
                    child: CorrelationMatrix(cohort: cohort),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CorrelationCard extends StatelessWidget {
  const _CorrelationCard({
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.subjects,
    required this.x,
    required this.y,
    required this.color,
  });

  final String title;
  final String xLabel;
  final String yLabel;
  final List<StudySubject> subjects;
  final double Function(StudySubject subject) x;
  final double Function(StudySubject subject) y;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = pearson(subjects.map(x), subjects.map(y));
    return SurfacePanel(
      title: title,
      trailing: _CorrelationBadge(value: r),
      child: SizedBox(
        height: 345,
        child: ScatterPlot(
          subjects: subjects,
          x: x,
          y: y,
          xLabel: xLabel,
          yLabel: yLabel,
          color: color,
        ),
      ),
    );
  }
}

class EnvironmentTab extends StatelessWidget {
  const EnvironmentTab({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final hourly = buildHourlyExposure();
    return DashboardScroll(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SurfacePanel(
                  title: '24h exposure profile',
                  child: SizedBox(
                    height: 340,
                    child: MultiLineChart(
                      series: [
                        ChartSeries(
                          label: 'PM2.5',
                          color: AppColors.blue,
                          values: hourly.map((point) => point.pm25).toList(),
                        ),
                        ChartSeries(
                          label: 'NO2',
                          color: AppColors.amber,
                          values: hourly.map((point) => point.no2).toList(),
                        ),
                        ChartSeries(
                          label: 'VOC',
                          color: AppColors.coral,
                          values: hourly.map((point) => point.voc / 8).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: SurfacePanel(
                  title: 'Micro-site distribution',
                  child: SizedBox(
                    height: 340,
                    child: SiteLoadChart(cohort: cohort),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricPanel(
                  title: 'Peak PM2.5',
                  value:
                      '${hourly.map((e) => e.pm25).reduce(math.max).toStringAsFixed(1)} ug/m3',
                  subtitle: '24h high exposure',
                  icon: Icons.filter_drama_rounded,
                  color: AppColors.blue,
                  sparkValues: hourly.map((point) => point.pm25),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricPanel(
                  title: 'Humidity',
                  value:
                      '${hourly.map((e) => e.humidity).averageValue().toStringAsFixed(0)}%',
                  subtitle: 'Respiratory context',
                  icon: Icons.water_drop_rounded,
                  color: AppColors.mint,
                  sparkValues: hourly.map((point) => point.humidity),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MetricPanel(
                  title: 'VOC index',
                  value: hourly
                      .map((e) => e.voc)
                      .averageValue()
                      .toStringAsFixed(0),
                  subtitle: 'Indoor source estimate',
                  icon: Icons.science_rounded,
                  color: AppColors.coral,
                  sparkValues: hourly.map((point) => point.voc),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LiveDataTab extends StatelessWidget {
  const LiveDataTab({super.key, required this.ble});

  final OpenPulseBleController ble;

  @override
  Widget build(BuildContext context) {
    final live = ble.latestLiveRecord;
    return DashboardScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: _DeviceConnectionPanel(ble: ble)),
              const SizedBox(width: 18),
              Expanded(
                flex: 6,
                child: SurfacePanel(
                  title: 'OpenPulse live frame',
                  trailing: _HardwareBadge(),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: LiveMetricTile(
                              label: 'Heart rate',
                              value: live?.heartRateBpm == null
                                  ? '--'
                                  : '${live!.heartRateBpm!.toStringAsFixed(1)} bpm',
                              color: AppColors.coral,
                              icon: Icons.favorite_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LiveMetricTile(
                              label: 'SpO2',
                              value: live?.spo2Percent == null
                                  ? '--'
                                  : '${live!.spo2Percent}%',
                              color: AppColors.amber,
                              icon: Icons.bloodtype_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LiveMetricTile(
                              label: 'HRV RMSSD',
                              value: live?.hrvRmssdMs == null
                                  ? '--'
                                  : '${live!.hrvRmssdMs!.toStringAsFixed(0)} ms',
                              color: AppColors.blue,
                              icon: Icons.monitor_heart_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LiveMetricTile(
                              label: 'Battery',
                              value: ble.batteryLevel == null
                                  ? '--'
                                  : '${ble.batteryLevel}%',
                              color: AppColors.mint,
                              icon: Icons.battery_charging_full_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 210,
                        child: MultiLineChart(
                          series: [
                            ChartSeries(
                              label: 'HR',
                              color: AppColors.coral,
                              values: ble.recentLiveRecords
                                  .map((record) => record.heartRateBpm)
                                  .whereType<double>()
                                  .toList(),
                            ),
                            ChartSeries(
                              label: 'SpO2',
                              color: AppColors.amber,
                              values: ble.recentLiveRecords
                                  .map(
                                    (record) => record.spo2Percent?.toDouble(),
                                  )
                                  .whereType<double>()
                                  .toList(),
                            ),
                            ChartSeries(
                              label: 'Accel',
                              color: AppColors.mint,
                              values: ble.recentLiveRecords
                                  .map(
                                    (record) => record.accelMilliG?.toDouble(),
                                  )
                                  .whereType<double>()
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _LiveStatusStrip(ble: ble),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SurfacePanel(
            title: 'Raw optical stream',
            trailing: _HardwareBadge(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ble.rawStreaming
                            ? 'High-rate MAXM86161 FIFO stream active'
                            : 'Raw stream stopped',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: ble.phase == BlePhase.streaming
                          ? () => ble.setRawStreaming(!ble.rawStreaming)
                          : null,
                      icon: Icon(
                        ble.rawStreaming
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(ble.rawStreaming ? 'Stop raw' : 'Start raw'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: RawPpgChart(
                    green: ble.rawGreenSamples,
                    red: ble.rawRedSamples,
                    ir: ble.rawIrSamples,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SmallFact(
                      label: 'Raw packets',
                      value: ble.rawPacketCount.toString(),
                    ),
                    _SmallFact(
                      label: 'Payload bytes',
                      value:
                          ble.latestRawFrame?.payloadLength.toString() ?? '--',
                    ),
                    _SmallFact(
                      label: 'Sensor',
                      value: ble.latestRawFrame?.sensorStatusLabel ?? '--',
                    ),
                    _SmallFact(
                      label: 'Puck',
                      value: ble.latestRawFrame?.attached == null
                          ? '--'
                          : ble.latestRawFrame!.attached!
                          ? 'Attached'
                          : 'Missing',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceConnectionPanel extends StatelessWidget {
  const _DeviceConnectionPanel({required this.ble});

  final OpenPulseBleController ble;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      title: 'Hardware connection',
      trailing: _HardwareBadge(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: ble.phase == BlePhase.scanning ? null : ble.scan,
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  label: Text(
                    ble.phase == BlePhase.scanning ? 'Scanning' : 'Scan',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ble.connectedDevice == null
                      ? null
                      : ble.disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ConnectionLine(label: 'Phase', value: ble.phase.label),
          _ConnectionLine(label: 'Status', value: ble.status),
          _ConnectionLine(label: 'Device', value: ble.connectedName ?? '--'),
          _ConnectionLine(
            label: 'Firmware',
            value: ble.deviceInfo.firmware ?? '--',
          ),
          _ConnectionLine(label: 'Puck', value: ble.puckStatus?.label ?? '--'),
          const Divider(color: AppColors.line, height: 24),
          if (ble.discovered.isEmpty)
            const Text(
              'No OpenPulse devices discovered in this desktop session.',
              style: TextStyle(color: AppColors.muted),
            )
          else
            for (final device in ble.discovered)
              _DiscoveredDeviceRow(device: device, ble: ble),
        ],
      ),
    );
  }
}

class _DiscoveredDeviceRow extends StatelessWidget {
  const _DiscoveredDeviceRow({required this.device, required this.ble});

  final DiscoveredOpenPulse device;
  final OpenPulseBleController ble;

  @override
  Widget build(BuildContext context) {
    final connected =
        ble.connectedDevice?.remoteId.toString() == device.remoteId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: connected ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: connected
              ? AppColors.mint.withValues(alpha: .55)
              : AppColors.line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_rounded,
            color: connected ? AppColors.mint : AppColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.remoteIdTail} · RSSI ${device.rssi}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: connected ? 'Connected' : 'Connect',
            onPressed: connected ? null : () => ble.connect(device),
            icon: Icon(
              connected ? Icons.check_rounded : Icons.arrow_forward_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusStrip extends StatelessWidget {
  const _LiveStatusStrip({required this.ble});

  final OpenPulseBleController ble;

  @override
  Widget build(BuildContext context) {
    final record = ble.latestLiveRecord;
    return Row(
      children: [
        _SmallFact(
          label: 'Live packets',
          value: ble.livePacketCount.toString(),
        ),
        _SmallFact(
          label: 'Calibration',
          value: record?.calibrationProgress == null
              ? '--'
              : '${record!.calibrationProgress}%',
        ),
        _SmallFact(
          label: 'HR conf',
          value: record?.hrConfidence == null
              ? '--'
              : '${record!.hrConfidence}%',
        ),
        _SmallFact(
          label: 'Flags',
          value: record == null ? '--' : record.qualityLabel,
        ),
      ],
    );
  }
}

class LiveMetricTile extends StatelessWidget {
  const LiveMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SmallFact extends StatelessWidget {
  const _SmallFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScroll extends StatelessWidget {
  const DashboardScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class MetricPanel extends StatelessWidget {
  const MetricPanel({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.sparkValues,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Iterable<double> sparkValues;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const Spacer(),
              SizedBox(
                width: 88,
                height: 32,
                child: Sparkline(values: sparkValues.toList(), color: color),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HardwareBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _Badge(
      icon: Icons.sensors_rounded,
      label: 'Real BLE',
      color: AppColors.mint,
    );
  }
}

class _CorrelationBadge extends StatelessWidget {
  const _CorrelationBadge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.functions_rounded,
      label: 'r ${value.toStringAsFixed(2)}',
      color: value.abs() > .55 ? AppColors.coral : AppColors.blue,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class OpenPulseMark extends StatelessWidget {
  const OpenPulseMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OpenPulseMarkPainter(),
    );
  }
}

class _OpenPulseMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .115;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .36;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    paint.color = AppColors.blueInk;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.05,
      math.pi * .62,
      false,
      paint,
    );
    paint.color = AppColors.softRose;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 1.84,
      math.pi * .55,
      false,
      paint,
    );
    paint.color = AppColors.coral;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * .43,
      math.pi * .62,
      false,
      paint,
    );

    final dotPaint = Paint()..style = PaintingStyle.fill;
    dotPaint.color = AppColors.blueInk;
    canvas.drawCircle(
      Offset(center.dx + radius * .35, center.dy - radius * .93),
      stroke * .78,
      dotPaint,
    );
    dotPaint.color = AppColors.softRose;
    canvas.drawCircle(
      Offset(center.dx + radius * .9, center.dy + radius * .48),
      stroke * .78,
      dotPaint,
    );
    dotPaint.color = AppColors.coral;
    canvas.drawCircle(
      Offset(center.dx - radius * .85, center.dy + radius * .42),
      stroke * .78,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        series: [ChartSeries(label: '', color: color, values: values)],
        showLegend: false,
        showGrid: false,
      ),
    );
  }
}

class MultiLineChart extends StatelessWidget {
  const MultiLineChart({super.key, required this.series});

  final List<ChartSeries> series;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(painter: _LinePainter(series: series)),
    );
  }
}

class RawPpgChart extends StatelessWidget {
  const RawPpgChart({
    super.key,
    required this.green,
    required this.red,
    required this.ir,
  });

  final List<int> green;
  final List<int> red;
  final List<int> ir;

  @override
  Widget build(BuildContext context) {
    final series = [
      ChartSeries(
        label: 'Green',
        color: AppColors.mint,
        values: green.map((sample) => sample.toDouble()).toList(),
      ),
      ChartSeries(
        label: 'Red',
        color: AppColors.coral,
        values: red.map((sample) => sample.toDouble()).toList(),
      ),
      ChartSeries(
        label: 'IR',
        color: AppColors.amber,
        values: ir.map((sample) => sample.toDouble()).toList(),
      ),
    ];
    return SizedBox.expand(
      child: CustomPaint(painter: _LinePainter(series: series)),
    );
  }
}

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<double> values;
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    this.showLegend = true,
    this.showGrid = true,
  });

  final List<ChartSeries> series;
  final bool showLegend;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) {
      return;
    }
    final values = series.expand((entry) => entry.values).toList();
    final rect = Offset.zero & size;
    final bg = Paint()
      ..color = AppColors.surfaceRaised.withValues(alpha: .45)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      bg,
    );

    if (values.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }

    final left = showGrid ? 46.0 : 0.0;
    final top = showLegend ? 36.0 : 2.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - 18),
      math.max(1, size.height - top - 28),
    );
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final spread = math.max(1, maxValue - minValue);

    if (showGrid) {
      final gridPaint = Paint()
        ..color = AppColors.line
        ..strokeWidth = 1;
      for (var i = 0; i < 4; i++) {
        final y = chart.top + chart.height * (i / 3);
        canvas.drawLine(
          Offset(chart.left, y),
          Offset(chart.right, y),
          gridPaint,
        );
      }
    }

    if (showLegend) {
      var x = chart.left;
      for (final entry in series.where((entry) => entry.values.isNotEmpty)) {
        final dot = Paint()..color = entry.color;
        canvas.drawCircle(Offset(x + 6, 14), 4, dot);
        _drawText(
          canvas,
          entry.label,
          Offset(x + 16, 6),
          color: AppColors.muted,
          size: 12,
        );
        x += 86;
      }
    }

    for (final entry in series.where((entry) => entry.values.isNotEmpty)) {
      final points = entry.values;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x =
            chart.left +
            (points.length == 1 ? 0 : chart.width * i / (points.length - 1));
        final y =
            chart.bottom - ((points[i] - minValue) / spread) * chart.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final stroke = Paint()
        ..color = entry.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, stroke);

      final fillPath = Path.from(path)
        ..lineTo(chart.right, chart.bottom)
        ..lineTo(chart.left, chart.bottom)
        ..close();
      final fill = Paint()
        ..shader = LinearGradient(
          colors: [
            entry.color.withValues(alpha: .18),
            entry.color.withValues(alpha: 0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(chart)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fill);
    }
  }

  void _drawEmpty(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1.2;
    final y = size.height / 2;
    canvas.drawLine(Offset(28, y), Offset(size.width - 28, y), paint);
    _drawText(
      canvas,
      'Waiting for data',
      Offset(size.width / 2 - 54, y - 28),
      color: AppColors.muted,
      size: 13,
    );
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => true;
}

class ScatterPlot extends StatelessWidget {
  const ScatterPlot({
    super.key,
    required this.subjects,
    required this.x,
    required this.y,
    required this.xLabel,
    required this.yLabel,
    required this.color,
  });

  final List<StudySubject> subjects;
  final double Function(StudySubject subject) x;
  final double Function(StudySubject subject) y;
  final String xLabel;
  final String yLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _ScatterPainter(
          subjects: subjects,
          x: x,
          y: y,
          xLabel: xLabel,
          yLabel: yLabel,
          color: color,
        ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.subjects,
    required this.x,
    required this.y,
    required this.xLabel,
    required this.yLabel,
    required this.color,
  });

  final List<StudySubject> subjects;
  final double Function(StudySubject subject) x;
  final double Function(StudySubject subject) y;
  final String xLabel;
  final String yLabel;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 120 || size.height < 120) {
      return;
    }
    final plot = Rect.fromLTWH(58, 28, size.width - 84, size.height - 72);
    final xs = subjects.map(x).toList();
    final ys = subjects.map(y).toList();
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final spreadX = math.max(1, maxX - minX);
    final spreadY = math.max(1, maxY - minY);

    final gridPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final yGrid = plot.top + plot.height * i / 3;
      canvas.drawLine(
        Offset(plot.left, yGrid),
        Offset(plot.right, yGrid),
        gridPaint,
      );
      final xGrid = plot.left + plot.width * i / 3;
      canvas.drawLine(
        Offset(xGrid, plot.top),
        Offset(xGrid, plot.bottom),
        gridPaint,
      );
    }

    final pointPaint = Paint()..color = color.withValues(alpha: .76);
    for (final subject in subjects) {
      final px = plot.left + ((x(subject) - minX) / spreadX) * plot.width;
      final py = plot.bottom - ((y(subject) - minY) / spreadY) * plot.height;
      canvas.drawCircle(Offset(px, py), 4.2, pointPaint);
    }

    _drawText(
      canvas,
      yLabel,
      const Offset(10, 8),
      color: AppColors.muted,
      size: 12,
    );
    _drawText(
      canvas,
      xLabel,
      Offset(plot.right - 96, plot.bottom + 28),
      color: AppColors.muted,
      size: 12,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CorrelationMatrix extends StatelessWidget {
  const CorrelationMatrix({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(painter: _CorrelationMatrixPainter(cohort: cohort)),
    );
  }
}

class _CorrelationMatrixPainter extends CustomPainter {
  _CorrelationMatrixPainter({required this.cohort});

  final List<StudySubject> cohort;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 180 || size.height < 180) {
      return;
    }
    final labels = ['HR', 'Temp', 'PM2.5', 'NO2', 'VOC', 'Risk'];
    final fields = <double Function(StudySubject)>[
      (s) => s.heartRate,
      (s) => s.bodyTemperatureC,
      (s) => s.pm25,
      (s) => s.no2,
      (s) => s.vocIndex,
      (s) => s.exacerbationRisk,
    ];
    final top = 46.0;
    final left = 72.0;
    final cell = math.min(
      (size.width - left - 18) / labels.length,
      (size.height - top - 18) / labels.length,
    );

    for (var i = 0; i < labels.length; i++) {
      _drawCentered(
        canvas,
        labels[i],
        Offset(left + i * cell + cell / 2, 18),
        11,
        AppColors.muted,
      );
      _drawText(
        canvas,
        labels[i],
        Offset(6, top + i * cell + cell / 2 - 7),
        color: AppColors.muted,
        size: 11,
      );
    }

    for (var row = 0; row < labels.length; row++) {
      for (var col = 0; col < labels.length; col++) {
        final value = pearson(cohort.map(fields[row]), cohort.map(fields[col]));
        final strong = value.abs().clamp(0, 1).toDouble();
        final paint = Paint()
          ..color = value >= 0
              ? AppColors.mint.withValues(alpha: .16 + strong * .55)
              : AppColors.coral.withValues(alpha: .16 + strong * .55);
        final rect = Rect.fromLTWH(
          left + col * cell + 3,
          top + row * cell + 3,
          cell - 6,
          cell - 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          paint,
        );
        _drawCentered(
          canvas,
          value.toStringAsFixed(2),
          rect.center,
          cell >= 48 ? 11 : 9,
          AppColors.text,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RingMetric extends StatelessWidget {
  const RingMetric({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.color,
  });

  final String label;
  final double value;
  final String display;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _RingPainter(
          value: value,
          display: display,
          label: label,
          color: color,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.display,
    required this.label,
    required this.color,
  });

  final double value;
  final String display;
  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 4);
    final radius = math.min(size.width, size.height) * .31;
    final bg = Paint()
      ..color = AppColors.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      fg,
    );
    _drawCentered(
      canvas,
      display,
      Offset(center.dx, center.dy - 10),
      28,
      AppColors.text,
    );
    _drawCentered(
      canvas,
      label,
      Offset(center.dx, center.dy + 22),
      12,
      AppColors.muted,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RiskBandChart extends StatelessWidget {
  const RiskBandChart({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final low = cohort
        .where((subject) => subject.exacerbationRisk < .42)
        .length;
    final medium = cohort
        .where(
          (subject) =>
              subject.exacerbationRisk >= .42 && subject.exacerbationRisk < .66,
        )
        .length;
    final high = cohort
        .where((subject) => subject.exacerbationRisk >= .66)
        .length;
    return Column(
      children: [
        _BandRow(
          label: 'Low',
          value: low,
          total: cohort.length,
          color: AppColors.mint,
        ),
        _BandRow(
          label: 'Moderate',
          value: medium,
          total: cohort.length,
          color: AppColors.amber,
        ),
        _BandRow(
          label: 'High',
          value: high,
          total: cohort.length,
          color: AppColors.coral,
        ),
      ],
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 13,
                value: value / total,
                color: color,
                backgroundColor: AppColors.track,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 38,
            child: Text(
              value.toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class SiteLoadChart extends StatelessWidget {
  const SiteLoadChart({super.key, required this.cohort});

  final List<StudySubject> cohort;

  @override
  Widget build(BuildContext context) {
    final sites = <String, List<StudySubject>>{};
    for (final subject in cohort) {
      sites.putIfAbsent(subject.site, () => []).add(subject);
    }
    final maxValue = sites.values
        .map((items) => items.average((subject) => subject.pm25))
        .reduce(math.max);
    return Column(
      children: [
        for (final entry in sites.entries)
          _SiteRow(
            site: entry.key,
            value: entry.value.average((subject) => subject.pm25),
            maxValue: maxValue,
            count: entry.value.length,
          ),
      ],
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.site,
    required this.value,
    required this.maxValue,
    required this.count,
  });

  final String site;
  final double value;
  final double maxValue;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              site,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 14,
                value: value / maxValue,
                color: AppColors.blue,
                backgroundColor: AppColors.track,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              '${value.toStringAsFixed(1)} · n=$count',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyProgress extends StatelessWidget {
  const _TinyProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 8,
        value: value,
        color: color,
        backgroundColor: AppColors.track,
      ),
    );
  }
}

class OpenPulseBleController extends ChangeNotifier {
  final Map<String, DiscoveredOpenPulse> _discovered = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  BlePhase phase = BlePhase.disconnected;
  String status = 'Ready';
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _live;
  BluetoothCharacteristic? _raw;
  BluetoothCharacteristic? _puck;
  BluetoothCharacteristic? _battery;
  DeviceInfo deviceInfo = const DeviceInfo();
  PuckStatus? puckStatus;
  int? batteryLevel;
  int livePacketCount = 0;
  int rawPacketCount = 0;
  int _lastDeviceUptimeMs = 0;
  int _syncedUnixMs = 0;
  int _syncedDeviceUptimeMs = 0;
  bool rawStreaming = false;
  Timer? _rawPollTimer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  LiveRecord? latestLiveRecord;
  RawPpgFrame? latestRawFrame;
  List<LiveRecord> recentLiveRecords = const [];
  List<int> rawGreenSamples = const [];
  List<int> rawRedSamples = const [];
  List<int> rawIrSamples = const [];

  int samplingHz = 64;
  int ledGreenMa = 12;
  int ledRedMa = 8;
  int ledIrMa = 8;
  int? _savedSamplingHzBeforeRaw;
  int? _savedGreenBeforeRaw;
  int? _savedRedBeforeRaw;
  int? _savedIrBeforeRaw;

  List<DiscoveredOpenPulse> get discovered {
    final list = _discovered.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  String? get connectedName {
    final id = connectedDevice?.remoteId.toString();
    if (id == null) {
      return null;
    }
    return _discovered[id]?.name ?? connectedDevice?.platformName;
  }

  Future<void> scan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _discovered.clear();
    phase = BlePhase.scanning;
    status = 'Scanning for OpenPulse and OpenPulse Nova';
    notifyListeners();

    try {
      final adapter = await FlutterBluePlus.adapterState.first;
      if (adapter != BluetoothAdapterState.on) {
        phase = BlePhase.bluetoothUnavailable;
        status = 'Bluetooth adapter is ${adapter.name}';
        notifyListeners();
        return;
      }
      await FlutterBluePlus.stopScan();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        _handleScanResults,
      );
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 7));
      await Future<void>.delayed(const Duration(milliseconds: 7600));
      if (phase == BlePhase.scanning) {
        phase = BlePhase.disconnected;
        status = _discovered.isEmpty
            ? 'No OpenPulse advertisement found'
            : 'Select a discovered OpenPulse device';
        notifyListeners();
      }
    } catch (error) {
      phase = BlePhase.error;
      status = 'Scan failed: $error';
      notifyListeners();
    }
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      if (!OpenPulseBleContract.isOpenPulseResult(result)) {
        continue;
      }
      final remoteId = result.device.remoteId.toString();
      _discovered[remoteId] = DiscoveredOpenPulse(
        device: result.device,
        name: OpenPulseBleContract.deviceName(result),
        remoteId: remoteId,
        rssi: result.rssi,
        lastSeen: DateTime.now(),
      );
    }
    if (_discovered.isNotEmpty) {
      status = 'Found ${_discovered.length} OpenPulse device(s)';
      notifyListeners();
    }
  }

  Future<void> connect(DiscoveredOpenPulse target) async {
    await disconnect(silent: true);
    phase = BlePhase.connecting;
    status = 'Connecting to ${target.name}';
    connectedDevice = target.device;
    notifyListeners();

    try {
      await target.device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 12),
      );
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (!message.contains('already') && !message.contains('connected')) {
        phase = BlePhase.error;
        status = 'Connect failed: $error';
        notifyListeners();
        return;
      }
    }

    _subscriptions.add(
      target.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            phase != BlePhase.disconnected) {
          _handleUnexpectedDisconnect();
        }
      }),
    );

    try {
      await target.device.requestMtu(247);
    } catch (_) {
      // macOS may not expose MTU requests for every adapter.
    }

    phase = BlePhase.discovering;
    status = 'Discovering OpenPulse GATT';
    notifyListeners();

    try {
      final services = await target.device.discoverServices();
      await _discoverGatt(services);
      await _subscribeNotifications();
      await _readDeviceInformation(services);
      await _readInitialControlState();
      await _readInitialBattery();
      await _readInitialPuck();
      await _timeSync();
      await _writeControl(OpenPulseBleContract.buildSetMode(DeviceMode.active));
      phase = BlePhase.streaming;
      status = '${target.name} is streaming';
      notifyListeners();
    } catch (error) {
      phase = BlePhase.error;
      status = 'GATT setup failed: $error';
      notifyListeners();
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    await setRawStreaming(false);
    _rawPollTimer?.cancel();
    _rawPollTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await connectedDevice?.disconnect();
    } catch (_) {
      // Disconnect is best-effort on desktop BLE adapters.
    }
    connectedDevice = null;
    _control = null;
    _live = null;
    _raw = null;
    _puck = null;
    _battery = null;
    if (!silent) {
      phase = BlePhase.disconnected;
      status = 'Disconnected';
      notifyListeners();
    }
  }

  Future<void> setRawStreaming(bool enabled) async {
    if (enabled == rawStreaming) {
      return;
    }
    if (enabled && phase != BlePhase.streaming) {
      return;
    }
    rawStreaming = enabled;
    notifyListeners();

    if (enabled) {
      _savedSamplingHzBeforeRaw = samplingHz;
      _savedGreenBeforeRaw = ledGreenMa;
      _savedRedBeforeRaw = ledRedMa;
      _savedIrBeforeRaw = ledIrMa;
      rawGreenSamples = const [];
      rawRedSamples = const [];
      rawIrSamples = const [];
      latestRawFrame = null;
      rawPacketCount = 0;
      status = 'Starting raw optical stream';
      notifyListeners();
      try {
        await _writeSampling(128);
        await _writeLed(
          greenMa: math.max(16, ledGreenMa),
          redMa: math.max(8, ledRedMa),
          irMa: math.max(8, ledIrMa),
        );
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await _requestRawWindow(1);
        _rawPollTimer?.cancel();
        _rawPollTimer = Timer.periodic(
          const Duration(milliseconds: 250),
          (_) => unawaited(_requestRawWindow(1)),
        );
      } catch (error) {
        rawStreaming = false;
        status = 'Raw stream failed: $error';
        notifyListeners();
      }
    } else {
      _rawPollTimer?.cancel();
      _rawPollTimer = null;
      try {
        if (_control != null) {
          await _requestRawWindow(0);
          if (_savedSamplingHzBeforeRaw != null) {
            await _writeSampling(_savedSamplingHzBeforeRaw!);
          }
          if (_savedGreenBeforeRaw != null &&
              _savedRedBeforeRaw != null &&
              _savedIrBeforeRaw != null) {
            await _writeLed(
              greenMa: _savedGreenBeforeRaw!,
              redMa: _savedRedBeforeRaw!,
              irMa: _savedIrBeforeRaw!,
            );
          }
        }
      } catch (_) {
        // Raw mode is diagnostic; failure to restore should not hide live data.
      } finally {
        _savedSamplingHzBeforeRaw = null;
        _savedGreenBeforeRaw = null;
        _savedRedBeforeRaw = null;
        _savedIrBeforeRaw = null;
        status = phase == BlePhase.streaming
            ? 'Raw optical stream stopped'
            : status;
        notifyListeners();
      }
    }
  }

  Future<void> _discoverGatt(List<BluetoothService> services) async {
    _control = null;
    _live = null;
    _raw = null;
    _puck = null;
    _battery = null;

    for (final service in services) {
      if (OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.serviceUuid,
      )) {
        _control = _findCharacteristic(
          service,
          OpenPulseBleContract.controlUuid,
        );
        _live = _findCharacteristic(
          service,
          OpenPulseBleContract.liveStreamUuid,
        );
        _raw = _findCharacteristic(service, OpenPulseBleContract.rawPpgUuid);
        _puck = _findCharacteristic(
          service,
          OpenPulseBleContract.puckStatusUuid,
        );
      }
      if (OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.batteryService,
      )) {
        _battery = _findCharacteristic(
          service,
          OpenPulseBleContract.batteryLevelCharacteristic,
        );
      }
    }

    if (_control == null || _live == null || _puck == null) {
      throw StateError('OpenPulse custom service is incomplete');
    }
  }

  BluetoothCharacteristic? _findCharacteristic(
    BluetoothService service,
    Object uuid,
  ) {
    for (final characteristic in service.characteristics) {
      if (OpenPulseBleContract.uuidMatches(characteristic.uuid, uuid)) {
        return characteristic;
      }
    }
    return null;
  }

  Future<void> _subscribeNotifications() async {
    Future<void> subscribe(
      BluetoothCharacteristic? characteristic,
      void Function(List<int> bytes) onData,
    ) async {
      if (characteristic == null || !characteristic.properties.notify) {
        return;
      }
      _subscriptions.add(characteristic.onValueReceived.listen(onData));
      await characteristic.setNotifyValue(true);
    }

    await subscribe(_control, _handleControlAck);
    await subscribe(_battery, _handleBattery);
    await subscribe(_puck, _handlePuckStatus);
    await subscribe(_live, _handleLiveFrame);
    await subscribe(_raw, _handleRawPpgFrame);
  }

  Future<void> _readDeviceInformation(List<BluetoothService> services) async {
    String? manufacturer;
    String? model;
    String? firmware;
    String? hardware;

    for (final service in services) {
      if (!OpenPulseBleContract.uuidMatches(
        service.uuid,
        OpenPulseBleContract.deviceInformationService,
      )) {
        continue;
      }

      Future<String?> readText(Object uuid) async {
        final characteristic = _findCharacteristic(service, uuid);
        if (characteristic == null || !characteristic.properties.read) {
          return null;
        }
        final bytes = await characteristic.read();
        return utf8.decode(bytes, allowMalformed: true);
      }

      manufacturer = await readText(
        OpenPulseBleContract.manufacturerCharacteristic,
      );
      model = await readText(OpenPulseBleContract.modelCharacteristic);
      firmware = await readText(OpenPulseBleContract.firmwareCharacteristic);
      hardware = await readText(OpenPulseBleContract.hardwareCharacteristic);
    }

    deviceInfo = DeviceInfo(
      manufacturer: manufacturer,
      model: model,
      firmware: firmware,
      hardware: hardware,
    );
  }

  Future<void> _readInitialControlState() async {
    final control = _control;
    if (control == null || !control.properties.read) {
      return;
    }
    _lastDeviceUptimeMs = OpenPulseBleContract.parseControlDeviceUptime(
      await control.read(),
    );
  }

  Future<void> _readInitialBattery() async {
    final battery = _battery;
    if (battery == null || !battery.properties.read) {
      batteryLevel = null;
      return;
    }
    _handleBattery(await battery.read());
  }

  Future<void> _readInitialPuck() async {
    final puck = _puck;
    if (puck == null || !puck.properties.read) {
      return;
    }
    _handlePuckStatus(await puck.read());
  }

  Future<void> _timeSync() async {
    phase = BlePhase.timeSyncing;
    status = 'Writing desktop time to OpenPulse';
    notifyListeners();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _syncedUnixMs = nowMs;
    _syncedDeviceUptimeMs = _lastDeviceUptimeMs;
    await _writeControl(
      OpenPulseBleContract.buildTimeSync(
        unixMs: nowMs,
        deviceUptimeMsSeenByApp: _lastDeviceUptimeMs,
      ),
    );
  }

  Future<void> _writeSampling(int hz) async {
    samplingHz = hz;
    await _writeControl(OpenPulseBleContract.buildSetSampling(hz));
    notifyListeners();
  }

  Future<void> _writeLed({
    required int greenMa,
    required int redMa,
    required int irMa,
  }) async {
    ledGreenMa = greenMa;
    ledRedMa = redMa;
    ledIrMa = irMa;
    await _writeControl(
      OpenPulseBleContract.buildSetLedCurrent(
        greenMa: greenMa,
        redMa: redMa,
        irMa: irMa,
      ),
    );
    notifyListeners();
  }

  Future<void> _requestRawWindow(int seconds) async {
    await _writeControl(OpenPulseBleContract.buildRequestRawWindow(seconds));
  }

  Future<void> _writeControl(List<int> frame) async {
    final control = _control;
    if (control == null) {
      throw StateError('Control characteristic unavailable');
    }
    await control.write(frame, withoutResponse: false);
  }

  void _handleControlAck(List<int> bytes) {
    final ack = OpenPulseBleContract.parseControlAck(bytes);
    if (ack != null) {
      status =
          'Control ack 0x${ack.command.toRadixString(16)} status ${ack.status}';
      notifyListeners();
    }
  }

  void _handleBattery(List<int> bytes) {
    batteryLevel = OpenPulseBleContract.parseBattery(bytes);
    notifyListeners();
  }

  void _handlePuckStatus(List<int> bytes) {
    puckStatus = OpenPulseBleContract.parsePuckStatus(bytes);
    notifyListeners();
  }

  void _handleLiveFrame(List<int> bytes) {
    final parsed = OpenPulseBleContract.parseLiveFrame(
      bytes: bytes,
      previousDeviceUptimeMs: _lastDeviceUptimeMs,
      syncedUnixMs: _syncedUnixMs,
      syncedDeviceUptimeMs: _syncedDeviceUptimeMs,
      receivedAt: DateTime.now(),
    );
    if (parsed == null || parsed.records.isEmpty) {
      return;
    }
    livePacketCount++;
    _lastDeviceUptimeMs = parsed.lastDeviceUptimeMs;
    latestLiveRecord = parsed.records.last;
    recentLiveRecords = [
      ...recentLiveRecords,
      ...parsed.records,
    ].takeLast(180).toList(growable: false);
    notifyListeners();
  }

  void _handleRawPpgFrame(List<int> bytes) {
    final frame = OpenPulseBleContract.parseRawPpgFrame(bytes);
    if (frame == null) {
      return;
    }
    rawPacketCount++;
    latestRawFrame = frame;
    rawGreenSamples = [
      ...rawGreenSamples,
      ...frame.greenSamples,
    ].takeLast(620).toList(growable: false);
    rawRedSamples = [
      ...rawRedSamples,
      ...frame.redSamples,
    ].takeLast(620).toList(growable: false);
    rawIrSamples = [
      ...rawIrSamples,
      ...frame.irSamples,
    ].takeLast(620).toList(growable: false);
    notifyListeners();
  }

  void _handleUnexpectedDisconnect() {
    _rawPollTimer?.cancel();
    _rawPollTimer = null;
    rawStreaming = false;
    phase = BlePhase.disconnected;
    status = 'OpenPulse disconnected';
    connectedDevice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(disconnect(silent: true));
    super.dispose();
  }
}

enum BlePhase {
  disconnected('Disconnected'),
  scanning('Scanning'),
  connecting('Connecting'),
  discovering('Discovering'),
  timeSyncing('Time sync'),
  streaming('Live'),
  bluetoothUnavailable('Bluetooth unavailable'),
  error('Error');

  const BlePhase(this.label);

  final String label;
}

enum DeviceMode {
  standby(0),
  active(1),
  lowPower(2),
  hrOnly(3),
  shipMode(4);

  const DeviceMode(this.value);

  final int value;
}

class DiscoveredOpenPulse {
  const DiscoveredOpenPulse({
    required this.device,
    required this.name,
    required this.remoteId,
    required this.rssi,
    required this.lastSeen,
  });

  final BluetoothDevice device;
  final String name;
  final String remoteId;
  final int rssi;
  final DateTime lastSeen;

  String get remoteIdTail =>
      remoteId.length <= 8 ? remoteId : remoteId.substring(remoteId.length - 8);
}

class DeviceInfo {
  const DeviceInfo({
    this.manufacturer,
    this.model,
    this.firmware,
    this.hardware,
  });

  final String? manufacturer;
  final String? model;
  final String? firmware;
  final String? hardware;
}

class PuckStatus {
  const PuckStatus({
    required this.eventType,
    required this.puckKind,
    required this.attached,
    required this.sensorStatus,
  });

  final int eventType;
  final int puckKind;
  final bool attached;
  final int sensorStatus;

  String get label {
    if (!attached) {
      return 'Missing';
    }
    if (sensorStatus == 0) {
      return 'Attached';
    }
    return 'Attached, status $sensorStatus';
  }
}

class ControlAck {
  const ControlAck({
    required this.command,
    required this.status,
    required this.mode,
  });

  final int command;
  final int status;
  final int mode;
}

class LiveRecord {
  const LiveRecord({
    required this.receivedAt,
    required this.wallTime,
    required this.deviceUptimeMs,
    required this.sequence,
    required this.heartRateBpm,
    required this.ibiMs,
    required this.accelMilliG,
    required this.spo2Percent,
    required this.qualityFlags,
    required this.stepCount,
    required this.motionStatus,
    required this.hrConfidence,
    required this.spo2Confidence,
    required this.calibrationProgress,
    required this.hrvRmssdMs,
  });

  final DateTime receivedAt;
  final DateTime wallTime;
  final int deviceUptimeMs;
  final int sequence;
  final double? heartRateBpm;
  final int? ibiMs;
  final int? accelMilliG;
  final int? spo2Percent;
  final int qualityFlags;
  final int? stepCount;
  final int? motionStatus;
  final int? hrConfidence;
  final int? spo2Confidence;
  final int? calibrationProgress;
  final double? hrvRmssdMs;

  String get qualityLabel {
    final flags = <String>[];
    if (qualityFlags & 0x01 != 0) flags.add('skin');
    if (qualityFlags & 0x02 != 0) flags.add('motion');
    if (qualityFlags & 0x04 != 0) flags.add('low perfusion');
    if (qualityFlags & 0x20 != 0) flags.add('clipping');
    if (qualityFlags & 0x40 != 0) flags.add('calibrating');
    return flags.isEmpty ? 'clean' : flags.join(', ');
  }
}

class ParsedLiveFrame {
  const ParsedLiveFrame({
    required this.sequence,
    required this.records,
    required this.lastDeviceUptimeMs,
  });

  final int sequence;
  final List<LiveRecord> records;
  final int lastDeviceUptimeMs;
}

class RawPpgFrame {
  const RawPpgFrame({
    required this.sequence,
    required this.requestedSeconds,
    required this.attached,
    required this.sensorStatus,
    required this.payloadLength,
    required this.greenSamples,
    required this.redSamples,
    required this.irSamples,
  });

  final int sequence;
  final int? requestedSeconds;
  final bool? attached;
  final int? sensorStatus;
  final int payloadLength;
  final List<int> greenSamples;
  final List<int> redSamples;
  final List<int> irSamples;

  String get sensorStatusLabel {
    switch (sensorStatus) {
      case 0:
        return 'OK';
      case 1:
        return 'Unavailable';
      default:
        return sensorStatus?.toString() ?? '--';
    }
  }
}

class OpenPulseBleContract {
  static const advertisedName = 'OpenPulse';
  static const legacyLiveRecordLength = 12;
  static const activityLiveRecordLength = 17;
  static const metricsLiveRecordLength = 20;
  static const extendedLiveRecordLength = 26;

  static final serviceUuid = Guid('f04d0000-57f5-4f5a-9b80-4f6f2f1d0001');
  static final controlUuid = Guid('f04d0001-57f5-4f5a-9b80-4f6f2f1d0001');
  static final liveStreamUuid = Guid('f04d0002-57f5-4f5a-9b80-4f6f2f1d0001');
  static final rawPpgUuid = Guid('f04d0004-57f5-4f5a-9b80-4f6f2f1d0001');
  static final puckStatusUuid = Guid('f04d0005-57f5-4f5a-9b80-4f6f2f1d0001');

  static const deviceInformationService = '180a';
  static const batteryService = '180f';
  static const batteryLevelCharacteristic = '2a19';
  static const manufacturerCharacteristic = '2a29';
  static const modelCharacteristic = '2a24';
  static const firmwareCharacteristic = '2a26';
  static const hardwareCharacteristic = '2a27';

  static bool isOpenPulseName(String? name) {
    final trimmed = name?.trim();
    return trimmed != null &&
        trimmed.isNotEmpty &&
        (trimmed == advertisedName || trimmed.startsWith('$advertisedName '));
  }

  static bool isOpenPulseResult(ScanResult result) {
    return isOpenPulseName(result.advertisementData.advName) ||
        isOpenPulseName(result.device.advName) ||
        isOpenPulseName(result.device.platformName) ||
        result.advertisementData.serviceUuids.any(
          (uuid) => uuidMatches(uuid, serviceUuid),
        );
  }

  static String deviceName(ScanResult result) {
    final names = [
      result.advertisementData.advName,
      result.device.advName,
      result.device.platformName,
    ];
    for (final name in names) {
      if (name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return advertisedName;
  }

  static bool uuidMatches(Guid uuid, Object expected) {
    final actual = uuid.toString().toLowerCase();
    final value = expected is Guid
        ? expected.toString().toLowerCase()
        : expected.toString().toLowerCase();
    if (actual == value) {
      return true;
    }
    if (value.length == 4) {
      return actual == value ||
          actual == '0000$value-0000-1000-8000-00805f9b34fb';
    }
    return false;
  }

  static List<int> buildTimeSync({
    required int unixMs,
    required int deviceUptimeMsSeenByApp,
  }) {
    final data = ByteData(18);
    data.setUint8(0, 0x01);
    data.setUint8(1, 16);
    data.setUint64(2, unixMs, Endian.little);
    data.setUint64(10, deviceUptimeMsSeenByApp, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildSetMode(DeviceMode mode) => [0x02, 1, mode.value];

  static List<int> buildSetSampling(int hz) {
    final data = ByteData(4);
    data.setUint8(0, 0x03);
    data.setUint8(1, 2);
    data.setUint16(2, hz, Endian.little);
    return data.buffer.asUint8List();
  }

  static List<int> buildSetLedCurrent({
    required int greenMa,
    required int redMa,
    required int irMa,
  }) => [0x04, 3, greenMa & 0xff, redMa & 0xff, irMa & 0xff];

  static List<int> buildRequestRawWindow(int seconds) {
    final data = ByteData(4);
    data.setUint8(0, 0x06);
    data.setUint8(1, 2);
    data.setUint16(2, seconds, Endian.little);
    return data.buffer.asUint8List();
  }

  static int? parseBattery(List<int> bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    return bytes.first <= 100 ? bytes.first : null;
  }

  static int parseControlDeviceUptime(List<int> bytes) {
    if (bytes.length < 12) {
      return 0;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return data.getUint64(4, Endian.little);
  }

  static PuckStatus? parsePuckStatus(List<int> bytes) {
    if (bytes.length < 4) {
      return null;
    }
    return PuckStatus(
      eventType: bytes[0],
      puckKind: bytes[1],
      attached: bytes[2] == 1,
      sensorStatus: bytes[3],
    );
  }

  static ControlAck? parseControlAck(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 0x80) {
      return null;
    }
    return ControlAck(command: bytes[1], status: bytes[2], mode: bytes[3]);
  }

  static ParsedLiveFrame? parseLiveFrame({
    required List<int> bytes,
    required int previousDeviceUptimeMs,
    required int syncedUnixMs,
    required int syncedDeviceUptimeMs,
    required DateTime receivedAt,
  }) {
    if (bytes.length < 4 || bytes[0] != 0x10) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final count = data.getUint8(1);
    final sequence = data.getUint16(2, Endian.little);
    final availableRecordBytes = bytes.length - 4;
    final recordLength =
        count > 0 && availableRecordBytes >= count * extendedLiveRecordLength
        ? extendedLiveRecordLength
        : count > 0 && availableRecordBytes >= count * metricsLiveRecordLength
        ? metricsLiveRecordLength
        : count > 0 && availableRecordBytes >= count * activityLiveRecordLength
        ? activityLiveRecordLength
        : legacyLiveRecordLength;

    var offset = 4;
    var deviceUptime = previousDeviceUptimeMs;
    final records = <LiveRecord>[];
    for (var i = 0; i < count; i++) {
      if (offset + recordLength > bytes.length) {
        break;
      }
      final delta = data.getUint32(offset, Endian.little);
      final hrX10 = data.getUint16(offset + 4, Endian.little);
      final ibiMs = data.getUint16(offset + 6, Endian.little);
      final accel = data.getInt16(offset + 8, Endian.little);
      final spo2 = data.getUint8(offset + 10);
      final quality = data.getUint8(offset + 11);
      final stepCount = recordLength >= activityLiveRecordLength
          ? data.getUint32(offset + 12, Endian.little)
          : null;
      final motionStatus = recordLength >= activityLiveRecordLength
          ? data.getUint8(offset + 16)
          : null;
      final hrConfidence = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 17)
          : null;
      final spo2Confidence = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 18)
          : null;
      final calibrationProgress = recordLength >= metricsLiveRecordLength
          ? data.getUint8(offset + 19)
          : null;
      final absoluteUptime = recordLength >= extendedLiveRecordLength
          ? data.getUint32(offset + 20, Endian.little)
          : null;
      final hrvRmssd = recordLength >= extendedLiveRecordLength
          ? data.getUint16(offset + 24, Endian.little)
          : null;

      deviceUptime = absoluteUptime ?? (deviceUptime + delta);
      final wallTimeMs = syncedUnixMs + (deviceUptime - syncedDeviceUptimeMs);
      records.add(
        LiveRecord(
          receivedAt: receivedAt,
          wallTime: DateTime.fromMillisecondsSinceEpoch(wallTimeMs),
          deviceUptimeMs: deviceUptime,
          sequence: sequence,
          heartRateBpm: hrX10 == 0 ? null : hrX10 / 10.0,
          ibiMs: ibiMs == 0 ? null : ibiMs,
          accelMilliG: accel == 0 ? null : accel,
          spo2Percent: spo2 == 0xff ? null : spo2,
          qualityFlags: quality,
          stepCount: stepCount,
          motionStatus: motionStatus,
          hrConfidence: hrConfidence,
          spo2Confidence: spo2Confidence,
          calibrationProgress: calibrationProgress,
          hrvRmssdMs: hrvRmssd == null || hrvRmssd == 0
              ? null
              : hrvRmssd.toDouble(),
        ),
      );
      offset += recordLength;
    }

    return ParsedLiveFrame(
      sequence: sequence,
      records: records,
      lastDeviceUptimeMs: deviceUptime,
    );
  }

  static RawPpgFrame? parseRawPpgFrame(List<int> bytes) {
    if (bytes.length < 8 || bytes[0] != 0x30) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final declaredPayloadLength = bytes[7];
    final availablePayloadLength = bytes.length - 8;
    final payloadLength = math.min(
      declaredPayloadLength,
      availablePayloadLength,
    );
    final payload = bytes.skip(8).take(payloadLength).toList(growable: false);
    final channels = parseRawChannels(payload);
    return RawPpgFrame(
      sequence: data.getUint16(1, Endian.little),
      requestedSeconds: data.getUint16(3, Endian.little),
      attached: bytes[5] == 1,
      sensorStatus: bytes[6],
      payloadLength: payloadLength,
      greenSamples: channels.green,
      redSamples: channels.red,
      irSamples: channels.ir,
    );
  }

  static RawChannels parseRawChannels(List<int> payload) {
    final green = <int>[];
    final red = <int>[];
    final ir = <int>[];
    final legacy = <int>[];
    var sawTagged = false;
    for (var i = 0; i + 2 < payload.length; i += 3) {
      final tag = payload[i] >> 3;
      final value =
          ((payload[i] & 0x07) << 16) | (payload[i + 1] << 8) | payload[i + 2];
      switch (tag) {
        case 1:
          sawTagged = true;
          green.add(value);
          break;
        case 2:
          sawTagged = true;
          ir.add(value);
          break;
        case 3:
          sawTagged = true;
          red.add(value);
          break;
        default:
          legacy.add(value);
      }
    }
    return RawChannels(green: sawTagged ? green : legacy, red: red, ir: ir);
  }
}

class RawChannels {
  const RawChannels({required this.green, required this.red, required this.ir});

  final List<int> green;
  final List<int> red;
  final List<int> ir;
}

class StudySubject {
  const StudySubject({
    required this.id,
    required this.group,
    required this.site,
    required this.heartRate,
    required this.bodyTemperatureC,
    required this.pm25,
    required this.no2,
    required this.vocIndex,
    required this.humidity,
    required this.symptomScore,
    required this.exacerbationRisk,
  });

  final String id;
  final String group;
  final String site;
  final double heartRate;
  final double bodyTemperatureC;
  final double pm25;
  final double no2;
  final double vocIndex;
  final double humidity;
  final double symptomScore;
  final double exacerbationRisk;
}

class ExposureHour {
  const ExposureHour({
    required this.hour,
    required this.pm25,
    required this.no2,
    required this.voc,
    required this.humidity,
  });

  final int hour;
  final double pm25;
  final double no2;
  final double voc;
  final double humidity;
}

List<StudySubject> buildAsthmaCohort() {
  final random = math.Random(8042);
  const sites = ['Dorm A', 'Clinic', 'Transit', 'Home', 'Gym'];
  const groups = ['Control', 'Mild', 'Moderate', 'Severe'];
  return List.generate(50, (index) {
    final site = sites[index % sites.length];
    final group = groups[(index ~/ 13).clamp(0, groups.length - 1)];
    final exposureBase = switch (site) {
      'Transit' => 28.0,
      'Gym' => 18.0,
      'Dorm A' => 22.0,
      'Clinic' => 11.0,
      _ => 16.0,
    };
    final severity = groups.indexOf(group) / (groups.length - 1);
    final pm25 = exposureBase + random.nextDouble() * 13 + severity * 5;
    final no2 = 10 + exposureBase * .72 + random.nextDouble() * 12;
    final voc = 78 + pm25 * 2.6 + random.nextDouble() * 62;
    final temp =
        36.35 + severity * .28 + pm25 * .006 + random.nextDouble() * .34;
    final hr = 58 + severity * 11 + pm25 * .42 + random.nextDouble() * 12;
    final humidity = 38 + random.nextDouble() * 28;
    final symptoms = (severity * 4.5 + pm25 / 12 + random.nextDouble() * 2.5)
        .clamp(0, 10);
    final risk =
        ((symptoms / 10) * .55 +
                (pm25 / 60) * .24 +
                (hr - 55) / 90 * .18 +
                random.nextDouble() * .08)
            .clamp(0, 1)
            .toDouble();
    return StudySubject(
      id: 'P${(index + 1).toString().padLeft(3, '0')}',
      group: group,
      site: site,
      heartRate: hr,
      bodyTemperatureC: temp,
      pm25: pm25,
      no2: no2,
      vocIndex: voc,
      humidity: humidity,
      symptomScore: symptoms.toDouble(),
      exacerbationRisk: risk,
    );
  });
}

List<ExposureHour> buildHourlyExposure() {
  final random = math.Random(1701);
  return List.generate(24, (hour) {
    final commute = hour == 8 || hour == 17 ? 16 : 0;
    final night = hour < 6 ? 4 : 0;
    final pm25 =
        10 +
        commute +
        night +
        math.sin(hour / 24 * math.pi * 2) * 5 +
        random.nextDouble() * 5;
    return ExposureHour(
      hour: hour,
      pm25: pm25,
      no2: 12 + commute * .8 + random.nextDouble() * 9,
      voc: 90 + night * 10 + random.nextDouble() * 88,
      humidity: 42 + math.sin((hour - 4) / 24 * math.pi * 2) * 9,
    );
  });
}

double pearson(Iterable<double> xValues, Iterable<double> yValues) {
  final x = xValues.toList();
  final y = yValues.toList();
  if (x.length != y.length || x.length < 2) {
    return 0;
  }
  final meanX = x.averageValue();
  final meanY = y.averageValue();
  var numerator = 0.0;
  var denomX = 0.0;
  var denomY = 0.0;
  for (var i = 0; i < x.length; i++) {
    final dx = x[i] - meanX;
    final dy = y[i] - meanY;
    numerator += dx * dy;
    denomX += dx * dx;
    denomY += dy * dy;
  }
  final denom = math.sqrt(denomX * denomY);
  return denom == 0 ? 0 : numerator / denom;
}

extension IterableNumbers on Iterable<double> {
  double averageValue() {
    if (isEmpty) {
      return 0;
    }
    return reduce((a, b) => a + b) / length;
  }
}

extension SubjectListStats on List<StudySubject> {
  double average(double Function(StudySubject subject) selector) {
    if (isEmpty) {
      return 0;
    }
    return map(selector).reduce((a, b) => a + b) / length;
  }
}

extension TakeLastList<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) {
      return this;
    }
    return skip(length - count);
  }
}

void _drawText(
  Canvas canvas,
  String text,
  Offset offset, {
  required Color color,
  required double size,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: 'Helvetica',
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
}

void _drawCentered(
  Canvas canvas,
  String text,
  Offset center,
  double size,
  Color color,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: 'Helvetica',
        fontWeight: FontWeight.w900,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

class AppColors {
  static const background = Color(0xfff6f8fb);
  static const sidebar = Color(0xffffffff);
  static const surface = Color(0xffffffff);
  static const surfaceRaised = Color(0xffeef5f7);
  static const line = Color(0xffd8e2e7);
  static const lineStrong = Color(0xffb7c8d0);
  static const track = Color(0xffe4edf1);
  static const text = Color(0xff132126);
  static const muted = Color(0xff66757d);
  static const mint = Color(0xff16b89f);
  static const coral = Color(0xffef3746);
  static const amber = Color(0xffd99619);
  static const blue = Color(0xff2787c5);
  static const blueInk = Color(0xff091735);
  static const softRose = Color(0xffc58d83);
}
