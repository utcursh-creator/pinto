create type public.batting_style     as enum ('right', 'left');
create type public.playing_role      as enum ('batter', 'bowler', 'all_rounder', 'keeper');
create type public.team_member_role  as enum ('captain', 'admin', 'player');
create type public.invite_status     as enum ('pending', 'accepted', 'declined', 'expired');
create type public.claim_status      as enum ('pending', 'approved', 'rejected');
