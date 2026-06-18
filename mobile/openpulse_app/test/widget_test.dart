import 'package:flutter_test/flutter_test.dart';
import 'package:openpulse_app/ble/openpulse_controller.dart';
import 'package:openpulse_app/storage/openpulse_storage.dart';
import 'package:openpulse_app/ui/openpulse_app.dart';

void main() {
  testWidgets('OpenPulse shell renders without demo data', (tester) async {
    final controller = OpenPulseController(OpenPulseStorage());

    await tester.pumpWidget(OpenPulseApp(controller: controller));

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Waiting for OpenPulse'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('Flutter Demo Home Page'), findsNothing);
  });
}
