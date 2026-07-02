-- Provenance tag so the manage UI can show how a team entered ('organizer' via
-- direct add, 'invite' via a redeemed tournament join link). Nullable, not
-- load-bearing for authz.
alter table public.tournament_teams add column added_via text;
