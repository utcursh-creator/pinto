import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/location_service.dart';
import 'package:pitch_app/src/features/discover/presentation/location_screen.dart';

class _FakeLoc implements LocationService {
  @override
  Future<({double lat, double lng})> current() async =>
      (lat: 12.34, lng: 56.78);
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Use my current location fills the fields on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [locationServiceProvider.overrideWithValue(_FakeLoc())],
            child: const MaterialApp(home: LocationScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Use my current location'), findsOneWidget);

        await tester.tap(find.text('Use my current location'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('12.34000'), findsOneWidget);
        expect(find.text('56.78000'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
