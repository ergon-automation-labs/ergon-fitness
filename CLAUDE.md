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
