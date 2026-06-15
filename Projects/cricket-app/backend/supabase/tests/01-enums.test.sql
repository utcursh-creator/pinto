begin;
select plan(5);
select has_type('public', 'batting_style', 'batting_style enum exists');
select has_type('public', 'playing_role', 'playing_role enum exists');
select has_type('public', 'team_member_role', 'team_member_role enum exists');
select has_type('public', 'invite_status', 'invite_status enum exists');
select has_type('public', 'claim_status', 'claim_status enum exists');
select * from finish();
rollback;
