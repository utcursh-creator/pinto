-- PROF-1 / MISS-5: a unique, case-insensitive handle so players are addressable
-- (search, /player/<handle>, @mentions). Nullable during rollout; the app
-- collects + validates it at create-profile. Uniqueness is enforced
-- case-insensitively via a functional unique index (NULLs stay distinct, so
-- existing rows without a handle don't collide).
alter table public.profiles add column handle text;

alter table public.profiles
  add constraint profiles_handle_format
  check (handle is null or handle ~ '^[A-Za-z0-9_]{3,30}$');

create unique index profiles_handle_lower_uidx on public.profiles (lower(handle));
