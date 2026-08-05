import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'discover_models.dart';
import 'discover_repository.dart';

/// The anchor the discover feed searches around.
///
/// [anchorProvider] holds ONLY the anchor the user explicitly chose (null until
/// they do). Its one dependency is the signed-in user's ID - a SYNC provider,
/// so it still cannot participate in an async invalidation cascade - and it
/// exists so one person's chosen city does not follow the next person signed in
/// on the same phone (review #2, finding 55). The
/// anchor the feed should actually use is derived by [effectiveAnchor] as a pure
/// function of two values the WIDGET watches.
///
/// Two earlier shapes both crashed with "setState() called during build" on
/// every Discover open (found on the simulator, fix run 2026-07-07):
///   1. DiscoverScreen.build did `ref.listen(homeLocationProvider, ... )` and
///      mutated this notifier from the callback.
///   2. This notifier `ref.watch`ed homeLocationProvider directly - a
///      NotifierProvider watching a FutureProvider invalidates ITSELF when the
///      future resolves, and when the first watch happens during build that
///      scheduleRefresh calls setState on the ProviderScope mid-build.
/// The invariant that actually holds: NO PROVIDER may watch
/// homeLocationProvider. Widgets may; providers may not.
typedef Anchor = ({double lat, double lng, double radiusM});

typedef HomeBase = ({double lat, double lng, String? label});

const Anchor kFallbackAnchor = (lat: 19.07, lng: 72.87, radiusM: 25000.0);

class AnchorNotifier extends Notifier<Anchor?> {
  @override
  Anchor? build() {
    // Resets when the SIGNED-IN PERSON changes (review #2, finding 55). The
    // anchor is a personal choice, not a device setting: left behind at
    // sign-out it centred the next user's feed on the previous user's city AND
    // geotagged every looking-for post they published there, so nobody near
    // them ever saw it - with no coordinates anywhere on screen to explain why.
    //
    // Keyed on the USER ID, not the Session: gotrue yields a new Session object
    // on every JWT refresh (about hourly), and resetting "Near me" once an hour
    // would be its own bug.
    ref.watch(currentSessionProvider.select((s) => s?.user.id));
    return null;
  }

  void set(Anchor anchor) => state = anchor;

  /// Drop back to deriving from the saved home base.
  void clear() => state = null;
}

final anchorProvider =
    NotifierProvider<AnchorNotifier, Anchor?>(AnchorNotifier.new);

/// The user's choice wins; otherwise their saved home base; otherwise a city
/// centre. Pure, so it cannot participate in an invalidation cascade.
Anchor effectiveAnchor(Anchor? chosen, HomeBase? home) {
  if (chosen != null) return chosen;
  if (home != null) {
    return (lat: home.lat, lng: home.lng, radiusM: kFallbackAnchor.radiusM);
  }
  return kFallbackAnchor;
}

/// The signed-in user's saved home base (null if unset or anonymous). Drives the
/// default discover anchor so the feed centres on the user's real area, not a
/// hardcoded city.
final homeLocationProvider =
    FutureProvider<({double lat, double lng, String? label})?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null || session.user.isAnonymous) return null;
  return ref.watch(discoverRepositoryProvider).myHomeLocation();
});

/// A team's saved home ground (members only), or null if unset.
final teamGroundProvider =
    FutureProvider.family<({double lat, double lng, String? label})?, String>(
        (ref, teamId) async {
  return ref.watch(discoverRepositoryProvider).teamHomeLocation(teamId);
});

/// The discover feed: open posts near the anchor, with optional mode/flair
/// filters. Returns coarsened distance (approx_m), never coordinates.
final discoverFeedProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DiscoverQuery>((
      ref,
      q,
    ) async {
      // Re-fetch when auth changes: discover_posts is authenticated-only, so an
      // anonymous boot 403s; the feed must reload once the user signs in.
      ref.watch(currentSessionProvider);
      final c = ref.watch(supabaseClientProvider);
      final rows = await c.rpc('discover_posts', params: {
        '_lat': q.lat,
        '_lng': q.lng,
        '_radius_m': q.radiusM,
        if (q.mode != null) '_mode': q.mode,
        if (q.flair != null) '_flair': q.flair,
        if (q.skill != null) '_skill': q.skill,
        if (q.maxOvers != null) '_max_overs': q.maxOvers,
        if (q.onOrAfter != null) '_on_or_after': q.onOrAfter!.toIso8601String(),
      });
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// A single post's public replies, oldest first, with each author's name.
final postRepliesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      postId,
    ) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('post_replies')
          .select('id, body, author_id, created_at, profiles(display_name)')
          .eq('post_id', postId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// A single looking-for post by id, via the SECURITY DEFINER post_detail RPC
/// (SEC-2: the raw row with exact geog is no longer client-readable). Returns
/// the author + team names (DISC-5) and the place_label, never coordinates.
final postProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  id,
) async {
  final c = ref.watch(supabaseClientProvider);
  final res = await c.rpc('post_detail', params: {'_post_id': id});
  return res == null ? null : Map<String, dynamic>.from(res as Map);
});

