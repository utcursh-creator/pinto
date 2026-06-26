import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/main.dart' as app;

/// Verifies the avatar upload + display path on the real app against live
/// Supabase: upload bytes to the `avatars` bucket (RLS: own folder), set
/// photo_url, and confirm the Profile header renders the photo. The native
/// image PICKER is the only manual-only step.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // a valid 1x1 PNG
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> settle(WidgetTester tester, Finder until, {int tries = 25}) async {
    for (var i = 0; i < tries; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      if (until.evaluate().isNotEmpty) return;
    }
  }

  testWidgets('avatar upload + display (real app)', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final c = Supabase.instance.client;
    if (c.auth.currentUser == null || (c.auth.currentUser?.isAnonymous ?? false)) {
      await c.auth.signInWithPassword(email: 'dev@pitch.local', password: 'password123');
    }
    final uid = c.auth.currentUser!.id;

    // Upload to the avatars bucket (RLS: own <uid>/ folder) + set photo_url -
    // exactly what EditProfile does after the picker returns bytes.
    final path = '$uid/it-${DateTime.now().microsecondsSinceEpoch}.png';
    await c.storage.from('avatars').uploadBinary(
          path,
          pngBytes,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
        );
    final url = c.storage.from('avatars').getPublicUrl(path);
    await c.from('profiles').update({'photo_url': url}).eq('id', uid);

    // Open "My cricket" (player stats) - it fetches player_public_profile
    // fresh (incl. photo_url), so its header avatar shows the uploaded photo.
    await settle(tester, find.text('Profile'));
    await tester.tap(find.text('Profile').last);
    await settle(tester, find.text('My cricket'));
    await tester.tap(find.text('My cricket'));
    await settle(tester, find.byType(CircleAvatar));
    final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    expect(
      avatars.any((a) => a.foregroundImage != null),
      isTrue,
      reason: 'the stats header avatar should show the uploaded photo',
    );
    await shot(tester, '60_profile_photo');

    // cleanup so the seed stays photo-less for other runs
    await c.from('profiles').update({'photo_url': null}).eq('id', uid);
  });
}
