import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/ui/human_error.dart';

/// The review found raw `'$e'` interpolated into SnackBars and Text at 55 call
/// sites. Those strings leak Postgres internals and, at several of them, are the
/// ONLY feedback for a failed write - so the user cannot tell what went wrong or
/// what to do. humanError() is the single mapper; these lock its contract.
void main() {
  test('never leaks Postgres internals', () {
    const raw = 'PostgrestException(message: new row violates row-level '
        'security policy for table "team_members", code: 42501, details: ...)';
    final out = humanError(raw);
    expect(out, 'You do not have permission to do that.');
    expect(out.toLowerCase(), isNot(contains('postgrest')));
    expect(out.toLowerCase(), isNot(contains('row-level')));
    expect(out, isNot(contains('42501')));
  });

  test('keeps our own deliberately-written RPC copy', () {
    const raw = 'PostgrestException(message: a team needs at least one '
        'captain, code: P0001, details: null)';
    expect(humanError(raw), 'A team needs at least one captain.');
  });

  test('keeps the concurrency message the console keys off', () {
    const raw = 'PostgrestException(message: the innings changed on another '
        'device - refresh before recording, code: P0001)';
    expect(humanError(raw), contains('changed on another device'));
  });

  test('maps offline to something actionable', () {
    expect(humanError('SocketException: Failed host lookup: supabase.co'),
        'No connection. Check your network and try again.');
  });

  test('maps duplicate and foreign-key failures to plain language', () {
    expect(humanError('duplicate key value violates unique constraint'),
        'That already exists.');
    expect(
        humanError('PostgrestException(message: update or delete on table '
            '"team_members" violates foreign key constraint, code: 23503)'),
        'That is still being used elsewhere, so it cannot be removed.');
  });

  test('a missing function tells the user to update, not to panic', () {
    expect(
        humanError('PostgrestException(message: Could not find the function '
            'public.set_toss, code: PGRST202)'),
        'This version of the app is out of date. Update and try again.');
  });

  test('falls back to the caller sentence, not the exception', () {
    final out = humanError(Exception('some internal detail'),
        fallback: 'Could not save the squads.');
    expect(out, 'Could not save the squads.');
    expect(out, isNot(contains('some internal detail')));
  });

  test('unknown failures still say something useful', () {
    expect(humanError(StateError('boom')), 'Something went wrong. Try again.');
  });
}
