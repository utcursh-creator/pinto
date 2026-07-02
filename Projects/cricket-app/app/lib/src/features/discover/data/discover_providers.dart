import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'discover_models.dart';
import 'discover_repository.dart';

/// The geo anchor (lat/lng + radius) the feed searches around. Defaults to a
/// city centre until the user's saved home base loads (or they set one on the
/// Location screen). [adoptHome] applies the persisted home base only if the
/// user hasn't already chosen an anchor this session.
typedef Anchor = ({double lat, double lng, double radiusM});

class AnchorNotifier extends Notifier<Anchor> {
  bool _userSet = false;

  @override
  Anchor build() => (lat: 19.07, lng: 72.87, radiusM: 25000);

  void set(Anchor anchor) {
    _userSet = true;
    state = anchor;
  }

  /// Apply the saved home base as the default, unless the user already picked
  /// an anchor this session.
  void adoptHome(double lat, double lng) {
    if (_userSet) return;
    state = (lat: lat, lng: lng, radiusM: state.radiusM);
  }
}

final anchorProvider = NotifierProvider<AnchorNotifier, Anchor>(
  AnchorNotifier.new,
);

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
          .order('created_at');
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

/// The current user's own posts (any status), newest first.
final myPostsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('looking_for_posts')
      .select('id, mode, flair, title, status, created_at')
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
          .order('created_at');
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// The DM inbox: one entry per thread with the other participant + last message.
final dmInboxProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);

  final mine = await c.from('dm_participants').select('thread_id').eq('profile_id', me);
  final ids = [for (final r in (mine as List)) r['thread_id'] as String];
  if (ids.isEmpty) return [];

  final others = await c
      .from('dm_participants')
      .select('thread_id, profiles(id, display_name, photo_url)')
      .neq('profile_id', me)
      .inFilter('thread_id', ids);
  final byThread = <String, Map<String, dynamic>?>{};
  for (final r in (others as List)) {
    byThread[r['thread_id'] as String] = r['profiles'] as Map<String, dynamic>?;
  }

  final msgs = await c
      .from('dm_messages')
      .select('thread_id, body, created_at')
      .inFilter('thread_id', ids)
      .order('created_at', ascending: false);
  final preview = <String, String>{};
  for (final m in (msgs as List)) {
    preview.putIfAbsent(m['thread_id'] as String, () => m['body'] as String);
  }

  return [
    for (final t in ids)
      {'thread_id': t, 'other': byThread[t], 'preview': preview[t]},
  ];
});
