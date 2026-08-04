import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'identity_repository.dart';

/// Teams the current user belongs to: each row is {role, teams: {...}}.
final myTeamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (ref.watch(currentSessionProvider) == null) return [];
  return ref.watch(identityRepositoryProvider).myTeams();
});

/// A single team row by id.
final teamProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  teamId,
) async {
  final client = ref.watch(supabaseClientProvider);
  return client.from('teams').select().eq('id', teamId).maybeSingle();
});

/// Pending guest-claim requests an admin can act on. RLS already limits rows to
/// the caller's own requests OR claims on teams they administer; excluding the
/// caller's own requests leaves exactly the admin inbox.
final claimInboxProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return [];
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('guest_claim_requests')
      .select(
        'id, membership_id, requested_by, status, '
        'team_members(guest_name, team_id, teams(name)), '
        // TEAM-9: name + photo, so the captain sees WHO is claiming
        'requester:requested_by(display_name, photo_url)',
      )
      .eq('status', 'pending')
      .neq('requested_by', session.user.id)
      .order('created_at', ascending: true); // a queue is FIFO
  return List<Map<String, dynamic>>.from(rows as List);
});

/// A team's roster: real members carry a `profiles` object, guests a guest_name.
final teamRosterProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      teamId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      // TEAM-10: captain first (enum order captain/admin/player), then oldest.
      final rows = await client
          .from('team_members')
          .select('id, role, guest_name, profile_id, profiles(display_name, photo_url)')
          .eq('team_id', teamId)
          // Rows with left_at set are kept only so old scorecards can still
          // name them - they are not on the roster.
          .isFilter('left_at', null)
          .order('role', ascending: true)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// DISC-8: pre-flight an invite token -> team name + redeemability + the
/// reason a dead token died (null = unknown token). Keyed by token.
final invitePreviewProvider = FutureProvider.family<
        ({String teamName, bool redeemable, String? reason})?, String>(
    (ref, token) => ref.watch(identityRepositoryProvider).invitePreview(token));

/// TEAM-3/MISS-6: a team's outstanding (pending) invites, for the admin manage
/// sheet. RLS scopes reads to team admins.
final activeTeamInvitesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, teamId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('team_invites')
      .select('id, invite_token, uses, max_uses, expires_at, created_at')
      .eq('team_id', teamId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// TEAM-13: the team's W/L career line (anon-safe RPC off completed matches).
final teamStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, teamId) async {
  final client = ref.watch(supabaseClientProvider);
  final res =
      await client.rpc('team_career_stats', params: {'_team_id': teamId});
  return Map<String, dynamic>.from(res as Map);
});

/// TEAM-13: the team's matches (either side), newest first, with names+result.
final teamMatchesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, teamId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('matches')
      .select('id, status, overs_limit, result, created_at, '
          'team_a:team_a_id(name), team_b:team_b_id(name)')
      .or('team_a_id.eq.$teamId,team_b_id.eq.$teamId')
      .inFilter('status', ['live', 'innings_break', 'complete'])
      .order('created_at', ascending: false)
      .limit(15);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// TEAM-11: pending join requests for a team (admin view via RLS).
final pendingJoinRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, teamId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('team_join_requests')
      .select('id, requester_id, created_at, profiles(display_name, photo_url)')
      .eq('team_id', teamId)
      .eq('status', 'pending')
      .order('created_at', ascending: true); // a queue is FIFO
  return List<Map<String, dynamic>>.from(rows as List);
});
