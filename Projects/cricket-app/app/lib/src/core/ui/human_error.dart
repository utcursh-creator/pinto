/// Turns a thrown object into a sentence a cricketer can act on.
///
/// The review found raw `'$e'` interpolated into SnackBars and Text across 19
/// sites. That leaks Postgres internals ("PostgrestException(message: new row
/// violates row-level security policy for table \"team_members\", code: 42501)")
/// and reads to the user as a crash. Worse, several of those strings are the
/// ONLY feedback for a failed write, so the user cannot tell what to do next.
///
/// Every message here is phrased as: what happened, and what you can do.
String humanError(Object error, {String? fallback}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  // --- our own RAISEs, which are already written for humans -----------------
  // The RPCs raise P0001 with deliberate copy; surface it rather than replacing
  // it with something vaguer. PostgrestException stringifies as
  // "PostgrestException(message: <msg>, code: P0001, ...)".
  final msg = RegExp(r'message:\s*(.+?),\s*code:').firstMatch(raw)?.group(1);
  if (msg != null && _looksHumanWritten(msg)) return _sentence(msg);

  // --- transport ------------------------------------------------------------
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection closed') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('clientexception')) {
    return 'No connection. Check your network and try again.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'That took too long. Try again in a moment.';
  }

  // --- authorization / auth -------------------------------------------------
  if (lower.contains('row-level security') ||
      lower.contains('permission denied') ||
      raw.contains('42501')) {
    return 'You do not have permission to do that.';
  }
  if (lower.contains('not authenticated') || raw.contains('28000')) {
    return 'Sign in to do that.';
  }
  if (lower.contains('jwt') && lower.contains('expired')) {
    return 'Your session expired. Sign in again.';
  }

  // --- data shape -----------------------------------------------------------
  if (raw.contains('23505') || lower.contains('duplicate key')) {
    return 'That already exists.';
  }
  if (raw.contains('23503') || lower.contains('foreign key')) {
    return 'That is still being used elsewhere, so it cannot be removed.';
  }
  if (raw.contains('23514') || lower.contains('check constraint')) {
    return 'Those details are not valid.';
  }
  if (raw.contains('22P02') || lower.contains('invalid input syntax')) {
    return 'Those details are not valid.';
  }
  if (raw.contains('PGRST202') || lower.contains('could not find the function')) {
    return 'This version of the app is out of date. Update and try again.';
  }

  return fallback ?? 'Something went wrong. Try again.';
}

/// Our RPC messages are lowercase prose without SQL punctuation; Postgres
/// internals are not. This keeps deliberate copy and drops machine noise.
bool _looksHumanWritten(String m) {
  if (m.length > 140) return false;
  const machine = [
    'relation', 'column', 'violates', 'constraint', 'syntax', 'function public.',
    'does not exist', 'null value in', 'invalid input', 'permission denied',
    'row-level security',
  ];
  final l = m.toLowerCase();
  return !machine.any(l.contains);
}

String _sentence(String m) {
  final t = m.trim();
  if (t.isEmpty) return t;
  final capped = t[0].toUpperCase() + t.substring(1);
  return capped.endsWith('.') || capped.endsWith('!') || capped.endsWith('?')
      ? capped
      : '$capped.';
}