/// Player + team name search (MISS-3). Returns rows shaped
/// {kind, id, name, subtitle, photo_url}. Empty for queries under 2 chars.
///
/// autoDispose, and that is not a tidiness choice. The key is a free-text query
/// and the screens watch it on EVERY KEYSTROKE, so without it each prefix a
/// person types ("r", "ra", "rah", "rahu", "rahul") leaves an element alive for
/// the whole session - and, worse, a query that failed on a dropped connection
/// stays cached AS AN ERROR. Retyping the exact same name then re-reads the
/// dead element and never touches the network, so the one thing a user will
/// naturally try is precisely the thing that cannot work
/// (review #2, findings 33/64/86).
final searchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, query) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c.rpc('search_players_and_teams', params: {'_query': q});
  return List<Map<String, dynamic>>.from(rows as List);
});

/// The current user's own posts (any status), newest first.
final myPostsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('looking_for_posts')
      // expires_at and match_at, because a post that has run out reads exactly
      // like a live one without them (review #2, finding 43)
      .select('id, mode, flair, title, status, created_at, expires_at, match_at')
      .eq('author_id', me)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// Initial message load for a DM thread (the screen then appends realtime).
final dmThreadMessagesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      threadId,
    ) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('dm_messages')
          .select('id, sender_id, body, created_at')
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// The DM inbox: one entry per thread with the other participant + last message.
///
/// ONE call. This used to be three round-trips, the last of which pulled down
/// every message of every thread - body included - just to take the newest as a
/// preview and count the unread ones (review #2 finding 15). The inbox is
/// invalidated on every incoming message, so the cost was paid again and again
/// on exactly the conversations that had grown longest. The thread-id list also
/// travelled in a GET query string, which has a length limit.
///
/// `public.dm_inbox()` does the DISTINCT ON and the count server-side and is
/// scoped to the caller; the shape below is pinned by pgTAP 141.
final dmInboxProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(currentSessionProvider)?.user.id == null) return [];
  final rows = await ref.watch(supabaseClientProvider).rpc('dm_inbox');
  return [for (final r in (rows as List)) Map<String, dynamic>.from(r as Map)];
});

/// Total unread DM count, as a PURE function of inbox rows.
///
/// This used to be a synchronous `Provider<int>` doing
/// `ref.watch(dmInboxProvider).value`. A sync provider that watches an ASYNC one
/// invalidates ITSELF the moment the async value arrives; when the widget's first
/// watch happens during build, the ancestor is flushed inside that watch,
/// produces a new value, notifies this provider, and invalidateSelf ->
/// scheduleRefresh -> setState on the ProviderScope MID-BUILD. That crashed
/// Discover on every open (three separate shapes of the same bug - fix run
/// 2026-07-07). Widgets may watch async providers; an intermediate SYNC provider
/// may not. So there is no intermediate provider any more: the widget watches
/// dmInboxProvider and calls this.
int unreadDmCount(List<Map<String, dynamic>>? inbox) {
  var n = 0;
  for (final t in inbox ?? const []) {
    n += (t['unread'] as int?) ?? 0;
  }
  return n;
}

/// DM-1: the other participant of a thread (name + photo) for the header.
final threadOtherProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, threadId) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return null;
  final c = ref.watch(supabaseClientProvider);
  final row = await c
      .from('dm_participants')
      .select('profiles(id, display_name, photo_url)')
      .eq('thread_id', threadId)
      .neq('profile_id', me)
      .maybeSingle();
  return row?['profiles'] as Map<String, dynamic>?;
});

/// MISS-2: the caller's notifications, newest first.
final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('notifications')
      .select('id, type, ref_id, body, read_at, created_at')
      .order('created_at', ascending: false)
      .limit(50);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// Unread notification count, as a PURE function of notification rows (see
/// unreadDmCount for why this is not a provider).
int unreadNotificationCount(List<Map<String, dynamic>>? rows) =>
    (rows ?? const []).where((n) => n['read_at'] == null).length;
