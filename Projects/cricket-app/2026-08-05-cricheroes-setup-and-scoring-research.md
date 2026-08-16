---
type: research
date: 2026-08-05
project: cricket-app
status: active
tags: [cricheroes, competitive, scoring, setup, pitch]
---

# How CricHeroes solves the two things we got wrong

Written because the user asked: *"How does CricHeroes do it? The type of
research and thought they have given, you need to map it out."*

Scope: the two gaps the journey map exposed - **the day-one opponent** and **the
per-ball scoring loop**. Sourced, not remembered.

## Confidence, stated up front

| Claim | Source | Confidence |
|---|---|---|
| Teams can be created inline while starting a match | CricHeroes blog (friendly match) | HIGH - stated directly |
| Creating a team needs only name + location, logo optional | CricHeroes blog | HIGH |
| Scoring pad is 0/1/2/3/4/6 plus separate Wide / No ball / Bye / Leg Bye | CricHeroes blog + store listing | MEDIUM-HIGH |
| A delivery's TYPE can be corrected after the fact | CricHeroes blog (edit scorecards) | MEDIUM-HIGH |
| Wagon wheel is an opt-in SETTING, and plotting dot balls is a further option inside it | **CricHQ** support docs, not CricHeroes | MEDIUM - a competitor, cited honestly |
| Exact tap counts / screen layout | none - their FAQ and scoring blog both 403 to automated fetch | **NOT VERIFIED** |

I could not walk their app. Anything below marked NOT VERIFIED should be
checked by installing CricHeroes and scoring two overs before we copy it.

---

## 1. The day-one opponent - they simply let you make the team there

Our GAP 1: `start_match_screen` requires the opponent to already exist as a team
on Pitch. On day one nobody's opponent is on Pitch, so the user is forced to
create a second team he does not own and will never use - which is exactly what
he hit, and what every one of our journeys silently did for him.

CricHeroes does not treat "opponent" as a lookup at all. In their friendly-match
flow you **choose the teams participating, and you can either create your teams
or select from existing ones**. Creating one asks for **team name, location, and
an optional logo** - then you add players immediately.

The thinking behind that, which is what the user asked me to map:

- **A team is cheap.** It is a name and a place. It is not an account, not a
  roster of registered users, not a social object that must be claimed. That
  makes it safe to create one mid-flow for an opponent who will never install
  anything.
- **The scorer is the only user who has to exist.** Everyone else - the whole
  opposition, most of your own side - are names typed by the scorer. The app
  works at full value with exactly one real account.
- **Creation happens where the need appears.** Not "go to Teams, make a team,
  come back". The need arises inside Start A Match, so the escape hatch lives
  inside Start A Match.

### What we should do

Add **"Create a team"** directly to the opponent picker sheet - same fields we
already have (name, city), same `create_team` RPC, and on success select it as
the opponent and continue. No schema change, no new concept, and it removes the
day-one wall.

Deliberately NOT doing: a nameless "ad-hoc opponent" that is not a team. It
would need its own type everywhere a team id is expected (squads, scorecards,
stats, standings), and it would break the thing that makes the product worth
using later - that Sharma's XI, typed once by somebody's mate, is a real club
page the day they install.

Open question for the user: should a team created this way be **owned** by the
creator (appears in My teams, he can edit it), or ownerless so the real club can
claim it later? CricHeroes' answer is not visible from outside. My
recommendation: owned, because ownership is what lets him fix the spelling, and
we already have `request_guest_claim` as the hand-over path.

---

## 2. The per-ball loop - and why our dot ball was wrong

Their pad: **0, 1, 2, 3, 4, 6** as direct buttons, with **Wide, No ball, Bye,
Leg Bye** as separate extras controls, plus **UNDO**, **change strike**, and the
ability to **correct a delivery's type afterwards** (a ball wrongly marked wide,
no-ball or dot can be changed).

Three principles fall out of that, and we violated the second one:

**(a) The common case is one tap.** 0/1/2/3/4/6 are all a single press. Nothing
is nested behind a menu. Ours matches this.

