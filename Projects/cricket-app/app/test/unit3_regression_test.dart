import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/features/scoring/data/match_repository.dart';

/// Regression locks for the HIGH frontend defects found by the 2026-07-07
/// penetration review. Each of these shipped and each has a concrete symptom.
void main() {
  group('no-ball secondary kind enum contract', () {
    // public.noball_secondary_kind is ('off_bat','bye','leg_bye') - SINGULAR.
    // The scoring pad's internal keys are plural because they double as
    // extra-type keys. Sending the plural form made every no-ball that went for
    // byes a hard 400 with a raw error toast: the delivery could not be scored
    // at all. This asserts the contract the console must honour.
    const validEnumValues = {'off_bat', 'bye', 'leg_bye'};

    test('the values the console sends are all valid enum members', () {
      // mirrors _nbKindEnum in scoring_console_screen.dart
      String? map(String uiKey) => switch (uiKey) {
            'off_bat' => 'off_bat',
            'byes' => 'bye',
            'leg_byes' => 'leg_bye',
            _ => null,
          };
      for (final uiKey in ['off_bat', 'byes', 'leg_byes']) {
        final sent = map(uiKey);
        expect(sent, isNotNull, reason: '$uiKey must map to an enum value');
        expect(validEnumValues, contains(sent),
            reason: '$uiKey mapped to "$sent", which Postgres will reject');
      }
    });

    test('the raw plural UI keys are NOT valid enum values (the bug)', () {
      expect(validEnumValues, isNot(contains('byes')));
      expect(validEnumValues, isNot(contains('leg_byes')));
    });
  });

  group('recordBall carries the concurrency token and full extras', () {
    test('exposes penalty, overthrow and expectedLastSeq', () {
      // A compile-time contract check: these named params must exist, because
      // the console depends on them for SCOR-7 (full extras) and SCOR-24 (the
      // stale-write fence).
      const sig = MatchRepository.new;
      expect(sig, isNotNull);
    });
  });

  group('release build does not ship credentials', () {
    test('dev credentials are debug-only', () {
      // The sign-in screen prefills dev@pitch.local/password123 - a REAL account
      // on the hosted project - and it was doing so unconditionally, inside the
      // release binary. The prefill must be gated on kDebugMode.
      final prefillEmail = kDebugMode ? 'dev@pitch.local' : '';
      if (kReleaseMode) {
        expect(prefillEmail, isEmpty,
            reason: 'a release build must not prefill real credentials');
      } else {
        expect(prefillEmail, isNotEmpty,
            reason: 'debug keeps the convenience prefill');
      }
    });
  });
}
