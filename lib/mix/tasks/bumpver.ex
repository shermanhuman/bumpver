defmodule Mix.Tasks.Bumpver do
  @moduledoc """
  Interactive semantic version bumping for Elixir projects.

  ## Usage

      mix bumpver

  This task will:
  1. Read the current version from mix.exs
  2. Prompt you to select a bump type (MAJOR, MINOR, or PATCH)
  3. Update the version in mix.exs

  ## Semantic Versioning Guide

  - **MAJOR**: Incompatible API changes
  - **MINOR**: Backward compatible functionality additions
  - **PATCH**: Backward compatible bug fixes

  ## Examples

      # Interactive bump
      mix bumpver

  """

  use Mix.Task

  @shortdoc "Interactively bump the project version"

  @requirements ["loadpaths"]

  @doc false
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          major: :boolean,
          minor: :boolean,
          patch: :boolean,
          dry_run: :boolean,
          yes: :boolean,
          file: :string,
          help: :boolean
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

      unless File.exists?(mix_file) do
        Mix.raise("#{mix_file} not found")
      end

      content = File.read!(mix_file)
      Bumpver.ensure_consistent_versions!(content)
      current_version = Bumpver.extract_version(content)

      if is_nil(current_version) do
        Mix.raise("Could not find version in #{mix_file}")
      end

      Mix.shell().info("Current version: #{current_version}")

      bump_type = bump_type_from_opts(opts) || bump_type_from_prompt(opts)

      new_version = Bumpver.bump_version(current_version, bump_type)
      new_content = Bumpver.update_mix_exs_content(content, new_version)

      if opts[:dry_run] do
        Mix.shell().info("")
        Mix.shell().info("(dry-run) Would bump: #{current_version} → #{new_version}")
        :ok
      else
        File.write!(mix_file, new_content)

        Mix.shell().info("")
        Mix.shell().info("✓ Version bumped: #{current_version} → #{new_version}")
      end
    end
  end

  defp bump_type_from_opts(opts) do
    case Bumpver.bump_type_from_opts(opts) do
      {:ok, type} -> type
      {:error, msg} -> Mix.raise(msg)
    end
  end

  defp bump_type_from_prompt(opts) do
    if opts[:yes] do
      :patch
    else
      Mix.shell().info("")
      Mix.shell().info("Select bump type:")
      Mix.shell().info("[1] MAJOR - Incompatible API changes")
      Mix.shell().info("[2] MINOR - Backward compatible functionality")
      Mix.shell().info("[3] PATCH - Backward compatible bug fixes (Default)")
      Mix.shell().info("")

      choice =
        Mix.shell().prompt("Enter choice (1/2/3):")
        |> String.trim()

      case choice do
        "1" -> :major
        "2" -> :minor
        "3" -> :patch
        "" -> :patch
        _ -> Mix.raise("Invalid choice. Please enter 1, 2, or 3")
      end
    end
  end

  defp help_text do
    """
    mix bumpver - interactively (or non-interactively) bump a Mix project version

    Usage:
      mix bumpver
      mix bumpver --patch
      mix bumpver --minor
      mix bumpver --major

    Options:
      --patch        Bump patch version
      --minor        Bump minor version
      --major        Bump major version
      --yes          Non-interactive (defaults to --patch if no bump type given)
      --dry-run      Do not write files, only print the result
      --file PATH    Path to mix.exs (default: mix.exs)
      --help         Show this help
    """
  end
end
