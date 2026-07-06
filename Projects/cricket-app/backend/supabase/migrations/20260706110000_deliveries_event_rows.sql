-- SCOR-16 (root): retirements, timed-out dismissals and manual strike swaps are
-- EVENTS BETWEEN BALLS, not deliveries. Recording them as pseudo-balls corrupted
-- every count (over progression, balls faced, bowler figures) - and the fold
-- never even applied a retired batter's replacement. Model them as event rows in
-- the same `deliveries` stream (event-sourced, corrections/undo-compatible):
-- `event_kind` marks the row, everything ball-ish stays zero, and `is_legal` is
-- redefined to mean "counts as a legal delivery" so every modulo/count consumer
-- (folds, record_ball guards, corrections) stays correct without special cases.

create type public.delivery_event as enum ('strike_swap', 'retirement');

alter table public.deliveries add column event_kind public.delivery_event;
alter table public.deliveries alter column bowler_id drop not null;

-- event rows carry no runs/extras; real balls always name a bowler
alter table public.deliveries add constraint deliveries_event_rows_zero check (
  event_kind is null or (
    runs_off_bat = 0 and extra_wides = 0 and extra_no_ball_penalty = 0
    and extra_byes = 0 and extra_leg_byes = 0 and extra_penalty = 0
    and is_overthrow = false and bowler_id is null
  )
);
alter table public.deliveries add constraint deliveries_bowler_required check (
  bowler_id is not null or event_kind is not null
);
-- a swap is just a swap; a retirement event must say who left and how
alter table public.deliveries add constraint deliveries_event_wicket_shape check (
  event_kind is distinct from 'strike_swap' or wicket_type is null
);
alter table public.deliveries add constraint deliveries_retirement_shape check (
  event_kind is distinct from 'retirement'
  or (wicket_type in ('retired_out', 'retired_not_out', 'timed_out')
      and dismissed_player_id is not null)
);

-- is_legal now means "a legal DELIVERY was bowled": event rows are never legal
-- balls. Generated expressions cannot be altered in place - drop + re-add.
alter table public.deliveries drop column is_legal;
alter table public.deliveries add column is_legal boolean generated always as (
  extra_wides = 0 and extra_no_ball_penalty = 0 and event_kind is null
) stored;
