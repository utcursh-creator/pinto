import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_share_card.dart';

void main() {
  testWidgets('share card renders teams, score and brand', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MatchShareCard(
              title: 'Mumbai United v Dadar CC',
              battingTeam: 'Mumbai United',
              score: '45/2',
              line: 'Over 6.2  -  CRR 7.10',
              status: 'LIVE',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Mumbai United v Dadar CC'), findsOneWidget);
    expect(find.text('45/2'), findsOneWidget);
    expect(find.text('Pitch'), findsOneWidget);
  });
}
