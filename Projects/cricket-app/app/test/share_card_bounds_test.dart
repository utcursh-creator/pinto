import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_share_card.dart';

/// A review agent left a `zz_probe_card_size_test.dart` behind that rendered the
/// share card at pixelRatio 3 and PRINTED its size. It asserted nothing, could
/// not fail meaningfully, and added ~30 minutes to every `flutter test` run - and
/// I swept it into a commit with `git add -A` without noticing.
///
/// The question it was circling is real though: the full scorecard card is built
/// from whatever the innings contain, so a fat squad makes it taller, and if it
/// ever overflows its constraints the shared image is corrupt. This answers that
/// with an assertion instead of a printout, and without rasterising anything.
ScorecardInningsData _innings(int batters, int bowlers) => ScorecardInningsData(
      teamName: 'Mumbai United Cricket Club',
      total: '187/9',
      over: '20.0',
      batting: [
        for (var i = 0; i < batters; i++)
          ['Player Number $i', '45', '31', '4', '2'],
      ],
      bowling: [
        for (var i = 0; i < bowlers; i++)
          ['Bowler Number $i', '4.0', '0', '38', '2'],
      ],
    );

Future<void> _pump(WidgetTester tester, List<ScorecardInningsData> innings) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: FullScorecardCard(
          title: 'Mumbai United v Andheri Sporting',
          resultLine: 'Mumbai United won by 8 runs.',
          innings: innings,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a normal two-innings scorecard lays out cleanly', (tester) async {
    await _pump(tester, [_innings(11, 7), _innings(11, 7)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an oversized squad still lays out cleanly', (tester) async {
    // 16 a side is beyond a legal XI, but nothing stops a scorer naming a big
    // squad, and the card must not overflow when they do.
    await _pump(tester, [_innings(16, 16), _innings(16, 16)]);
    expect(tester.takeException(), isNull,
        reason: 'the share card must not overflow on a fat squad - the image it '
            'produces is what gets sent to a group chat');
  });

  testWidgets('a super-over style four-innings card lays out cleanly',
      (tester) async {
    await _pump(tester, [
      _innings(11, 7),
      _innings(11, 7),
      _innings(2, 1),
      _innings(2, 1),
    ]);
    expect(tester.takeException(), isNull);
  });
}
