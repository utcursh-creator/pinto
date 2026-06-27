import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'tournament_models.dart';

/// All tournaments, newest first (the list screen). Public-readable.
final tournamentsListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentSessionProvider); // refresh on sign-in
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('tournaments')
      .select('id, name, status, city, starts_on, champion_team_id, organizer_id')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// The full composed tournament page, login-free (tournament_overview is a
/// SECURITY DEFINER RPC granted to anon).
final tournamentOverviewProvider =
    FutureProvider.family<TournamentOverview, String>((ref, id) async {
  final c = ref.watch(supabaseClientProvider);
  final res = await c.rpc('tournament_overview', params: {'_tournament_id': id});
  return TournamentOverview.fromJson(Map<String, dynamic>.from(res as Map));
});

/// Player-of-the-match for a completed match (null if none / not enough data).
final matchPotmProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, matchId) async {
  final c = ref.watch(supabaseClientProvider);
  final res = await c.rpc('match_potm', params: {'_match_id': matchId});
  if (res == null) return null;
  return Map<String, dynamic>.from(res as Map);
});
