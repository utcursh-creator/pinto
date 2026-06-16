begin;
select plan(5);
select has_type('public','lf_mode','lf_mode enum');
select has_type('public','lf_status','lf_status enum');
select has_type('public','skill_level','skill_level enum');
select has_table('public','looking_for_posts','posts table');
select has_index('public','looking_for_posts','looking_for_posts_geog_idx','geog GiST index');
select * from finish();
rollback;