**(b) Nothing interrupts the common case.** This is where we were wrong.
`wagon_applicable` never checked whether runs were scored, so a dot ball opened
"Where did 0 run(s) go?" - a modal on roughly two balls in three. Fixed today
(pgTAP 157, migration 20260805240000).

The competitor evidence is stronger than "it felt wrong": in **CricHQ**, the
wagon wheel is a **setting you turn on**, and plotting **dot balls** is a further
option inside that setting. Nobody ships placement capture as mandatory, and
nobody makes dot-ball plotting the default.

So the fix we shipped is the floor, not the ceiling. The right end state:

- wagon capture is a **scorer preference**, off by default for a casual match;
- when on, it applies to scoring shots;
- dot-ball plotting is a **separate** opt-in for the analytics-minded.

**(c) Every ball is correctable, including its TYPE.** They let you re-mark a
delivery as wide / no-ball / dot after the fact. We have a ball-log editor with
edit and insert, and as of today the run-out `crossed` flag - so we are close.
Worth checking that changing a delivery's KIND (dot -> wide) is reachable in our
editor with the same ease.

---

## 3. Wides and no-balls - we match the convention

Measured against our fold: wide -> +1 and not a legal ball; no-ball -> +1 with
free hit; wide with 2 byes run -> +3. The console sends `wides: 1 + runs`, and
the sheet reads "Extra runs run off the wide (the wide itself counts 1)".

That is the standard convention and it agrees with how CricHeroes describes
entering "Wide Ball, No Ball, Bye and Leg Bye runs" as extras.

**So the arithmetic is not the defect.** If the number still looks wrong on the
screen, the remaining suspects are all UI, in order: what one fast tap on Wide
does before the stepper is touched; whether the total on screen updates before
the next ball; and whether the sheet's default of 0 reads as "no runs" or as
"nothing entered yet". NOT VERIFIED - needs the screen and the user's taps.

---

## 4. What this changes in the journey map

| Map ref | Was | Now |
|---|---|---|
| B1 day-one opponent | GAP, no path | **DONE** 6c4ada4 - Create "<typed name>" in the opponent sheet, selects it |
| C1 dot ball | modal on ~2 balls in 3 | **DONE** e32a04a (floor) + 29e149f/1573515/7195137 (the ceiling: account-level prefs, off by default, dot plotting a separate opt-in, toggles on Settings) |
| C2 wide/no-ball | suspected wrong | **SETTLED 2026-08-05 - REAL DEFECT.** Not arithmetic. The pad's `Wd`/`Nb` record a delivery IMMEDIATELY, so the natural gesture (tap Wd, then tap 2) writes TWO deliveries: runs 3, legal_balls 1, over 0.1 - versus the correct single delivery, runs 3, legal_balls 0, over 0.0. Same total, which is why every arithmetic check passed; but a legal ball that never happened is consumed and the over ends a ball early. FIX: make wide/no-ball a MODIFIER that arms, then the run button writes one delivery |
| C4 corrections | edit/insert/crossed | **VERIFIED, no fix needed** - the Delivery chips (Legal/Wide/No-ball) already exist. What was missing was a test that the choice REACHES the RPC; ball_log_test only asserted the chip existed. ball_log_change_kind_test now drives it; dropping `wides:` from the payload fails 2 |

## Sources

- [Create & Play Friendly Cricket Match with CricHeroes](https://blog.cricheroes.com/play-friendly-cricket-match-with-cricheroes/)
- [How to Score a Cricket Match with CricHeroes App](https://blog.cricheroes.com/how-to-score-a-cricket-match-with-cricheroes-app/)
- [How to Edit Scorecards in Live Matches on CricHeroes](https://blog.cricheroes.com/how-to-edit-scorecards-in-live-matches-on-cricheroes/)
- [CricHeroes on the App Store](https://apps.apple.com/in/app/cricheroes-cricket-scoring-app/id1222844050)
- [CricHQ - How do I use the wagon wheel?](https://support.crichq.com/hc/en-us/articles/216759108-How-do-I-use-the-wagon-wheel-) (competitor, cited for the wagon-wheel-as-setting evidence)
