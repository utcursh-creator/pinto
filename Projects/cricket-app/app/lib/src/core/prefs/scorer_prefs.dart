import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/profile_provider.dart';
import '../supabase/supabase_providers.dart';

/// The scorer's own preferences, read off their profile row.
///
/// ABSENT MEANS OFF. There is no seeded set of flags: a preference nobody asked
/// for should not exist, and a brand-new scorer gets the plain, fast console -
/// which is the whole point. The wagon wheel used to be mandatory, which is why
/// a dot ball opened a modal on the most common event in cricket
/// (2026-08-05-cricheroes-setup-and-scoring-research.md).
class ScorerPrefs {
  const ScorerPrefs({this.wagonCapture = false, this.wagonDotBalls = false});

  /// Ask where the ball went, for deliveries where placement means something.
  final bool wagonCapture;

  /// Also ask on DOT BALLS. A separate opt-in on purpose: dots are the most
  /// frequent event in the game, so this is the one that costs the scorer real
  /// time. CricHQ nests it inside the wagon setting the same way.
  final bool wagonDotBalls;

  static const keyCapture = 'wagon_capture';
  static const keyDotBalls = 'wagon_dot_balls';

  factory ScorerPrefs.fromProfile(Map<String, dynamic>? profile) {
    final p = profile?['preferences'];
    final m = p is Map ? p : const {};
    return ScorerPrefs(
      wagonCapture: m[keyCapture] == true,
      wagonDotBalls: m[keyDotBalls] == true,
    );
  }
}

/// Off for anyone not signed in, and off while the profile is still loading -
/// never guess a preference ON, because the cost of a wrong guess is a modal in
/// the scorer's face on the next ball.
final scorerPrefsProvider = Provider<ScorerPrefs>((ref) {
  final profile = ref.watch(myProfileProvider).value;
  return ScorerPrefs.fromProfile(profile);
});

/// Merges a patch into the caller's preferences via `set_preferences`, which
/// merges server-side so a client that knows about one key cannot switch off a
/// key it has never heard of.
typedef PrefsWriter = Future<void> Function(Map<String, dynamic> patch);

final prefsWriterProvider = Provider<PrefsWriter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (patch) async {
    await client.rpc('set_preferences', params: {'_patch': patch});
    ref.invalidate(myProfileProvider);
  };
});
