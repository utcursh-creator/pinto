-- Journey map C1 (ceiling): the app had NO preferences mechanism at all, which
-- is why the wagon wheel was mandatory and a dot ball opened a modal on the
-- most common event in cricket. Nobody ships placement capture that way - in
-- CricHQ it is a SETTING you turn on, with plotting DOT BALLS a further option
-- inside it (2026-08-05-cricheroes-setup-and-scoring-research.md).
--
-- ACCOUNT-level, not device-level: a scorer who reinstalls, or who scores from
-- a second phone at the same ground, keeps his choice. profiles is already
-- own-row for writes, so this needs one column and one merge RPC - no new
-- table, no new RLS surface, nothing for a reviewer to re-audit.
--
-- Absent = OFF. There is deliberately no default row of flags: a preference the
-- scorer never asked for should not exist, and "{}" reads as every aid off.
alter table public.profiles
  add column if not exists preferences jsonb not null default '{}'::jsonb;

-- MERGE, never replace. The client sends only the key it changed; a replace
-- would silently switch off a preference the scorer never touched - the same
-- class of bug as an authoritative save that drops rows nobody mentioned.
create or replace function public.set_preferences(_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare _me uuid := (select auth.uid()); _out jsonb;
begin
  if _me is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if _patch is null or jsonb_typeof(_patch) <> 'object' then
    raise exception 'preferences must be a json object' using errcode = '22023';
  end if;

  update public.profiles
     set preferences = coalesce(preferences, '{}'::jsonb) || _patch
   where id = _me
  returning preferences into _out;

  if _out is null then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  return _out;
end; $function$;

revoke all on function public.set_preferences(jsonb) from public;
grant execute on function public.set_preferences(jsonb) to authenticated;
