# CLAUDE.md

Guidance for Claude Code when working with `bot_army_fitness`.

---

## Purpose

**bot_army_fitness** is the fitness and wellness bot implementation.

Handles:
- Workout session logging and tracking
- Exercise data collection
- Fitness goal management and monitoring
- Progress reporting and analytics

---

## File Organization

```
.
├── lib/
│   ├── bot_army_fitness.ex              # Main module
│   └── bot_army_fitness/
│       ├── application.ex                # Application supervisor
│       ├── nats/
│       │   └── consumer.ex               # NATS message consumer
│       └── handlers/
│           ├── workout_handler.ex
│           ├── exercise_handler.ex
│           └── goal_handler.ex
├── test/
│   ├── test_helper.exs
│   └── bot_army_fitness/
│       ├── nats/
│       │   └── consumer_test.exs
│       └── handlers/
│           └── workout_handler_test.exs
├── mix.exs
├── CLAUDE.md
└── README.md
```

---

## Core Dependencies

- **bot_army_core** - NATS envelope decoding, schema validation
- **nats** - NATS client for message publishing/subscribing
- **jason** - JSON encoding/decoding
- **logger_json** - Structured JSON logging

The bot depends on schemas deployed by `bot_army_schemas_fitness` at `/etc/bot_army/schemas/fitness/`

---

## Development Workflow

### Setup

```bash
mix deps.get
mix test
```

### Key Modules to Implement

1. **BotArmyFitness.NATS.Consumer** - Subscribe to NATS subjects
2. **BotArmyFitness.Handlers.WorkoutHandler** - Handle workout logging
3. **BotArmyFitness.Handlers.ExerciseHandler** - Manage exercise data
4. **BotArmyFitness.Handlers.GoalHandler** - Track fitness goals

### Message Subjects

The bot listens to and publishes:
- `fitness.workout.*` - Workout operations
- `fitness.set.record` - one set of one home-gym movement (load × reps). **Not**
  `fitness.set.log`, which is a comfort calibration
  (`reps_achieved`/`reps_target` → `PersonalExerciseStore.update_comfort/5`,
  written only by the Go fitness TUI). The movement's `measure` and its
  equipment's `load_kind` are derived from `ExerciseCatalog`, never sent by the
  caller; an off-ladder load is refused (`load_not_on_ladder`), not rounded. Its
  reply also carries `next` (`BotArmyFitness.Progression`), the set to reach for
  next, and `fitness.set.list` reads the recorded sets back.
- `fitness.graph.series` - Every graph this bot can draw from her log, in one reply: the days she
  trained, the sets she kept, the load trend, and the two cardio series, over twelve weeks
  (`Graphs.window_days/0` = 84), each with its own points, kind and unit. It draws nothing and counts
  nothing — the menu is the answer, and the page picks one. A store that cannot be read is
  `read_failed`, never a menu of empty series.
- `fitness.exercise.*` - Exercise operations
- `fitness.goal.*` - Goal tracking

All messages follow the core envelope structure from `bot_army_core`.

---

## Testing

```bash
mix test                    # Run all tests
mix test --cover            # With coverage
mix credo                   # Linting
mix dialyzer                # Static analysis
```

---

## Deployment

This bot is deployed via Salt from `bot_army_infra`:

```bash
cd ../bot_army_infra
make deploy-bot BOT=fitness
```

Deployment happens after:
1. Core schemas deployed
2. bot_army_core library deployed

---

## The rules this bot keeps

Seven of these are load-bearing; changing one silently changes coaching advice, so a change
here is a change to what her body is told to do:

1. **A movement is not a workout, and a set is not a workout log.** `fitness.workout.log`
   is length × hardness; a set is a load and a count and has its own verb, table and
   store (`fitness.set.record` / `fitness.set.list`).
2. **A load that is not a setting the equipment really has is refused, never rounded.**
   Rounding records a set that never happened and the next read builds a progression on a
   weight that is not in the room.
3. **The bot owns the vocabulary.** `ExerciseCatalog` holds the gym, the muscle groups,
   the **six broad areas** and the movements; a surface draws them and keeps no copy. The
   area partition is exact — every group belongs to exactly one area — so an area filter
   is unambiguous, and a surface filters on the movement `"muscles"` it is sent, never on
   a mapping of its own.
4. **A failed read is a refusal, never an empty history.** `read_failed` covers an
   unreadable set log, day count or history — "she has logged nothing" and "nobody could
   read the log" are different sentences, and only one of them is safe to print.
   `fitness.coach.last` answers her last session on a subject of its own for this reason:
   a log that could not be read is a refusal, never `{"day": null}`, and a surface that
   asked the coach's read for it would empty the method beside it when the log failed.
   `fitness.coach.chat` keeps the rule for a model: `CoachChatHandler.context/1` renders
   every read it could not make as an explicit "could not be read just now — do not say
   what it is" line, so no hiccup can be answered as "she has kept nothing".
