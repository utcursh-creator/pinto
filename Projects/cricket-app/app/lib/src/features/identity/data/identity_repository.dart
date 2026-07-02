import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Write operations for the Identity surface (profile edits + team creation).
/// Reads live in identity_providers.dart.
class IdentityRepository {
  IdentityRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentSession?.user.id;
    if (id == null) {
      throw StateError('No authenticated user');
    }
    return id;
  }

  Future<void> updateMyProfile(Map<String, dynamic> fields) async {
    // `phone` is PII and lives in the self-only profile_private table, not on the
    // public profiles row (SEC-1). Route it there; write the rest to profiles.
    final rest = Map<String, dynamic>.of(fields);
    final hasPhone = rest.containsKey('phone');
    final phone = rest.remove('phone');
    if (rest.isNotEmpty) {
      await _client.from('profiles').update(rest).eq('id', _uid);
    }
    if (hasPhone) {
      await _client.from('profile_private').upsert({'id': _uid, 'phone': phone});
    }
  }

  /// Uploads an avatar (profile photo or team logo) to the user's own folder in
  /// the public `avatars` bucket and returns its CDN URL.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    final contentType = switch (ext.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _client.storage.from('avatars').getPublicUrl(path);
  }

  /// Sets the current user's profile photo.
  Future<void> setMyPhoto(String url) => updateMyProfile({'photo_url': url});

  /// Sets a team's logo (admin only, enforced by RLS on the teams table).
  Future<void> setTeamLogo(String teamId, String url) =>
      _client.from('teams').update({'logo_url': url}).eq('id', teamId);

  /// Creates a team (and the caller's captain membership, server-side) and
  /// returns the new team id.
  Future<String> createTeam({required String name, String? city}) async {
    final id = await _client.rpc(
      'create_team',
      params: {'_name': name, if (city != null && city.isNotEmpty) '_city': city},
    );
    return id as String;
  }

  /// TEAM-1: remove a membership row (a captain kicking a member, or a member
  /// leaving - RLS allows admin-or-self).
  Future<void> removeMember(String membershipId) =>
      _client.from('team_members').delete().eq('id', membershipId);

  /// TEAM-1: disband a team entirely (admin-only via RLS; memberships cascade).
  Future<void> deleteTeam(String teamId) =>
      _client.from('teams').delete().eq('id', teamId);

  /// TEAM-5: change a member's role (admin-only via RLS).
  Future<void> setMemberRole(String membershipId, String role) =>
      _client.from('team_members').update({'role': role}).eq('id', membershipId);

  /// TEAM-13: edit the team's name/city (admin-only via RLS).
  Future<void> updateTeam(String teamId, {String? name, String? city}) {
    final fields = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      'city': ?city,
    };
    return _client.from('teams').update(fields).eq('id', teamId);
  }

  /// Adds a guest member (no account) to a team; returns the membership id.
  Future<String> addGuest({
    required String teamId,
    required String guestName,
  }) async {
    final id = await _client.rpc(
      'add_guest_member',
      params: {'_team_id': teamId, '_guest_name': guestName},
    );
    return id as String;
  }

  /// Requests to claim a guest membership (becomes the real player behind it,
  /// pending a team admin's approval).
  Future<void> requestGuestClaim(String membershipId) =>
      _client.rpc('request_guest_claim', params: {'_membership_id': membershipId});

  /// Admin-only: approves a guest claim, transferring the guest membership to
  /// the claimer.
  Future<void> approveGuestClaim({
    required String membershipId,
    required String claimerId,
  }) =>
      _client.rpc('approve_guest_claim', params: {
        '_membership_id': membershipId,
        '_claimer': claimerId,
      });

  /// Admin-only: mints a shareable invite token for a team (registered-player
  /// invite path; guests use add-guest + claim instead).
  Future<String> createTeamInvite(String teamId) async {
    final token = await _client.rpc('create_team_invite', params: {'_team_id': teamId});
    return token as String;
  }

  /// Redeems an invite token, joining the caller to the team; returns the
  /// membership id.
  Future<String> acceptInvite(String token) async {
    final id = await _client.rpc('accept_invite', params: {'_invite_token': token});
    return id as String;
  }

  /// TEAM-3: revoke an outstanding invite (admin update via RLS).
  Future<void> revokeInvite(String inviteId) => _client
      .from('team_invites')
      .update({'status': 'expired'}).eq('id', inviteId);

  /// DISC-8: pre-flight a token to the inviting team's name + redeemability
  /// (null when the token is unknown), so the invite screen can show a clear
  /// state before the user taps Join.
  Future<({String teamName, bool redeemable})?> invitePreview(String token) async {
    final res =
        await _client.rpc('team_invite_preview', params: {'_invite_token': token});
    if (res == null) return null;
    final m = (res as Map).cast<String, dynamic>();
    return (
      teamName: (m['team_name'] as String?) ?? 'a team',
      redeemable: (m['redeemable'] as bool?) ?? false,
    );
  }
}

/// The shareable link for an invite token. The path is handled in-app by the
/// `/invite/:token` route; external universal-link registration is a separate
/// (credential-boundary) deployment step, like the `/watch` share links.
String inviteLink(String token) => 'https://pitch.app/invite/$token';

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(ref.watch(supabaseClientProvider)),
);
