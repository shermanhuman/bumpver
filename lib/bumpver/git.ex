defmodule Bumpver.Git do
  @moduledoc false

  @spec hooks_dir!() :: binary()
  def hooks_dir! do
    case System.cmd("git", ["rev-parse", "--git-path", "hooks"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> Path.expand(File.cwd!())

      {output, _} ->
        Mix.raise("Not a git repository (could not locate hooks dir): #{String.trim(output)}")
    end
  end
end