5. **The coach is pure and chooses nothing for her.** `BotArmyFitness.Coach` reads no store
   and no clock; its rotation turns on the **calendar** — `position/1` is
   `Integer.mod(Date.diff(date, @rotation_anchor), 4)` around `2026-01-01`, so a missed week
   does not hand her the same session twice — and every movement travels with her own `next`
   number beside it. `recent` names a fact from her log, not a pick. Progression is
   `BotArmyFitness.Progression`'s — do not re-derive it here or on a surface. The chat keeps
   this rule too: its reply carries **text and no movement** — no `stage`, no `offer` — and
   `CoachChat.system_prompt/0` tells the model in words not to choose a session or a movement
   for her and not to set a number for her.
6. **`BotArmyFitness.HouseholdDay` is the only answer to "what day is it", and it is the
   host's day.** `Date.utc_today/0` must not appear under `lib/` — `household_day_test.exs`
   searches for it and fails. The bot's day and her clock then agree; a UTC day stamped at
   18:00 MDT would put her evening on tomorrow, and two conventions in one bot is a defect
   rather than a nuance. Read the day **once per answer** (`date = HouseholdDay.today()`), build
   every field from that one value, and send it — `rotation.date` says which day the answer is
   for, so a surface can label a card with the bot's day instead of its own. Do not add `tzdata`
   to learn an offset the runtime host already knows; the residual risk (an instance outside the
   household's zone) is made discoverable by the boot log line, not by a dependency.
7. **`fitness.workout.today` is superseded, not deleted.** It answers a workout *type*
   derived from a user-id hash and the day of the year. New callers want
   `fitness.coach.today`; do not grow the old plan a catalog.
8. **A slow model is waited for, and the fallback stays on this machine.** A question outlives
   its fast lane more often than it fails one, so `CoachChatHandler` hands it to
   `BotArmyFitness.CoachJob` rather than losing it: `llm.request.chat` with `"async" => true`, and
   `model_type: "uncensored"` — the only type whose promise is "a local model, never a cloud
   provider". Her log and the method are health-shaped facts; do not remove that field, and do not
   substitute a type that may reach the cloud. The wait is on the job, not for it:
   `BotArmyFitness.JobBell` is rung by the consumer on `events.llm.job.completed` and the words are
   read afterwards from `llm.job.status`, because a bell carries no words and is never a proof.
   The budget is `FITNESS_COACH_JOB_BUDGET_MS` (default fifteen minutes) and it is a net for a
   *wedged* job, not a guess at how long a model may think — a slow local answer is waited for. The
   panel's wait is sized above the whole two-lane budget, so shortening one without the other turns
   a slow answer into "did not reply".

9. **A graph is a picture of her log and never a score.** `BotArmyFitness.Graphs` answers the whole
   menu in one reply (`fitness.graph.series`) because which series exist, which weeks they cover and
   what a number means are facts about *this* gym; the page scales points into SVG and decides
   nothing. Two rules ride on it. **Nothing is normalised across pieces** — a MaxPRO resistance
   level out of 25 is not a smaller kilogram than a dumbbell, so a load is only ever plotted against
   itself, over time, on one movement, and the series names the movement and its unit; do not add a
   cross-movement "heaviest lift" chart or a volume figure. And **an empty series is a fact, sent
   with its own labels and zeros**, never a missing entry: a graph she could only discover by
   accident is worse than a menu with an empty row in it. A read that fails is `read_failed`, never
   a menu of empty series. Bounds are the bucket **count** (`Integer.floor_div/2` plus an index
   range), not the last bucket's start date — the date comparison dropped a set kept today
   (2026-10-16).

---

## Related Repositories

- `bot_army_schemas_fitness` - Fitness message schemas
- `bot_army_core` - Core library and NATS decoder
- `bot_army_infra` - Deployment infrastructure

---

## Agent Workflow Pattern

**Effective use of Claude Code agents when developing this bot.**

This follows the polyrepo agent strategy documented in `bot_army_infra/CLAUDE.md`.

### When to Use Haiku Agents

- Exploring handler implementations and understanding existing patterns
- Reading test files to understand expected behavior
- Diagnostics: checking test failures, understanding error logs
- Code search: finding specific handlers or NATS subjects
- Verification: running tests, checking message flow

**Why**: Fast iteration loop, perfect for understanding how other bots are structured.

### When to Use Sonnet Agents

- Implementing new handlers or business logic
- Designing complex analytics and progress tracking features
- Multi-handler integrations and workout data management
- Refactoring handlers for new requirements
- Performance optimizations

**Why**: Deep reasoning ensures handlers are correct, analytics logic is sound, and data consistency is maintained.

### Example: Add Workout Analytics Feature

```
User: "Add workout performance analytics with trends"
  ↓
1. Haiku (Explore): Read existing workout_handler.ex and goal_handler.ex, understand data flow
  ↓
2. Sonnet (Plan): Design analytics feature, identify metrics to track, plan aggregation strategy
   Determine storage and query patterns
  ↓
3. Sonnet (Implement): Add analytics handler, implement trend calculations, add tests
  ↓
4. Haiku (Verify): Run test suite, check accuracy of calculations
```
