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
