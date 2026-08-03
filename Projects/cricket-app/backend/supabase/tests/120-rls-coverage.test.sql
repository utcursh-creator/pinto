begin;
select plan(3);
-- Written after the CRITICAL in whole-system review #2, where `matches` granted
-- INSERT under a policy that checked ownership but not PARTICIPATION, letting a
-- stranger fabricate a permanent match between two clubs.
--
-- Auditing the rest of the schema by hand showed no second instance: every other
-- write-granted table either has a policy that expresses its rule, or has NO
-- insert/update policy at all and therefore fails closed. That audit is a
-- snapshot of one afternoon. These assertions make it a standing invariant, so
-- the next table added to this schema cannot quietly ship without it.

-- 1. RLS is ON for every table in public. A table without it is readable and
-- writable by anyone holding the anon key.
select is(
  (select count(*)::int from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and not c.relrowsecurity),
  0, 'every public table has row level security enabled');

-- 2. No table grants a write to `anon`. Anonymous visitors read public matches
-- and profiles; they never write anything.
select is(
  (select count(*)::int
     from information_schema.role_table_grants
    where table_schema = 'public' and grantee = 'anon'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')),
  0, 'anon has no write grant on any table');

-- 3. Every table that grants INSERT to `authenticated` and HAS a permissive
-- insert policy must reference something beyond the caller's own id. A policy
-- of the form `owner = auth.uid()` alone is what let the matches forgery
-- through: it proves who is writing, never what they are allowed to write
-- ABOUT. This lists offenders by name so a failure is actionable.
select is(
  (select coalesce(string_agg(c.relname || '.' || p.polname, ', ' order by c.relname), '')
     from pg_policy p
     join pg_class c on c.oid = p.polrelid
     join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
    where p.polcmd = 'a'
      and pg_get_expr(p.polwithcheck, p.polrelid) ~ '^\(?[a-z_]+ = \(? ?SELECT auth\.uid\(\)'
      and pg_get_expr(p.polwithcheck, p.polrelid) !~ '(AND|OR)'
      -- these are legitimately self-scoped: the row IS the caller, so "who" and
      -- "what about" are the same question.
      and c.relname not in ('profiles', 'profile_private', 'profile_locations',
                            'post_replies', 'blocked_users')),
  '',
  'no insert policy authorizes purely on the caller''s own id');

select * from finish();
rollback;
