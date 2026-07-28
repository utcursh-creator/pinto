import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/presentation/new_post_composer.dart';

/// CONFIRMED MEDIUM (fix-run re-review 2026-07-07): `discover_posts` hides any
/// post whose match_at is more than six hours in the past, but the composer's
/// date picker offered YESTERDAY. So a user could pick a time already gone, the
/// post was created successfully, and then nobody - not even the author - would
/// ever see it.
///
/// The comparison lived inside `_pickWhen`, wrapped around two platform date
/// pickers, which is untestable. Extracted so the rule itself can be pinned.
void main() {
  final now = DateTime(2026, 7, 28, 12, 0);

  test('a match still to come is fine', () {
    expect(
      isPastFeedFloor(now.add(const Duration(days: 2)), now),
      isFalse,
    );
  });

  test('a match earlier today is still offerable inside the floor', () {
    // 5h ago: the feed still shows it, so the composer must accept it - people
    // post about a game that has just started.
    expect(
      isPastFeedFloor(
          now.subtract(const Duration(hours: 5)), now),
      isFalse,
    );
  });

  test('a match past the floor is refused', () {
    expect(
      isPastFeedFloor(
          now.subtract(const Duration(hours: 7)), now),
      isTrue,
    );
  });

  test('yesterday - what the picker used to offer - is refused', () {
    expect(
      isPastFeedFloor(
          now.subtract(const Duration(days: 1)), now),
      isTrue,
    );
  });

  test('the floor matches the SQL in discover_posts', () {
    // migration 20260707160000_posts_expire.sql:
    //   and (p.match_at is null or p.match_at >= now() - interval '6 hours')
    expect(postFeedFloor, const Duration(hours: 6));
  });
}
