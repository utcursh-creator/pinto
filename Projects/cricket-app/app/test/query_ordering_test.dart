import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// postgrest-dart's `order()` is declared
///   `order(String column, {bool ascending = false, ...})`
/// so a bare `.order('created_at')` sorts DESCENDING. Seven queries in this app
/// were written that way and every one of them wanted ascending:
///
///   * the ball log listed deliveries newest-first while computing each row's
///     over label (0.1, 0.2, ...) by POSITION, so every label was attached to
///     the wrong delivery - a scorer correcting "the wide at 2.3" would have
///     tapped and edited a different ball entirely
///   * a DM thread loaded its history backwards, then appended new messages to
///     the end, so a conversation read in neither order
///   * post replies read newest-first
///   * the claim inbox and the join-request queue were LIFO, not FIFO
///   * the innings switcher listed the 2nd innings before the 1st, directly
///     contradicting its own "oldest first" comment
///
/// Found by reading a journey screenshot: the ball log showed 0.1 = 2 runs and
/// 0.2 = 1 run when the database held exactly the opposite. The journey still
/// PASSED, because it only asserted the total.
///
/// This test fails if anyone writes a bare `.order(` again.
void main() {
  test('every postgrest order() states its direction explicitly', () {
    final offenders = <String>[];
    final bareOrder = RegExp(r"\.order\(\s*'[^']+'\s*\)");

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (bareOrder.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'postgrest order() defaults to DESCENDING. Pass ascending: '
          'explicitly.\n${offenders.join('\n')}',
    );
  });
}
