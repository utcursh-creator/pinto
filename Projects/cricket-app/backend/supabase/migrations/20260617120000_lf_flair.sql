-- Sub-project 4, Task 1: post flair (required field on looking_for_posts).
create type public.lf_flair as enum ('loser_pays','practice_match','corporate_match');

-- Safety fence: NOT NULL without a default is only safe on an empty table.
do $$
begin
  if (select count(*) from public.looking_for_posts) > 0 then
    raise exception 'looking_for_posts is not empty; a flair backfill is required before this migration';
  end if;
end $$;

alter table public.looking_for_posts add column flair public.lf_flair not null;
