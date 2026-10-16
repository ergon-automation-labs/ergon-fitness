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
  -> {"rotation": {"length": 4, "position": 1, "days_trained": 5, "date": "2026-10-16"},
      "session": {"value": "pull_a", "label": "Pull A — width first",
                  "groups": [...], "slots": [{"slot": "a press", "sets": 3,
                    "works": [...], "recent": "lat_pulldown",
                    "movements": [{"value": ..., "label": ..., "measure": ...,
                                   "min": ..., "max": ..., "last": ...,
                                   "next": {...} | "top" | null}]}]}}
```

* the rotation turns on the **calendar**, not on training days: `position/1` is
  `Integer.mod(Date.diff(date, @rotation_anchor), 4)` with the anchor at `2026-01-01`, so a
  missed week does **not** hand her the same session twice — the session she owes herself is
  today's session, and `fitness.coach.today` answers what today holds. `Integer.mod/2` and not
  `rem/2`: `rem(-1, 4)` is `-1`, and `Enum.at(list, -1)` would silently read the *last*
  session. A date that is not a `Date` answers `nil` rather than session one;
* `days_trained` is still counted and still sent — she has trained it, and a card may say so —
  but it decides nothing. `Scheduler.training_days/0` counts distinct days across both logs (a
  day with three sets is one day), and a failed read is an error, never a shorter history;
  it is a **hard prerequisite** of the answer: a day count that cannot be read is `read_failed`,
  never a session;
* the day is read **once per answer** (`HouseholdDay.today/0` in `CoachTodayHandler`) and every
  field is built from that one value, and the reply says which day it answered for in
  `rotation.date`. Reading the clock again beside each field could name one day and send the
  session of another;
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

### The day is the house's day, not UTC's

`BotArmyFitness.HouseholdDay` is the bot's one answer to "what day is it" — today it is
`:calendar.local_time()`, the host's own zone, read through `HouseholdDay.today/0` (the boot log
prints it beside its offset: `Fitness bot day: 2026-10-16 (local offset -6h from UTC)`). Every
`Date.utc_today/0` in `lib/` was replaced by it: a bot that stamped 18:00 MDT on tomorrow's date
would disagree with her about what "today" means for six hours every evening, and two conventions
in one bot is a defect rather than a nuance. A test in `household_day_test.exs` searches `lib/` for
the paren form and fails if any file — including `household_day.ex` itself — still asks the UTC
clock this question. The day is read once per answer; a handler that read it per field could name
one day and send the session of another. The fleet carries no IANA database on purpose: the
`tzdata` dependency, its compile-time download and a compile-time zone database config are a
heavier trade than an offset the runtime host already knows. The residual risk is honest and
small — if one instance of this bot ran outside the household's zone, the queue group would
balance presses between two bots that disagree about the date for part of the day; the boot log
is what makes that discoverable.

`fitness.coach.last` is a read of her **log**, not of the method — the third question the
Fitness tab asks, and one no list could answer, because `fitness.set.list`'s page is ten
while a session can be eighteen sets. It answers the newest day she trained and the last
set of each distinct movement on it, last-touched order, as **values only**:

```
fitness.coach.last   {}
  -> {"day": "2026-10-14", "count": 2,
      "movements": [{"value": "kb_swing", "measure": "reps", "amount": 12,
                     "load_kind": "kg", "load_value": 24.5},
                    {"value": "pull_up", "measure": "reps", "amount": 8,
                     "load_kind": "bodyweight", "load_value": null}]}
