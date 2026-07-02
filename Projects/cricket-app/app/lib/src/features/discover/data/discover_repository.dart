import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Write operations for the Discover / Matchmaking surface.
class DiscoverRepository {
  DiscoverRepository(this._c);

  final SupabaseClient _c;

  String get _uid => _c.auth.currentSession!.user.id;

  /// Uploads a post photo to the user's own folder in the public bucket and
  /// returns its CDN URL.
  Future<String> uploadPostImage(Uint8List bytes, String ext) async {
    final contentType = switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _c.storage.from('post-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return _c.storage.from('post-images').getPublicUrl(path);
  }

  Future<String> createPost({
    required String mode,
    required String flair,
    required double lat,
    required double lng,
    String? description,
    String? teamId,
    String? placeLabel,
    int? overs,
    String? skill,
    int? slotsNeeded,
    DateTime? matchAt,
    List<String>? imageUrls,
    String? linkUrl,
  }) async {
    final params = <String, dynamic>{
      '_mode': mode,
      '_flair': flair,
      '_lat': lat,
      '_lng': lng,
    };
    if (description != null && description.isNotEmpty) {
      params['_description'] = description;
    }
    if (teamId != null) params['_team_id'] = teamId;
    if (placeLabel != null && placeLabel.isNotEmpty) {
      params['_place_label'] = placeLabel;
    }
    if (overs != null) params['_overs'] = overs;
    if (skill != null) params['_skill'] = skill;
    if (slotsNeeded != null) params['_slots_needed'] = slotsNeeded;
    if (matchAt != null) params['_match_at'] = matchAt.toIso8601String();
    if (imageUrls != null && imageUrls.isNotEmpty) params['_image_urls'] = imageUrls;
    if (linkUrl != null && linkUrl.isNotEmpty) params['_link_url'] = linkUrl;
    final id = await _c.rpc('create_looking_for_post', params: params);
    return id as String;
  }

  Future<void> reply(String postId, String body) async {
    await _c.from('post_replies').insert({
      'post_id': postId,
      'author_id': _uid,
      'body': body,
    });
  }

  Future<void> cancelPost(String postId) =>
      _c.rpc('cancel_post', params: {'_post_id': postId});

  Future<void> markFilled(String postId) =>
      _c.rpc('mark_post_filled', params: {'_post_id': postId});

  Future<String> getOrCreateDmThread(String otherUserId) async {
    final id = await _c.rpc('get_or_create_dm_thread', params: {'_other': otherUserId});
    return id as String;
  }

  Future<void> sendDm(String threadId, String body) async {
    await _c.from('dm_messages').insert({
      'thread_id': threadId,
      'sender_id': _uid,
      'body': body,
    });
  }

  /// DM-4/SEC-4: stamps read_at on the OTHER side's unread messages via the
  /// secured RPC (table UPDATE on dm_messages is revoked).
  Future<void> markThreadRead(String threadId) =>
      _c.rpc('mark_thread_read', params: {'_thread_id': threadId});

  /// SEC-3: block a user (closes the DM channel both ways).
  Future<void> blockUser(String userId) =>
      _c.from('blocked_users').insert({'blocker_id': _uid, 'blocked_id': userId});

  /// MISS-2: mark all of the caller's notifications read.
  Future<void> markNotificationsRead() => _c
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()})
      .eq('recipient_id', _uid)
      .isFilter('read_at', null);

  /// Persists the caller's home base (used as the default discover anchor).
  Future<void> setMyLocation(double lat, double lng, {String? label}) =>
      _c.rpc('set_my_location', params: {
        '_lat': lat,
        '_lng': lng,
        if (label != null && label.isNotEmpty) '_label': label,
      });

  /// The caller's saved home base, or null if none is set.
  Future<({double lat, double lng, String? label})?> myHomeLocation() async {
    final res = await _c.rpc('my_home_location') as List;
    if (res.isEmpty) return null;
    final r = res.first as Map<String, dynamic>;
    return (
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
      label: r['label'] as String?,
    );
  }

  /// Persists a team's home ground (admin only, server-enforced).
  Future<void> setTeamLocation(String teamId, double lat, double lng, {String? label}) =>
      _c.rpc('set_team_location', params: {
        '_team_id': teamId,
        '_lat': lat,
        '_lng': lng,
        if (label != null && label.isNotEmpty) '_label': label,
      });

  /// A team's saved ground (members only), or null if none is set.
  Future<({double lat, double lng, String? label})?> teamHomeLocation(String teamId) async {
    final res = await _c.rpc('team_home_location', params: {'_team_id': teamId}) as List;
    if (res.isEmpty) return null;
    final r = res.first as Map<String, dynamic>;
    return (
      lat: (r['lat'] as num).toDouble(),
      lng: (r['lng'] as num).toDouble(),
      label: r['label'] as String?,
    );
  }
}

final discoverRepositoryProvider = Provider<DiscoverRepository>(
  (ref) => DiscoverRepository(ref.watch(supabaseClientProvider)),
);
