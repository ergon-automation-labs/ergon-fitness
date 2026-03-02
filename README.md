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
