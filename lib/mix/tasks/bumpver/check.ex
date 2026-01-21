defmodule Mix.Tasks.Bumpver.Check do
  @moduledoc """
  Verifies that the version in mix.exs has been updated since the last commit.

  This task is useful in pre-commit workflows to ensure developers remember to bump
  the version before committing changes.

  ## Usage

      mix bumpver.check

  ## Auto-bump

  By default this task is non-interactive and will fail if you forgot to bump.
  You can opt-in to auto-bumping (interactive by default):

      mix bumpver.check --auto-bump

  If no interactive terminal is available (for example in some GUIs / CI / hooks),
  use non-interactive mode:

      mix bumpver.check --auto-bump --yes

  Or choose a bump type explicitly:

      mix bumpver.check --auto-bump --bump minor

  ## Exit Codes

  - 0: Version has been updated (or no git history exists)
  - 1: Version has NOT been updated since last commit

  ## How it works

  1. Reads the current version from mix.exs
  2. Reads the version from the last commit using `git show REV:mix.exs`
  3. Compares them
  4. Passes if they differ, fails if they're the same
  """

  use Mix.Task

  alias Bumpver.CLIArgs

  @shortdoc "Verify version has been updated since last commit"

  @requirements ["loadpaths"]

  @doc false
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          file: :string,
          against: :string,
          help: :boolean,
          auto_bump: :boolean,
          bump: :string,
          major: :boolean,
          minor: :boolean,
          patch: :boolean,
          yes: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    if opts[:help] do
      Mix.shell().info(help_text())
      :ok
    else
      mix_file = opts[:file] || "mix.exs"
      rev = opts[:against] || "HEAD"

      unless File.exists?(mix_file) do
        Mix.raise("#{mix_file} not found")
      end

      content = File.read!(mix_file)
      Bumpver.ensure_consistent_versions!(content)
      current_version = Bumpver.extract_version(content)

      if is_nil(current_version) do
        Mix.raise("Could not find version in #{mix_file}")
      end

      case get_git_version(mix_file, rev) do
        {:ok, git_version} ->
          if current_version == git_version do
            if opts[:auto_bump] do
              auto_bump!(mix_file, opts)

              new_content = File.read!(mix_file)
              Bumpver.ensure_consistent_versions!(new_content)
              new_version = Bumpver.extract_version(new_content)

              if is_nil(new_version) do
                Mix.raise("Auto-bump failed: could not re-read version from #{mix_file}")
              end

              Mix.shell().info("✓ Version auto-bumped (#{git_version} → #{new_version})")
              :ok
            else
              Mix.raise(
                "\n✗ Version has not been updated since last commit!\n" <>
                  "  Current version: #{current_version}\n\n" <>
                  "  Please run: mix bumpver\n"
              )
            end
          end

          Mix.shell().info("✓ Version check passed (#{git_version} → #{current_version})")

        {:error, :no_git} ->
          Mix.shell().info("✓ Version check skipped (no git repository)")

        {:error, :no_commits} ->
          Mix.shell().info("✓ Version check skipped (no previous commits)")

        {:error, reason} ->
          Mix.shell().error("Warning: Could not check git version: #{reason}")
          Mix.shell().info("✓ Version check skipped")
      end
    end
  end

  defp get_git_version(file, rev) do
    case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
      {_, 0} ->
        case System.cmd("git", ["show", "#{rev}:#{file}"], stderr_to_stdout: true) do
          {output, 0} ->
            version = Bumpver.extract_version(output)
            if version, do: {:ok, version}, else: {:error, "version not found in git"}

          {output, _} ->
            if String.contains?(output, "does not have any commits yet") or
                 String.contains?(output, "bad revision") do
              {:error, :no_commits}
            else
              {:error, String.trim(output)}
            end
        end

      {_, _} ->
        {:error, :no_git}
    end
  end

  defp help_text do
    """
    mix bumpver.check - verify the version in mix.exs changed since a git revision

    Usage:
      mix bumpver.check
      mix bumpver.check --against HEAD
      mix bumpver.check --against v1.2.3
      mix bumpver.check --auto-bump
      mix bumpver.check --auto-bump --yes
      mix bumpver.check --auto-bump --bump patch

    Options:
      --file PATH      Path to mix.exs (default: mix.exs)
      --against REV    Git revision to compare against (default: HEAD)
      --auto-bump      When the version has not changed, run mix bumpver automatically
      --bump TYPE      One of: major, minor, patch (non-interactive if provided)
      --major          Alias for --bump major
      --minor          Alias for --bump minor
      --patch          Alias for --bump patch
      --yes            Non-interactive default (uses patch if no type given)
      --help           Show this help
    """
  end

  defp auto_bump!(mix_file, opts) do
    bump_type =
      case Bumpver.bump_type_from_opts(opts) do
        {:ok, type} -> type
        {:error, msg} -> Mix.raise(msg)
      end

    bump_args =
      ["--file", mix_file] ++
        Bumpver.mix_bumpver_args_for_type(bump_type) ++
        CLIArgs.yes_args(opts)

    if interactive_required?(bump_args) and not tty_available?() do
      Mix.raise(
        "\n✗ Cannot run interactive bump (no TTY detected).\n" <>
          "  Re-run with: mix bumpver.check --auto-bump --yes\n" <>
          "  Or choose a bump type: mix bumpver.check --auto-bump --bump patch\n"
      )
    end

    Mix.Task.run("bumpver", bump_args)
  end

  defp interactive_required?(bump_args) do
    not Enum.any?(bump_args, &(&1 in ["--major", "--minor", "--patch", "--yes"]))
  end

  defp tty_available? do
    if System.get_env("CI") do
      false
    else
      case :io.columns() do
        {:ok, _} -> true
        _ -> false
      end
    end
  end
end
