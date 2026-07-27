-- CRITICAL (penetration review 2026-07-07, rls-team-members-self-update-takeover):
-- TOTAL TEAM TAKEOVER via one PostgREST call.
--
-- `team_members_update_admin_or_self` had a self-branch:
--     using       (is_team_admin(team_id) or profile_id = auth.uid())
--     with check  (is_team_admin(team_id) or profile_id = auth.uid())
-- WITH CHECK is evaluated against the NEW row, and `profile_id` is unchanged by
-- the attack, so the admin branch is never consulted and BOTH `team_id` and
-- `role` are free. Any signed-in user (everyone owns a membership row - create_team
-- makes you captain of your own team) could run:
--     PATCH /rest/v1/team_members?id=eq.<their own row>
--     {"team_id":"<any victim team>","role":"admin"}
-- and is_team_admin(victim) flips false -> true, because that helper reads exactly
-- this table. Every admin-gated surface then falls: rename/delete the team, add and
-- remove members, read the team's exact home-ground coordinates, mint invites,
-- create matches in its name, absorb its guest history. Team ids are enumerable
-- (teams_select_authenticated is `using (true)`). Reproduced live.
--
-- FIX: there is no legitimate client-side self-UPDATE on this table - the only
-- direct write in the app is setMemberRole (an ADMIN action). So the self-branch is
-- deleted outright and UPDATE becomes admin-only. SECURITY DEFINER RPCs bypass RLS,
-- so approve_guest_claim (the one RPC that updates team_members.profile_id) is
-- unaffected and needs no exemption.
drop policy "team_members_update_admin_or_self" on public.team_members;

create policy "team_members_update_admin" on public.team_members
  for update to authenticated
  using (public.is_team_admin(team_id))
  with check (public.is_team_admin(team_id));

-- Even for an admin, a membership row must never be re-pointed at a different
-- team or a different person: that is the takeover primitive, not a role change.
-- The policy alone cannot express "these columns are immutable", so a trigger does.
-- It is deliberately NOT security definer - it only compares OLD/NEW.
create or replace function public.team_members_immutable_identity()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.team_id is distinct from old.team_id then
    raise exception 'a membership cannot be moved to another team' using errcode = 'P0001';
  end if;
  -- Repointing a membership at a DIFFERENT person is the takeover primitive.
  -- Two transitions are legitimate and must stay open:
  --   null -> person : the guest-claim flow (approve_guest_claim)
  --   person -> null : account deletion detaching a player into a guest row, so
  --                    match history survives without naming anyone
  if old.profile_id is not null and new.profile_id is not null
     and new.profile_id <> old.profile_id then
    raise exception 'a membership cannot be reassigned to another player' using errcode = 'P0001';
  end if;
  return new;
end; $$;

-- guest claim legitimately sets profile_id when it was NULL, hence the
-- `old.profile_id is not null` condition above.
create trigger team_members_immutable_identity_trg
  before update on public.team_members
  for each row execute function public.team_members_immutable_identity();

-- The app's only direct UPDATE moves to an admin-gated RPC, so the client never
-- needs table-level UPDATE at all. This also lifts the last-captain guard
-- (TEAM-5) out of the UI, where it was advisory only.
create or replace function public.set_team_member_role(
  _membership_id uuid, _role public.team_member_role
) returns void language plpgsql security definer set search_path = public as $$
declare _team uuid; _current public.team_member_role;
begin
  select team_id, role into _team, _current
    from public.team_members where id = _membership_id;
  if _team is null then raise exception 'membership not found' using errcode = 'P0001'; end if;
  if not public.is_team_admin(_team) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if _current = 'captain' and _role <> 'captain'
     and (select count(*) from public.team_members
           where team_id = _team and role = 'captain') <= 1 then
    raise exception 'a team needs at least one captain' using errcode = 'P0001';
  end if;
  update public.team_members set role = _role where id = _membership_id;
end; $$;
revoke all on function public.set_team_member_role(uuid, public.team_member_role) from public;
grant execute on function public.set_team_member_role(uuid, public.team_member_role) to authenticated;
