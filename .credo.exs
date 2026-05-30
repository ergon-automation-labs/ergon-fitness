%{
  configs: [
    %{
      name: "default",
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.MaxLineLength, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []}
        ]
      }
    }
  ]
}
