import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/theme/app_theme.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/presentation/start_match_screen.dart';

List<Map<String, dynamic>> _teamRow(String id, String name) => [
      {
        'teams': {'id': id, 'name': name}
      },
    ];

List<Map<String, dynamic>> _many(int n) => [
      for (var i = 0; i < n; i++)
        {
          'id': 'b$i',
          'name': 'Dadar CC $i',
          'city': 'Mumbai',
          'logo_url': null,
          'last_played': '2026-07-01T00:00:00Z',
        },
    ];

Future<void> _pump(WidgetTester tester, List<Map<String, dynamic>> ops) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myTeamsProvider.overrideWith((ref) async => _teamRow('a', 'My XI')),
        opponentSearchProvider((query: '', excludeTeamId: null))
            .overrideWith((ref) async => ops),
        opponentSearchProvider((query: '', excludeTeamId: 'a'))
            .overrideWith((ref) async => ops),
      ],
      child: MaterialApp(
        theme: AppTheme.material(),
        home: const StartMatchScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _case(String label, double w, double h, double kb, int rows) {
  testWidgets('$label ${w.toInt()}x${h.toInt()} kb=${kb.toInt()} rows=$rows',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = Size(w * 3, h * 3);
      tester.view.viewInsets = FakeViewPadding(bottom: kb * 3);
      addTearDown(tester.view.reset);

      await _pump(tester, _many(rows));
      await tester.tap(find.text('Choose the opponent'));
      await tester.pumpAndSettle();
      final ex = tester.takeException();
      debugPrint('RESULT $label ${w.toInt()}x${h.toInt()} kb=${kb.toInt()} '
          'rows=$rows -> ${ex == null ? 'NO OVERFLOW' : ex.toString().split('\n').first}');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  // iPhone SE 2/3 & iPhone 8 class
  _case('iPhoneSE', 375, 667, 216, 12); // iOS keyboard, no QuickType bar
  _case('iPhoneSE', 375, 667, 260, 12); // iOS keyboard with QuickType bar
  _case('iPhoneSE', 375, 667, 260, 0); // empty-state, same rigid 320 box
  _case('iPhoneSE', 375, 667, 207, 12); // exactly at the computed threshold
  _case('iPhoneSE', 375, 667, 208, 12);
  _case('iPhoneSE', 375, 667, 0, 12); // no keyboard at all
  // Common Android phone (e.g. Pixel 4a / most budget devices are ~360x640-800)
  _case('android360x640', 360, 640, 270, 12);
  _case('android360x800', 360, 800, 270, 12);
  // The device the fix run verified on
  _case('iPhone17', 393, 852, 336, 12);
}
