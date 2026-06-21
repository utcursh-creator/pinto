import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes screenshots captured by the integration test to /tmp/pitch_shots so
/// they can be inspected without controlling the desktop.
Future<void> main() async {
  final dir = Directory('/tmp/pitch_shots');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      File('/tmp/pitch_shots/$name.png').writeAsBytesSync(bytes);
      return true;
    },
  );
}
