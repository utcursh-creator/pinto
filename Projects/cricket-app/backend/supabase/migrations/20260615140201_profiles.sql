create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  phone         text,
  display_name  text not null,
  photo_url     text,
  city          text,
  batting_style public.batting_style,
  bowling_style text,
  playing_role  public.playing_role,
  created_at    timestamptz not null default now()
);

create index profiles_phone_idx on public.profiles (phone);

alter table public.profiles enable row level security;
