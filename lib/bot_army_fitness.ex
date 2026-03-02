defmodule BotArmyFitness do
  @moduledoc """
  BotArmyFitness is the fitness and wellness bot implementation.

  Handles workout tracking, exercise management, and fitness goal monitoring
  within the Bot Army ecosystem.

  ## Schemas

  Message schemas are defined in `bot_army_schemas_fitness` and deployed to:
  `/etc/bot_army/schemas/fitness/`

  The bot consumes messages from NATS subjects like:
  - `fitness.workout.log` - Log a workout
  - `fitness.exercise.record` - Record exercise data
  - `fitness.goal.track` - Track fitness goal progress
  """

  @version "0.1.0"

  def version do
    @version
  end
end
