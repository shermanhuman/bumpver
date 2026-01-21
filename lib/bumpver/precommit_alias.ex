defmodule Bumpver.PrecommitAlias do
  @moduledoc false

  @spec steps() :: [binary()]
  def steps do
    [
      "format",
      "compile --warnings-as-errors",
      "bumpver.check --auto-bump",
      "test"
    ]
  end

  @spec entry(binary()) :: binary()
  def entry(alias_name) when is_binary(alias_name) do
    steps = steps() |> Enum.map(&"\"#{&1}\"") |> Enum.join(", ")
    "#{alias_name}: [#{steps}]"
  end
end
