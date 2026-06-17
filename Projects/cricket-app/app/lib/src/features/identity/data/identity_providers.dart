import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Teams the current user belongs to: each row is {role, teams: {...}}.
final myTeamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return [];
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('team_members')
      .select('role, teams(*)')
      .eq('profile_id', session.user.id);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// A single team row by id.
final teamProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  teamId,
) async {
  final client = ref.watch(supabaseClientProvider);
  return client.from('teams').select().eq('id', teamId).maybeSingle();
});

/// A team's roster: real members carry a `profiles` object, guests a guest_name.
final teamRosterProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      teamId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      final rows = await client
          .from('team_members')
          .select('id, role, guest_name, profile_id, profiles(display_name, photo_url)')
          .eq('team_id', teamId);
      return List<Map<String, dynamic>>.from(rows as List);
    });
