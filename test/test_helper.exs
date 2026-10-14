ExUnit.configure(exclude: [:integration, :load, :nats_live])
ExUnit.start()

Mox.defmock(BotArmyFitness.WorkoutStoreMock, for: BotArmyFitness.WorkoutStoreBehaviour)
Mox.defmock(BotArmyFitness.GoalStoreMock, for: BotArmyFitness.GoalStoreBehaviour)
Mox.defmock(BotArmyFitness.WorkoutSetStoreMock, for: BotArmyFitness.WorkoutSetStoreBehaviour)
