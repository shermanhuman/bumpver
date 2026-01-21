defmodule Bumpver.CLIArgs do
  @moduledoc false

  @spec yes_args(keyword()) :: [binary()]
  def yes_args(opts) when is_list(opts) do
    if opts[:yes], do: ["--yes"], else: []
  end
end
