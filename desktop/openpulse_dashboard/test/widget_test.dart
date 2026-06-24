import 'package:flutter_test/flutter_test.dart';

import 'package:openpulse_dashboard/main.dart';

void main() {
  testWidgets('research dashboard renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenPulseDashboardApp());

    expect(find.text('OpenPulse'), findsOneWidget);
    expect(find.text('Respiratory Lab Console'), findsOneWidget);
    expect(find.text('Live data'), findsOneWidget);
    expect(find.text('50 participant cohort'), findsOneWidget);
  });

  testWidgets('live tab exposes real BLE controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OpenPulseDashboardApp());
    await tester.tap(find.text('Live data'));
    await tester.pump();

    expect(find.text('Hardware connection'), findsOneWidget);
    expect(find.text('Real BLE'), findsWidgets);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Start raw'), findsOneWidget);
  });

  testWidgets('study analysis tabs render cleanly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OpenPulseDashboardApp());

    await tester.tap(find.text('Correlations'));
    await tester.pump();
    expect(find.text('Pearson correlation grid'), findsOneWidget);

    await tester.tap(find.text('Environment'));
    await tester.pump();
    expect(find.text('24h exposure profile'), findsOneWidget);

    await tester.tap(find.text('Cohort'));
    await tester.pump();
    expect(find.text('Participant table'), findsOneWidget);
  });
}
