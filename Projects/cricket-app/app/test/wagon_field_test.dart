import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/presentation/wagon_field.dart';

void main() {
  test('zoneFor returns 1-8 and straight-down is zone 1', () {
    expect(WagonField.zoneFor(0.5, 0.8), 1); // directly below the batter
    for (final p in const [
      [0.1, 0.1],
      [0.9, 0.9],
      [0.2, 0.7],
      [0.8, 0.3],
      [0.5, 0.0],
    ]) {
      final z = WagonField.zoneFor(p[0], p[1]);
      expect(z, inInclusiveRange(1, 8));
    }
  });

  testWidgets('capture mode reports a tapped shot', (tester) async {
    double? gotX, gotY;
    int? gotZone;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: WagonField(
                onTap: (x, y, zone) {
                  gotX = x;
                  gotY = y;
                  gotZone = zone;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(WagonField)));
    await tester.pumpAndSettle();
    expect(gotX, isNotNull);
    expect(gotY, isNotNull);
    expect(gotX, inInclusiveRange(0.0, 1.0));
    expect(gotZone, inInclusiveRange(1, 8));
  });

  testWidgets('display mode renders shots without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: WagonField(shots: [
                WagonShot(x: 0.7, y: 0.4, runs: 4),
                WagonShot(x: 0.3, y: 0.6, runs: 6),
                WagonShot(x: 0.5, y: 0.8, runs: 1),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(WagonField), findsOneWidget);
  });
}