```

* the day is the one **the bot found** (`WorkoutSetStore.recent_day/1`), never a date a
  surface picked out of a page of rows, and no history is an answer —
  `{"day": null, "movements": [], "count": 0}` — rather than a failure;
* a store that cannot be read is `read_failed`, never an empty day: `fitness.coach.last`
  is a subject of its own **because** a log that could not be read must be a refusal rather
  than an empty coach beside it;
* the read carries **no vocabulary**: `value`, `measure`, `amount`, `load_kind`,
  `load_value` and nothing else, so a surface resolves the label and the piece from the
  catalog it already holds. It chooses nothing for her (§ the coach rule) and it stages
  nothing;
* `recent_day/1` is **two bounded queries** — the newest date, then that day's rows — so
  the answer cannot grow with the log and a page limit cannot cut a session in half.

`fitness.coach.chat` is the last of the tab's questions and the only one that is not a read of a
store: she asks about the gym or the method in her own words, and the **bot** answers. The surface
sends one thing — `{"message": "..."}` — and draws the one thing it gets back; it never talks to
the LLM bot, holds no copy of the gym, and knows no rule about what may be said. Three parts of
this bot keep the rule the coach rule states:

* **the grounding is built here**, in `BotArmyFitness.CoachChat` (pure): the `system_prompt/0`
  says in words that the model must not choose a session or a movement for her, must not set a
  number for her, and must not keep streaks or scores; `prompt/2` carries the gym (every piece,
  every area, every movement, with the note that the MaxPRO has a wall attachment but is set up on
  the floor most of the time **without** it), today's session and her last session, and her
  question last;
* **a failed read is said as a failed read** — `CoachChatHandler.context/1` never omits a read it
  could not make: `today: nil`, `days_trained: nil` and `last: :unreadable` each become an
  explicit "could not be read just now — do not say what it is" line in the prompt, so a hiccup
  cannot become "you have kept nothing";
* **the answer is text and nothing else** — the reply is `{"ok": true, "data": {"response":
  "..."}}`, the same envelope as every other read, and it carries no `stage`, no `offer` and no
  movement. Staging already belongs to the two reads above it (§53), and a chat that could put a
  movement in front of her would be a second, unbounded way to choose for her.

```
fitness.coach.chat   {"message": "what does the cable row work?"}
  -> {"ok": true, "data": {"response": "The cable row is a back movement. Start light."}}
```

* an empty or missing `message` is refused in the bot's own words (`missing_message`), and a
  model that does not answer, times out or answers with something that is not words is
  `llm_failed` — never a blank answer;
* one owner reads an LLM reply: `BotArmyFitness.LlmReply` (`text/1`, `decode/1`, `read/1`),
  shared with `fitness.chat`;
* the consumer **`spawn`s** the handler, because the hop to the LLM bot is seconds long and the
  fitness subscriptions must not queue behind one question. `fitness.chat` still runs
  synchronously — the same wart, left for later;
* **a slow local model is answered, not lost.** The question goes to `llm.prompt.submit` first —
  the general local model, twenty seconds (`@llm_timeout_ms`, against the persona's eight: a
  grounded question is a bigger ask than a one-line reply) — and a hop that fails or outlives
  is handed to `BotArmyFitness.CoachJob` as a **backgrounded job** on the llm bot
  (`llm.request.chat`, `"async" => true`, `model_type: "uncensored"`: the type whose promise is "a
  local model, never a cloud provider", which is the promise her log needs). The job is waited
  *on*, not *for* — `BotArmyFitness.JobBell` wakes the waiter when the llm bot rings
  `events.llm.job.completed`, and the words are then **read** from `llm.job.status`. A bell is a
  wake-up and never a proof (one that arrives before the result is stored, or on the other node's
  queue-group member, must not be mistaken for the answer), and a bell that never comes is
  survivable by design: the wait still polls, so an llm bot older than the async path behaves as
  it did before. The budget is **fifteen minutes** (`FITNESS_COACH_JOB_BUDGET_MS`, operator-tunable
  without a release) and it is a net for a *wedged* job rather than a guess at how long a model may
  think: a slow local answer is waited for, not thrown away. The panel's `@coach_timeout_ms` sits
  above the whole two-lane budget. The wire is unchanged: an answer is still an answer and a failure is
  still `llm_failed`.

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
