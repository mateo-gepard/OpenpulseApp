import 'package:flutter_test/flutter_test.dart';

import 'package:openpulse_dashboard/main.dart';

void main() {
  testWidgets('research dashboard renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenPulseDashboardApp());

    expect(find.text('OpenPulse'), findsOneWidget);
    expect(find.text('Asthma Lab Console'), findsOneWidget);
    expect(find.text('Live data'), findsOneWidget);
    expect(find.text('Mock cohort'), findsWidgets);
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
}
