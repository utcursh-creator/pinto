import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/platform/adaptive_scaffold.dart';

/// Regression: Material widgets (TextField, ListTile, Chip, ...) must work
/// inside AdaptiveScaffold on BOTH platforms. On iOS the scaffold uses
/// CupertinoPageScaffold, which provides no Material ancestor, so the body
/// must be wrapped in a Material - else "No Material widget found" crashes
/// every form/list screen (sign-in, edit profile, composer, ...).
void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('AdaptiveScaffold hosts Material widgets on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveScaffold(
            title: 'Test',
            body: Column(
              children: [TextField(), ListTile(title: Text('row'))],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      if (platform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
