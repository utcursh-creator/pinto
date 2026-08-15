---
type: design
date: 2026-08-05
project: cricket-app
status: active
tags: [journeys, testing, scoring, pitch]
---

# How somebody actually uses Pitch

Written because the user rejected the test approach, correctly: every "user
journey" in `integration_test/user_journeys_test.dart` creates BOTH teams from
one account, so the setup flow has never been walked the way it is really met.
The scripts were green while the app stopped him on his first real attempt.

The rule this document exists to enforce: **a journey is only evidence if its
SETUP is how the situation actually arises for a user.** If the test has to
build a world no user could build, it is testing the fixture.

---

## 1. Who is holding the phone

Weekend/gully cricket in India. One person - the organiser of one side - does
almost everything: rounds up players, finds an opposition, and then scores the
match one-handed at the boundary while people shout at him. He is not a
statistician. He is busy, standing up, and often on one bar of signal.

Three roles, usually the same person:

| Role | What they want |
|---|---|
| **Organiser** | eleven players, an opponent, a ground, a time |
| **Scorer** | one tap per ball, no interruptions, correct total |
| **Sharer** | a scorecard link that opens for people with no account |

Everyone else - the other ten players, the opposition, friends watching - are
**passive**. They may never install the app. Any flow that requires them to is
a flow that does not happen.

---

## 2. Day one, the honest version

This is the case the tests never modelled:

```
installs the app
  -> browses Discover anonymously            [works]
  -> signs up                                [works]
  -> creates ONE team, adds guests by name   [works]
  -> wants to score Sunday's game
       ...against a team that IS NOT ON PITCH.
```

**Nobody's opponent is on Pitch on day one.** That is not an edge case, it is
the default for every single new user until the app has a network in their city.

Today `start_match_screen` requires the opponent to be an existing team: the
picker is a search over `teams`. There is no "they're not on Pitch, they're just
Sharma's XI" path. So the only way through is to create a second team you do not
own and will never use again - which is exactly what the user hit, and exactly
what every journey in the repo quietly did on his behalf.

**GAP 1 (design, not a code defect): no ad-hoc opponent.** The fix is a named
opponent that is not a real team, or a "quick opponent" that creates a
lightweight team owned by nobody. This needs a product decision, not a patch.

---

## 3. Scoring a ball - the loop that matters most

The scorer does this ~120 times per innings, standing up, under time pressure.
Everything here is judged on **taps per ball** and **interruptions per ball**.

What actually happens on a delivery, in rough order of frequency:

| Outcome | Frequency in gully cricket | Ideal taps |
|---|---|---|
| **dot ball** | the single most common outcome | 1 |
| 1, 2, 3 runs | very common | 1 |
| 4 / 6 | common | 1 (+ optional placement) |
| wide | common - loose bowling | 2 |
| no-ball | common | 2 |
| wicket | ~10 per innings | 2-3 |
| bye/leg-bye | occasional | 2 |

**GAP 2 (real defect, reproduced): the wagon-wheel sheet opens on a DOT BALL.**
`record_ball` computes:

```sql
wagon_applicable := _extra_wides = 0 and _extra_byes = 0 and _extra_leg_byes = 0
  and (_noball_secondary_kind is null or _noball_secondary_kind = 'off_bat')
  and (_wicket_type is null or _wicket_type in ('caught','run_out'));
```

It never asks whether any runs were scored. So a dot ball returns true and the
console opens "Where did 0 run(s) go?". Measured: a plain dot returns
`wagon_applicable = t`.

On the most common outcome in the game, the scorer gets a modal asking where a
ball that went nowhere went. That is the "dot ball, something weird happens"
report, and it is why the existing journeys had to grow a `scoreRuns()` helper
that dismisses a sheet after every single run tap - the test worked around the
defect instead of reporting it.

A wagon entry is meaningful for runs off the bat and for a catch (where the
ball went). It is meaningless for a dot.

---

## 4. Wides and no-balls - what the scorer believes

The convention the app implements is correct: a wide is 1 penalty plus any runs
the batters ran, all recorded as wides; the console sends `wides: 1 + runs`, and
the sheet says "Extra runs run off the wide (the wide itself counts 1)".
Measured against the fold: wide -> +1 and no legal ball; no-ball -> +1 and free
hit; wide + 2 byes run -> +3. All correct.

**So the engine is right and the wording is right.** If the number on screen
still surprises a scorer, the remaining suspects are, in order:

1. the stepper's default and what a fast tap does (does opening the sheet and
   hitting Record immediately give a plain wide, or nothing?)
2. whether the *displayed* total updates before the next ball is entered
3. whether "+1"/"+2" chips exist elsewhere that add on top of the penalty

These are questions about the SCREEN, and they need the screen, not the schema.
Unresolved - and not to be written up as fixed until reproduced.

---

## 5. The journey map

Each row is a state a real user reaches, and the action that leaves it. Tests
derive from THIS, not from review findings.

| # | State | User's intent | Leaves by | Modelled today? |
|---|---|---|---|---|
| A1 | fresh install, anonymous | "is anything happening near me?" | browses Discover | yes |
| A2 | anonymous, wants to act | "I want to post/reply" | signs up | yes |
| A3 | signed up, no team | "put my side in" | creates team + guests | yes |
| **B1** | **one team, opponent NOT on Pitch** | **"score Sunday's game"** | **no path** | **NO - GAP 1** |
| B2 | one team, opponent IS on Pitch | "score Sunday's game" | opponent search | partly |
| B3 | squads screen | "pick my XI and theirs" | add guests to both sides | untested for a stranger's team |
| B4 | toss | "we won, batting" | toss + openers | yes |
| **C1** | **console, every ball** | **"record what happened, fast"** | **run pad** | **yes, but GAP 2 on dots** |
| C2 | console, wide/no-ball | "extras" | extras sheet | yes |
| C3 | console, wicket | "he's out" | wicket sheet | yes |
| C4 | console, mistake made | "undo/correct that" | ball log | yes |
| C5 | innings break | "swap sides" | second innings | yes |
| D1 | match over | "send it round" | share card / /watch link | yes |
| D2 | friend opens link, no account | "just show me the score" | login-free viewer | yes |

---

## 6. What to test, in the order it hurts

1. **B1 - the day-one wall.** Until it has an answer, every new user is stopped.
2. **C1 - one tap per dot ball.** ~70 of 120 deliveries.
3. **B3 - filling a stranger's XI.** The backend allows it
   (`add_match_guest` is gated on `is_match_scorer`, not team admin); nothing has
   ever driven it.
4. C2 - the extras sheet, driven on a device, watching the number change.

Rules for these tests, learned the hard way:
- ONE account creates ONE team. If a journey needs a second team, it must arrive
  the way it would in life, or the journey is invalid.
- Screenshot the score after every ball and READ it. An assertion I wrote about
  behaviour I wrote is not independent evidence.
- Run the mutation. A journey that passes against the broken build is not a test.
