import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/core/auth/profile_provider.dart';
import 'package:pitch_app/src/core/prefs/scorer_prefs.dart';
import 'package:pitch_app/src/features/profile/presentation/settings_screen.dart';

/// Journey map C1 (ceiling): the preference has to be REACHABLE, not merely
/// respected. A flag the console honours but nobody can find is the same as no
/// flag at all - the scorer is still stuck with whatever we chose for him.
Widget _screen(List<Map<String, dynamic>> writes,
        {Map<String, dynamic>? prefs}) =>
    ProviderScope(
      overrides: [
        currentSessionProvider.overrideWithValue(null),
        myProfileProvider.overrideWith((ref) async =>
            {'display_name': 'Rahul', 'preferences': prefs ?? const {}}),
        prefsWriterProvider.overrideWithValue((patch) async {
          writes.add(patch);
        }),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the scoring preferences are on the settings screen, off by '
        'default, on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(_screen([]));
        await tester.pumpAndSettle();

        final capture = find.widgetWithText(
            SwitchListTile, 'Ask where the ball went');
        expect(capture, findsOneWidget,
            reason: 'a preference the console honours but nobody can reach is '
                'the same as no preference at all');
        expect(tester.widget<SwitchListTile>(capture).value, isFalse,
            reason: 'off for a scorer who never asked for it');

        final dots =
            find.widgetWithText(SwitchListTile, 'Also ask on dot balls');
        expect(tester.widget<SwitchListTile>(dots).onChanged, isNull,
            reason: 'dot plotting is nested under capture - asking about dots '
                'is meaningless when you are not being asked about anything, '
                'and CricHQ nests it the same way');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('turning capture on sends ONLY that key on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final writes = <Map<String, dynamic>>[];
        await tester.pumpWidget(_screen(writes));
        await tester.pumpAndSettle();

        await tester.tap(
            find.widgetWithText(SwitchListTile, 'Ask where the ball went'));
        await tester.pumpAndSettle();

        expect(writes, hasLength(1));
        expect(writes.single, {'wagon_capture': true},
            reason: 'send only what changed - set_preferences merges, so a '
                'client that knows one flag must never post a whole object and '
                'switch off a flag it has never heard of');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('with capture ON the dot toggle becomes usable on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final writes = <Map<String, dynamic>>[];
        await tester.pumpWidget(
            _screen(writes, prefs: const {'wagon_capture': true}));
        await tester.pumpAndSettle();

        final dots =
            find.widgetWithText(SwitchListTile, 'Also ask on dot balls');
        expect(tester.widget<SwitchListTile>(dots).onChanged, isNotNull);
        await tester.tap(dots);
        await tester.pumpAndSettle();
        expect(writes.single, {'wagon_dot_balls': true});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
