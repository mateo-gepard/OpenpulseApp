import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class OpenPulseNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool ready = false;
  bool permissionGranted = false;

  Future<void> initialize() async {
    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
        defaultPresentAlert: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
        defaultPresentSound: true,
      ),
    );

    await _plugin.initialize(settings: settings);
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    permissionGranted =
        await ios?.requestPermissions(alert: true, sound: true) ?? false;
    ready = true;
  }

  Future<void> connectionDropped() {
    return _show(
      id: 1001,
      title: 'OpenPulse disconnected',
      body: 'The live hardware link dropped. Reconnecting now.',
    );
  }

  Future<void> stepGoalReached({required int steps, required int goal}) {
    return _show(
      id: 1002,
      title: 'Step goal reached',
      body: '$steps steps counted from the OpenPulse IMU. Goal: $goal.',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!ready || !permissionGranted) {
      return;
    }

    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
