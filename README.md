# BotArmyFitness

Fitness and wellness bot implementation for the Bot Army ecosystem.

Manages workout tracking, exercise data collection, and fitness goal monitoring.

## Building

```bash
mix deps.get
mix test
```

## Running

```bash
iex -S mix
```

## Architecture

- **NATS Consumer** - Listens for fitness-related messages
- **Workout Tracker** - Records and tracks workout sessions
- **Goal Monitor** - Monitors progress toward fitness goals

## Message Schemas

Schemas are defined in `bot_army_schemas_fitness` and deployed to `/etc/bot_army/schemas/fitness/`

## The home gym

Her gym is a real one, and the bot is the only place it is written down:
`BotArmyFitness.ExerciseCatalog` holds the equipment (`maxpro`, `dumbbells`,
`kettlebell`, `dip_bars`, `pull_up_bar`), what a number means on each piece
(`kg`, the device's own `level`, or `bodyweight`), and the movements it makes
possible. `fitness.workout.options` publishes all of it, so a surface draws the
gym without keeping a copy — and when a setting changes, it changes in one file.

A movement is **not** a workout. `fitness.workout.log` asks how long and how
hard; that vocabulary is length × hardness, and no column in `workouts` can say
"24.5 kg for 12" — which is the only sentence a progression is made of. So a set
has its own verb and its own table:

```
fitness.set.record   {"exercise": "kb_swing", "amount": 12, "load": 24.5}
                     -> {"set": {...}, "previous": {...}|null, "next": {...}|"top"|null}
fitness.set.list     {"limit": 10}
                     -> {"sets": [...], "count": n, "limit": n}
```

* the bot derives `measure` (`reps` | `seconds`) and `load_kind` from the
  catalog — a caller describing the movement would be guessing at the gym;
* a load that is not a setting the equipment really has is **refused**
  (`load_not_on_ladder`), never rounded — rounding records a set that never
  happened, and the next read builds a progression on a weight that is not in
  the room;
* an absent load is a fact, not a missing field: a bodyweight movement's absent
  number means the body alone, and one with no load still records its reps;
* the reply carries `previous` — the newest set that is **not** the one just
  kept — so a surface can say "last time" without slicing a history itself, and a
  day logged in the past cannot make the card point at the set she is looking at;
* the same reply carries `next`, from `BotArmyFitness.Progression` — one rung up
  when the count has topped the movement's own window, one more rep when it has
  not, `"top"` when there is no higher number on the piece, and `null` when the
  rule declines to guess (a hold, an unknown movement, a laddered piece with no
  load recorded). A suggestion is not a row: it carries no id and above all no
  date;
* both lines come from **one** read of the movement's newest rows, taken after
  the insert. That read is ordered by the day she did the set, so the row just
  kept is not always at its head: `previous` names the newest row that is not the
  one just kept, `next` follows the head — her latest real set, when the day
  logged was in the past — and each line names the row it is about;
* `fitness.set.list` is the read those rows never had. Unlike
  `fitness.workout.list`, a store that cannot answer is a refusal
  (`read_failed`) and not an empty list — "she has logged nothing" and "the log
  could not be read" are different sentences.

A set counts as training: `Scheduler.days_since_last_workout/0` reads the newest
day from the workout log **and** the set log, and a failed read is an error, never
a shorter history. Both logs are read newest-day-first, so a set she backfills for
an older day does not become "last time" — and does not make today look trained.

## What a movement works, and the coach

A movement is not a muscle either. `ExerciseCatalog` carries a **fixed vocabulary of
eighteen groups** and every movement says what it is for (`"main"`) and what comes
along (`"also"`) in those words — because "rear delts", "rear shoulders" and
"posterior deltoid" are one group spelled three ways, and a coverage question asked
in three vocabularies cannot be answered. `groups/0`, `group_label/1`,
`exercises_for_group/1`, `works?/2` and the two receipt functions
(`uncovered_groups/0`, `groups_without_a_primary_mover/0`) publish it. No group is
left unreached by the menu; the lower back and the hip flexors are worked here and
**never led with**, because a movement that leads with either needs equipment this
house does not own, so the list is reported rather than padded away.

Eighteen exact groups make a truthful vocabulary and a poor picker, so `ExerciseCatalog`
also carries a **six-area layer** — `chest`, `shoulders`, `back`, `arms`, `core`, `legs` —
and the partition is **exact**: every group belongs to exactly one area, so a movement
filtered by an area is never also filtered out by a neighbouring one. `area_options/0`,
`groups_for_area/1` and `area_for_group/1` publish it, and `fitness.workout.options`
sends `"areas"` beside the gym and each movement's own `"muscles"`, so a surface can
offer *pick the body part, then the movement* without a copy of the mapping. An area
filter is against a movement's `"main"` groups only — a movement that merely comes along
on a group is not one she would press for that area.

`BotArmyFitness.Coach` is the method — and it is **pure**: no store, no clock. Four
sessions (`push_a`, `pull_a`, `push_b`, `pull_b`), six slots each, every slot naming
what it is there to work and offering the movements that fit:

```
fitness.coach.today   {}
  -> {"rotation": {"length": 4, "position": 1, "days_trained": 5},
      "session": {"value": "pull_a", "label": "Pull A — width first",
                  "groups": [...], "slots": [{"slot": "a press", "sets": 3,
                    "works": [...], "recent": "lat_pulldown",
                    "movements": [{"value": ..., "label": ..., "measure": ...,
                                   "min": ..., "max": ..., "last": ...,
                                   "next": {...} | "top" | null}]}]}}
```

* the rotation turns on **training days**, not the calendar: `rem(days_trained, 4)`,
  so a missed week does not skip a session. `Scheduler.training_days/0` counts
  distinct days across both logs — a day with three sets is one day — and a failed
  read is an error, never a shorter history;
* nothing is chosen for her. Every movement a slot offers travels with **her own**
  `next` number, straight from `Progression.next_load/1`, and the one movement named
  in `recent` is a fact read back from her log rather than a pick. Ties keep the
  slot's order, so the same log always names the same movement;
* a read that fails is `read_failed`, never a session: a coach that answered "Push A"
  because a database hiccup looked like a fresh log would be inventing a training
  decision;
* the menu is broader than the method on purpose — `dip_hold_top` is in the menu and
  in no session. The bound that matters is the **session** (six slots, so a card stays
  something a person can hold), not the menu, and the free picker stays the escape
  hatch;
* `fitness.workout.today` still answers, and is **superseded**: it names a workout
  *type* from a hash of the user id and the day of the year, and no movement.

A note on the two nodes: air and mini each keep their **own** `ergon_fitness`
database (measured 2026-10-14: air held 1 workout, mini held 0). Mini's copy is a
standby that starts empty, so a failover to mini loses her history until the data
is copied over: `make migrate-live-db-to-mini BOT=fitness` from `bot_army_infra`.

`fitness.set.log` is a different thing and stays that way — it is a comfort
calibration (`reps_achieved` vs `reps_target` into
`PersonalExerciseStore.update_comfort/5`), written by the Go fitness TUI.

## Dependencies

- `bot_army_core` - Core NATS decoder and envelope handling
- `nats` - NATS client library
- `jason` - JSON encoding/decoding
- `logger_json` - JSON logging

## Development

```bash
make setup    # Install dependencies
make test     # Run tests
make check    # Run all checks
```

## Related Repositories

- `bot_army_schemas_fitness` - Fitness message schemas
- `bot_army_core` - Core library
- `bot_army_infra` - Deployment infrastructure
