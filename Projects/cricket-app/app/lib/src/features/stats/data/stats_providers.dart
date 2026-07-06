import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import 'stats_models.dart';

/// Career + recent-form stats for a player, keyed by profile id. Login-free:
/// `player_public_profile` is a SECURITY DEFINER RPC granted to anon, so a
/// shared player link resolves for logged-out viewers too.
final playerStatsProvider =
    FutureProvider.family<PlayerStats, String>((ref, profileId) async {
  final client = ref.watch(supabaseClientProvider);
  final res = await client.rpc(
    'player_public_profile',
    params: {'_profile_id': profileId},
  );
  return PlayerStats.fromJson(Map<String, dynamic>.from(res as Map));
});

/// STAT-2: career + form for an UNCLAIMED guest, keyed by team_members.id.
/// guest_player_profile composes the same career/recent_form payload; the
/// guest's name stands in for the profile identity.
final guestPlayerStatsProvider =
    FutureProvider.family<PlayerStats, String>((ref, memberId) async {
  final client = ref.watch(supabaseClientProvider);
  final res = await client
      .rpc('guest_player_profile', params: {'_member_id': memberId});
  final m = Map<String, dynamic>.from(res as Map);
  return PlayerStats.fromJson({
    'profile': {'display_name': (m['name'] as String?) ?? 'Player'},
    'career': m['career'],
    'recent_form': m['recent_form'],
  });
});
