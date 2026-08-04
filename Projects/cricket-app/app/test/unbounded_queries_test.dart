import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), findings 21 / 74 / 83: four queries
/// fetch a set that grows with the whole database, or with a user's entire
/// history, and never asked for fewer.
///
/// Most unbounded queries in this app are FINE and must be left alone - a match
/// squad is eleven rows, an innings is at most a few hundred deliveries, a team
/// roster is a club. Adding limits there would break correctness for no gain.
/// These four are different: each one's row count is bounded by nothing the
/// user can see.
///
///   * the public live-match list - EVERY live match in the world, and
///     reachable without signing in, so it is the most exposed query in the app
///   * my matches - every game this scorer has ever scored
///   * tournaments - every tournament that has ever existed, unfiltered
///   * a DM thread - every message the conversation has ever contained
///
/// A source guard, because the thing being asserted is the shape of a query
/// builder chain: a mocked repository test cannot see whether `.limit()` was
/// ever called, and that is precisely the bug.
/// Comments are stripped before scanning: a `;` inside a `//` comment would
/// otherwise cut the builder chain short and make the guard assert nothing.
/// (It did exactly that on first run - the comment "accumulates these for
/// years;" truncated the chain to a single line.)
String _code(String path) => File(path)
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  const cases = <String, ({String file, String anchor})>{
    'the public live-match list': (
      file: 'lib/src/features/scoring/data/match_providers.dart',
      anchor: "inFilter('status', ['live', 'innings_break'])",
    ),
    'my matches': (
      file: 'lib/src/features/scoring/data/match_providers.dart',
      anchor: "eq('scorer_id', me)",
    ),
    'the tournaments list': (
      file: 'lib/src/features/tournaments/data/tournament_providers.dart',
      anchor: "from('tournaments')",
    ),
    'a DM thread': (
      file: 'lib/src/features/messages/presentation/dm_thread_screen.dart',
      anchor: "from('dm_messages')",
    ),
  };

  cases.forEach((name, c) {
    test('$name asks for a bounded number of rows', () {
      final src = _code(c.file);
      final at = src.indexOf(c.anchor);
      expect(at, isNot(-1),
          reason: 'anchor "${c.anchor}" not found in ${c.file} - this guard '
              'has drifted from the code and is no longer checking anything');

      // the builder chain runs from the anchor to the statement terminator
      final end = src.indexOf(';', at);
      final chain = src.substring(at, end);
      expect(chain, contains('.limit('),
          reason: '$name is unbounded. Its row count grows with the database '
              '(or with the user\'s whole history), so on a phone this is a '
              'download that gets slower every week the app succeeds.');
    });
  });

  test('domain-bounded queries are deliberately left alone', () {
    // A guard against over-correcting. If someone "fixes" these the same way,
    // a scorecard silently loses players and an innings loses deliveries -
    // which is a correctness bug, not a performance one.
    const mustNotBeLimited = [
      ("lib/src/features/scoring/data/match_providers.dart", "from('match_squad')"),
      // the innings LIST of a match - anchored on its own order clause,
      // because a bare from('innings') also matches currentInningsProvider,
      // which is a single-row lookup and legitimately uses .limit(1)
      ("lib/src/features/scoring/data/match_providers.dart",
          "order('innings_number', ascending: true)"),
    ];
    for (final (file, anchor) in mustNotBeLimited) {
      final src = _code(file);
      final at = src.indexOf(anchor);
      expect(at, isNot(-1), reason: 'anchor "$anchor" not found in $file');
      // scan BACKWARDS to the start of the statement for order-clause anchors
      final stmtStart = src.lastIndexOf('await c', at);
      final chain = src.substring(stmtStart == -1 ? at : stmtStart,
          src.indexOf(';', at));
      expect(chain, isNot(contains('.limit(')),
          reason: '$anchor is bounded by the match itself - capping it would '
              'drop players off a scorecard or balls out of an innings');
    }
  });
}
