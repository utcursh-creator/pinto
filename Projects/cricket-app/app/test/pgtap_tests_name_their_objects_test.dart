import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A DRIFT GUARD for a defect class that has now bitten this project twice.
///
/// A pgTAP test that names the object under test with
/// `(select id from public.X limit 1)` is not testing its own fixture - it is
/// testing whatever row the database happens to hold. On an empty database that
/// is the fixture and everything passes; on a database with real data in it,
/// the call lands on a stranger's row, trips a DIFFERENT guard, and throws_ok
/// (given only an errcode) is perfectly happy.
///
/// Commit 114002b rescoped TWELVE files off this shape. Four survived that
/// sweep - 50, 90, 91 and 99 - and 90 was found only because a device-journey
/// run left real tournaments in the local DB and turned it red. It had been
/// passing on the WRONG ERROR the whole time: the organizer check, not the
/// team-admin guard the test is named after.
///
/// Two manual sweeps is enough. This one names the class, so the third
/// occurrence fails a test instead of waiting for someone to run the suite
/// against a dirty database and notice.
///
/// It lives in the Dart suite because pgTAP cannot read files, and because
/// `flutter test` is the harness that actually runs on every change - the same
/// reasoning as error_branches_have_retry_test.dart, which reads lib/.
void main() {
  test('no pgTAP test names its object with an unscoped `limit 1`', () {
    final dir = Directory('../backend/supabase/tests');
    expect(dir.existsSync(), isTrue,
        reason: 'sanity: the guard must be looking at the real test directory, '
            'not silently passing because the path moved');

    // `(select <col> from <table> limit 1)` with NO where clause: the shape
    // that reads the world instead of the fixture. A subquery that filters -
    // `where name = 'Z'`, `where email = ...` - is naming something and is fine.
    final unscoped =
        RegExp(r'\(\s*select\s+\w+\s+from\s+(public\.)?\w+\s+limit\s+1\s*\)');

    final offenders = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.sql')) continue;
      var lineNo = 0;
      for (final raw in f.readAsLinesSync()) {
        lineNo++;
        final line = raw.trim();
        // Comments are where the habit is DOCUMENTED, deliberately, by the
        // fixes that removed it. Documenting a trap is not falling into it.
        if (line.startsWith('--')) continue;
        if (unscoped.hasMatch(line)) {
          offenders.add('${f.uri.pathSegments.last}:$lineNo  $line');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'These name their object by whatever the database happens to '
            'hold, so they pass on an empty DB and quietly test something else '
            'on a used one. Capture the id with \\gset and interpolate it with '
            'format(%L) - psql does NOT substitute :\'var\' inside \$\$ quoting, '
            'which is what made this habit attractive in the first place:\n'
            '${offenders.join('\n')}');
  });
}
