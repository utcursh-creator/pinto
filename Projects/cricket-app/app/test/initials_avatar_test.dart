import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/identity/presentation/initials_avatar.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('shows initials when there is no photo on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: InitialsAvatar(name: 'Rohit Sharma')),
        ));
        await tester.pump();
        expect(find.text('RS'), findsOneWidget);
        final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(avatar.foregroundImage, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('uses the network photo when present on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: InitialsAvatar(
              name: 'Rohit Sharma',
              photoUrl: 'https://cdn.example.com/a.jpg',
            ),
          ),
        ));
        await tester.pump();
        final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(avatar.foregroundImage, isA<NetworkImage>());
        // initials are not drawn when a photo is shown
        expect(find.text('RS'), findsNothing);
        // flutter_test's HTTP mock returns 400 for NetworkImage; that load error
        // is expected here - consume it so it doesn't fail the test.
        final ex = tester.takeException();
        expect(ex, anyOf(isNull, isA<NetworkImageLoadException>()));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
