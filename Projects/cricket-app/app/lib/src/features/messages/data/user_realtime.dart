
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../discover/data/discover_providers.dart';

/// ONE realtime channel per SIGNED-IN USER, `user:<uid>`, carrying every event
/// that could change a badge (review #3, and review #2's deferred finding 40).
///
/// Before this there was no realtime subscription of any kind outside the
/// Messages screens, and dmInboxProvider / notificationsProvider are plain
/// FutureProviders - not autoDispose - so each resolved once per app launch and
/// held. Discover is the initial branch of the shell and stays mounted all
/// session, so the mail and bell badges simply never changed: ten minutes and
/// three DMs later they were still empty, and opening the inbox showed the
/// ten-minute-old rows.
///
/// The server sends one event per arrival on this topic (a DM to the recipient,
/// a notification row for everything else). The client does not care which -
/// it re-reads the two providers the badges are drawn from.
class UserRealtime {
  UserRealtime(this._ref);

  final Ref _ref;
  SupabaseClient? _c;
  RealtimeChannel? _channel;
  String? _uid;

  /// Subscribes to the topic for [uid], replacing any previous subscription.
  /// A null uid (signed out, or anonymous) tears the channel down: an anonymous
  /// visitor has no inbox and no notifications.
  /// [client] is passed in rather than read at construction: an anonymous or
  /// signed-out session has no topic to join, and reading the Supabase client
  /// eagerly would make every widget test that mounts the app shell require a
  /// live Supabase - for a channel it never opens.
  void follow(SupabaseClient? client, String? uid) {
    if (uid == _uid) return;
    _detach();
    _uid = uid;
    _c = client;
    if (uid == null || client == null) return;
    // a private topic needs a JWT on the socket, or the per-user receive policy
    // silently drops every broadcast
    client.realtime.setAuth(client.auth.currentSession?.accessToken);
    final ch = client.channel('user:$uid',
        opts: const RealtimeChannelConfig(private: true));
    ch.onBroadcast(event: 'USER', callback: (_) => _refresh()).subscribe(
      (status, _) {
        // whatever arrived while the socket was down is exactly what the badges
        // are not showing
        if (status == RealtimeSubscribeStatus.subscribed) _refresh();
      },
    );
    _channel = ch;
  }

  void _refresh() {
    _ref.invalidate(dmInboxProvider);
    _ref.invalidate(notificationsProvider);
  }

  void _detach() {
    final ch = _channel;
    if (ch != null) _c?.removeChannel(ch);
    _channel = null;
  }

  void dispose() => _detach();
}

/// Kept alive by the app shell for the whole session, and re-pointed whenever
/// the signed-in user changes.
final userRealtimeProvider = Provider<UserRealtime>((ref) {
  final rt = UserRealtime(ref);
  ref.onDispose(rt.dispose);
  // THE CLIENT FIRST. currentSessionProvider reads the Supabase client itself,
  // so asking for the session before checking there IS one would make every
  // widget test that mounts the app shell stand up a backend for a channel it
  // never opens. No client, no session to follow.
  final client = ref.watch(supabaseClientOrNullProvider);
  if (client == null) return rt;
  rt.follow(client, ref.watch(currentSessionProvider)?.user.id);
  return rt;
});
