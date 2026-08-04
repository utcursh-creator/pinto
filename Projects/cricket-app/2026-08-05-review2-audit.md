---
type: audit
date: 2026-08-05
project: cricket-app
status: in-progress
---

# Review #2: per-finding audit of all 87

The findings doc's confirmed/refuted split was LOST (header says ~35 of 87 were
confirmed). I had been working from a mental subset and wrongly reported the
list as complete. This is the systematic pass over all 87.

CLOSED = fixed this run with a proven-RED test, commit named.
REFUTED = re-verified against the code and found not to hold.
USER = blocked on a credential or action only the user can take.
OPEN = still to do.

## CLOSED (45)
1 CRITICAL deleted account claimable ......... pgTAP 121 (earlier run)
2 CRITICAL gradle configuration-time guard ... build.gradle.kts (earlier run)
3 CRITICAL console innings-state no retry .... 3c27925
5 CRITICAL insert_ball 2 broadcasts .......... 18bae73 (measured 71, not 2)
6 CRITICAL matches INSERT owner-only ......... 7f96525
7 HIGH block stops replies .................. 553d6d3
12 HIGH ball-log cannot clear a wicket ....... 565b557
13 HIGH bowler picker raw vs effective cap ... 3004ed6
14 HIGH console clears bowler on 1st-ball wide 80adbb6
16 HIGH sole captain deletion freezes team ... earlier run
17 HIGH failed loads render as empty state ... 2a67a21
19 HIGH match viewer no re-sync .............. 0ed439d
20 HIGH search unanchored ILIKE, no trigram .. 5b683c3
21 HIGH watch-live seq-scan, no limit ........ 5b683c3
22 HIGH onboarding gate misses pushed sign-in  earlier run
23 HIGH console no error branch .............. 3c27925 / 63f87f3
24 HIGH turning Wicket off is a no-op ........ 565b557
26 HIGH auth_gate_reload_test re-implements .. earlier run
27 HIGH delete_my_account no captain guard ... earlier run
29 HIGH career stats scan match_squad ........ 5b683c3
30 HIGH respond_join_request silent fail ..... b6a4640
31 HIGH respond_join_request no revive ....... b6a4640
33 MED failed search cached forever .......... 68575f4
35 MED deletion keeps DM bodies .............. 53b45f1
36 MED tournament orphaned on organizer del .. c926bb4
37 MED android auto-backup .................. a50adc7
38 MED (duplicate of 37) .................... a50adc7
42 MED ball-log delete strands bowler ........ 42d0f89
46 MED tournament join code not sanitised .... 480f765
47 MED raw exceptions at the scorer .......... 63f87f3
48 MED raw exceptions, eight sites ........... 63f87f3 + sweep
51 MED no dismissal off a wide/no-ball ....... d734bc4
52 MED uploaded photos never deleted ......... 53b45f1
56 MED delete_match guard bypassable ......... e26294f
57 MED (duplicate of 1) ..................... earlier run
58 MED discover_posts no LIMIT ............... 526fcb4
59 MED (duplicate of 5) ..................... 18bae73
60 MED matches no team_a/team_b index ........ 5b683c3
63 MED post_replies globally readable ........ 42ed763
64 MED searchProvider not autoDispose ........ 68575f4
70 LOW home-location failure pins fallback ... 9b20c9e
71 LOW claim approval no roster refresh ...... 2e3b3fd
72 LOW no-ball byes not charged to bowler .... f5b94ea
74 LOW DM thread unbounded ................... 5b683c3
75 LOW no errorBuilder ....................... 2e3b3fd
77 LOW innings-break write swallowed ......... c9bd9c3
78 LOW console raw exception ................. 63f87f3
79 LOW +5 penalty always to batting side ..... 5be66be
80 LOW crossed ignored for obstructing ....... 4b0fb14
82 LOW toss error names missing control ...... 2e3b3fd
83 LOW tournaments list unbounded ............ 5b683c3
84 LOW viewer wagon never updates ............ 0ed439d
85 LOW last-pair retirement strands batter ... 61aff0c
67 MED NRR ignored balls_per_over ........... (this commit)
86 LOW (duplicate of 64) .................... 68575f4

67 MED tournament_standings NRR hardcoded /6.0 .. 2c94aba
32 MED dev-credentials test was self-referential  (test integrity)
50 MED no-ball enum lock tested its own copy .... (test integrity)
69 LOW recordBall params: tearoff non-null ...... (test integrity)
81 LOW location oracle passed on an empty result  (test integrity)
18 HIGH journey G group split ............... already fixed; screenshot proves it
45 MED journey D Undo asserted nothing ...... 79b16c4
53 MED oversized squad silently changes format 60184df
62 MED image URLs were arbitrary client strings aff06c9
61 MED status stuck at innings_break ......... 6223e6e
54 MED a departed guest could never be re-added .. 24022fb
15 HIGH DM inbox downloaded every message body ... 38f24ea
41 MED DM thread never re-synced after a socket gap 38f24ea
10 HIGH un-ticking a squad member never removed him (this commit)
25 HIGH the same, on a resumed setup ............ (this commit)
9  HIGH 'Add my team' offered teams it could not add (this commit)
11 HIGH AuthGate.error tore down the whole nav stack (this commit)

## REFUTED on re-verification
28 HIGH edit_ball/insert_ball accept impossible dismissals
   -> record_ball ALREADY validates both guards correctly; pgTAP 125 pins the
      uncovered half (that the FOLD counts them right).

## USER-ONLY
4 CRITICAL iOS reversed-client-ID URL scheme
   -> needs GOOGLE_IOS_CLIENT_ID. The dead-end half IS fixed: the Google button
      is hidden unless SupabaseEnv.googleConfigured.

## DEFERRED with a reason
40 MED  DM inbox opens one realtime channel per thread
   -> CONFIRMED: dm_inbox_screen listens per visible thread and each listener
      invalidates the WHOLE inbox. Fixing it properly needs a per-user realtime
      topic (a `user:<id>` channel the DM trigger also broadcasts to), which is
      a backend design change, not a client tidy-up. Left open deliberately
      rather than papered over; the cost is one socket join per conversation on
      screen, not incorrect data.

## OPEN - still to do
8  HIGH  reset-password link cannot re-enter the app
34 MED   abandoning a match refreshes only myMatchesProvider
39 MED   async error branches offer no retry while providers cache
43 MED   expired posts still read 'open' to their author
44 MED   GPS lookup has no time limit
49 MED   'Propose a match' bridge silently drops the notification DM
55 MED   anchorProvider survives sign-out
65 MED   tournament_leaderboard materialises a big join
66 MED   tournament_overview folds every innings three times
68 LOW   'Share image' can fail with no message
73 LOW   claim inbox evaluates is_team_admin per row
76 LOW   handover leaves a stale "Continue scoring" that always fails
87 LOW   tournamentsListProvider never refreshed after a status change
