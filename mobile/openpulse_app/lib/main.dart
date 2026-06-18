import 'dart:async';

import 'package:flutter/material.dart';

import 'ble/openpulse_controller.dart';
import 'storage/openpulse_storage.dart';
import 'ui/openpulse_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = OpenPulseController(OpenPulseStorage());
  unawaited(controller.initialize());
  runApp(OpenPulseApp(controller: controller));
}
