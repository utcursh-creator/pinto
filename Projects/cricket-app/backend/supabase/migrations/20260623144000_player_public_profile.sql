-- player_public_profile(_profile_id): one-round-trip composition for the public
-- profile stats screen - anon-safe identity (display_name/photo/batting_style)
-- plus career stats and the last-5 form strip. For a claimed user the player_key
-- equals their profile_id (v_player_key resolves COALESCE(profile_id, id)).
-- Composes three already-anon-granted SECURITY DEFINER functions.
create or replace function public.player_public_profile(_profile_id uuid)
returns jsonb language sql security definer set search_path = '' stable as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.public_profile_minimal(_profile_id) p),
    'career', public.player_career_stats(_profile_id),
    'recent_form', public.player_recent_form(_profile_id, 5)
  );
$$;
revoke all on function public.player_public_profile(uuid) from public;
grant execute on function public.player_public_profile(uuid) to anon, authenticated;
