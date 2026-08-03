import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/presentation/match_share_card.dart';

ScorecardInningsData inn(int bat, int bowl) => ScorecardInningsData(
      teamName: 'Mumbai United Cricket Club',
      total: '187/9',
      over: '20.0',
      batting: [
        for (var i = 0; i < bat; i++)
          ['Player Number $i', '45', '31', '4', '2'],
      ],
      bowling: [
        for (var i = 0; i < bowl; i++)
          ['Bowler Number $i', '4.0', '0', '38', '2'],
      ],
    );

Future<void> probe(WidgetTester t, String label, List<ScorecardInningsData> data) async {
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: key,
          child: FullScorecardCard(
            title: 'Mumbai United v Andheri Sporting',
            resultLine: 'Mumbai United won by 8 runs.',
            innings: data,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: 3);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  // ignore: avoid_print
  print('PROBE $label: logical=${b.size} pixels=${img.width}x${img.height} '
      'png=${bytes == null ? "NULL" : "${bytes.lengthInBytes} bytes"}');
}

void main() {
  testWidgets('typical T20 two innings', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    await probe(t, 'T20 11+7 x2', [inn(11, 7), inn(11, 7)]);
  });

  testWidgets('fat squads', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    await probe(t, 'fat 16+16 x2', [inn(16, 16), inn(16, 16)]);
  });

  testWidgets('four innings super-over-ish', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    await probe(t, '4 innings 11+7', [inn(11, 7), inn(11, 7), inn(11, 7), inn(11, 7)]);
  });
}
