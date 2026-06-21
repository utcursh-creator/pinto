import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Name of a squad/roster member row shaped {guest_name, profiles:{display_name}}.
String memberName(Map<String, dynamic> m) {
  final guest = m['guest_name'] as String?;
  if (guest != null && guest.isNotEmpty) return guest;
  final p = m['profiles'] as Map<String, dynamic>?;
  return (p?['display_name'] as String?) ?? 'Player';
}

/// All teams (for the opponent picker).
final allTeamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final c = ref.watch(supabaseClientProvider);
  final rows = await c.from('teams').select('id, name, city').order('name');
  return List<Map<String, dynamic>>.from(rows as List);
});

/// A team's members (for squad selection).
final teamMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, teamId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('team_members')
          .select('id, profile_id, guest_name, profiles(display_name)')
          .eq('team_id', teamId);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// A match row.
final matchProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  matchId,
) async {
  final c = ref.watch(supabaseClientProvider);
  return c.from('matches').select().eq('id', matchId).maybeSingle();
});

/// A match's squad, with each member's name + which team they're on.
final matchSquadProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('match_squad')
          .select(
            'team_id, team_member_id, team_members(id, guest_name, profiles(display_name))',
          )
          .eq('match_id', matchId);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// The latest innings of a match (to resume scoring / view).
final currentInningsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      return c
          .from('innings')
          .select('id, innings_number, batting_team_id, bowling_team_id, status, target')
          .eq('match_id', matchId)
          .order('innings_number', ascending: false)
          .limit(1)
          .maybeSingle();
    });

/// All innings of a match, oldest first (for the viewer's innings switcher).
final matchInningsListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('innings')
          .select(
            'id, innings_number, batting_team_id, bowling_team_id, status, target',
          )
          .eq('match_id', matchId)
          .order('innings_number');
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// Map of {teamId: name} for a match's two teams. RLS-safe for anon viewers
/// (the teams of a live/complete match are readable via the gated policy).
final matchTeamNamesProvider =
    FutureProvider.family<Map<String, String>, String>((ref, matchId) async {
      final match = await ref.watch(matchProvider(matchId).future);
      if (match == null) return {};
      final ids = [match['team_a_id'], match['team_b_id']]
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return {};
      final c = ref.watch(supabaseClientProvider);
      final rows = await c.from('teams').select('id, name').inFilter('id', ids);
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['id'] as String: (r['name'] as String?) ?? 'Team',
      };
    });

/// The full computed innings state (the fold) - score, cards, strike, rates.
final inningsStateProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, inningsId) async {
      final c = ref.watch(supabaseClientProvider);
      final res = await c.rpc('compute_innings_state', params: {'_innings_id': inningsId});
      return Map<String, dynamic>.from(res as Map);
    });

/// Matches the current user is the scorer of (the Matches tab list).
final myMatchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('matches')
      .select('id, status, overs_limit, venue, created_at')
      .eq('scorer_id', me)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});
