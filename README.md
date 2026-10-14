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
                     -> {"set": {...}, "previous": {...}|null}
```

* the bot derives `measure` (`reps` | `seconds`) and `load_kind` from the
  catalog — a caller describing the movement would be guessing at the gym;
* a load that is not a setting the equipment really has is **refused**
  (`load_not_on_ladder`), never rounded — rounding records a set that never
  happened, and the next read builds a progression on a weight that is not in
  the room;
* an absent load is a fact, not a missing field: a bodyweight movement's absent
  number means the body alone, and one with no load still records its reps;
* the reply carries `previous` — the set before this one for the same movement —
  so a surface can say "last time" without slicing a history itself.

A set counts as training: `Scheduler.days_since_last_workout/0` reads the newest
day from the workout log **and** the set log, and a failed read is an error, never
a shorter history. Both logs are read newest-day-first, so a set she backfills for
an older day does not become "last time" — and does not make today look trained.

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
