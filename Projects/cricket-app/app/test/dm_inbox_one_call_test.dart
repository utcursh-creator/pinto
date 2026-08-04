import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), finding 15: opening the inbox
/// downloaded every message body of every conversation the user has.
///
/// The provider made three round-trips - the user's thread ids, the other
/// participant of each, then EVERY MESSAGE of all of them, `body` included -
/// purely to take the first as a preview and count the unread ones. A user with
/// a few long conversations pulls down thousands of rows on every inbox open,
/// every incoming message (the inbox is invalidated per message) and every
/// pull-to-refresh. The thread-id list also travelled in a GET query string via
/// `.inFilter`, whose length grows with how many people you talk to.
///
/// `public.dm_inbox()` returns one row per thread and no body but the preview.
/// The pgTAP file 141-dm-inbox-rpc pins its shape and its per-caller scoping;
/// this pins that the client actually calls it, because a correct RPC nobody
/// calls fixes nothing.
void main() {
  test('the inbox is one RPC, not a bulk message download', () {
    final src = File('lib/src/features/discover/data/discover_providers.dart')
        .readAsStringSync();
    // the provider body, up to the closing `});` of its declaration
    final start = src.indexOf('final dmInboxProvider');
    expect(start, isNot(-1), reason: 'sanity: the provider still exists');
    final end = src.indexOf('\n});', start);
    expect(end, isNot(-1), reason: 'sanity: found the end of the declaration');
    final body = src.substring(start, end);

    expect(body, contains("rpc('dm_inbox')"),
        reason: 'the whole inbox is one server-side call');
    expect(body.contains("from('dm_messages')"), isFalse,
        reason: 'no message table read belongs in the inbox at all - that is '
            'what downloaded every body of every thread:\n$body');
    expect(body.contains('inFilter'), isFalse,
        reason: 'and no thread-id list belongs in a URL:\n$body');
  });
}
