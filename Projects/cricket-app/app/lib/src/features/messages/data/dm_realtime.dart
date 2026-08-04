import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// ONE realtime channel per `dm:<threadId>` topic, shared by every screen that
/// cares about it.
///
/// Before this, the inbox opened a channel per visible thread AND the thread
/// screen opened its own channel on the same topic. Two joins on one topic from
/// a single client is not a supported shape - the second subscribe can take over
/// or drop the first, which killed live delivery in the open conversation
/// exactly when the user was looking at it (penetration review 2026-07-07).
///
/// Screens now attach a listener and get a disposer back. The channel is created
/// on the first attach and torn down on the last detach, so there is never more
/// than one join per topic and never a leak.
class DmRealtime {
  DmRealtime(this._c);

  final SupabaseClient _c;
  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, List<void Function(Map<String, dynamic>)>> _listeners = {};

  final Map<String, List<void Function()>> _subscribed = {};

  /// Subscribes [onInsert] to `dm:<threadId>`. Call the returned function to
  /// detach; the underlying channel closes when the last listener detaches.
  ///
  /// [onSubscribed] fires whenever the topic is (re)joined. A re-join means the
  /// socket was down, and what was missed while it was down is exactly what the
  /// screen is not showing (review #2 finding 41) - so this is where a listener
  /// catches up.
  void Function() listen(
    String threadId,
    void Function(Map<String, dynamic>) onInsert, {
    void Function()? onSubscribed,
  }) {
    final topic = 'dm:$threadId';
    _listeners.putIfAbsent(topic, () => []).add(onInsert);
    if (onSubscribed != null) {
      _subscribed.putIfAbsent(topic, () => []).add(onSubscribed);
    }

    if (!_channels.containsKey(topic)) {
      // a private channel needs a JWT on the socket, or the participant-scoped
      // receive policy silently drops every broadcast
      _c.realtime.setAuth(_c.auth.currentSession?.accessToken);
      final ch = _c.channel(topic,
          opts: const RealtimeChannelConfig(private: true));
      ch
          .onBroadcast(
            event: 'INSERT',
            callback: (payload) {
              final record =
                  (payload['payload'] as Map?)?['record'] as Map<String, dynamic>?;
              if (record == null) return;
              // copy: a listener may detach while we are iterating
              for (final l in List.of(_listeners[topic] ?? const [])) {
                l(record);
              }
            },
          )
          .subscribe((status, _) {
        if (status != RealtimeSubscribeStatus.subscribed) return;
        for (final s in List.of(_subscribed[topic] ?? const [])) {
          s();
        }
      });
      _channels[topic] = ch;
    }

    return () {
      _subscribed[topic]?.remove(onSubscribed);
      final ls = _listeners[topic];
      if (ls == null) return;
      ls.remove(onInsert);
      if (ls.isEmpty) {
        _listeners.remove(topic);
        _subscribed.remove(topic);
        final ch = _channels.remove(topic);
        if (ch != null) _c.removeChannel(ch);
      }
    };
  }

  void disposeAll() {
    for (final ch in _channels.values) {
      _c.removeChannel(ch);
    }
    _channels.clear();
    _listeners.clear();
    _subscribed.clear();
  }
}

final dmRealtimeProvider = Provider<DmRealtime>((ref) {
  final r = DmRealtime(ref.watch(supabaseClientProvider));
  ref.onDispose(r.disposeAll);
  return r;
});
