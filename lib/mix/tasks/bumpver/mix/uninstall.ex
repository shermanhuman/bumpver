defmodule Mix.Tasks.Bumpver.Mix.Uninstall do
  @moduledoc """
  Removes a `precommit` (or custom) Mix alias from a project's `mix.exs`.

  This is conservative:

  - By default it only removes an alias entry if it points at the configured command.
  - Use `--force` to remove the alias key regardless of its current value.

  ## Usage

      mix bumpver.mix.uninstall

  ## Options

    * `--file PATH`    Path to `mix.exs` (default: `mix.exs`)
    * `--alias NAME`   Alias name to remove (default: `precommit`)
    * `--force`        Remove the alias even if it points elsewhere
    * `--help`         Show this help
  """

  use Mix.Task

  alias Bumpver.{Mixfile, PrecommitAlias}

  @shortdoc "Uninstall a precommit Mix alias"

  @requirements ["loadpaths"]

  @impl true
  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          file: :string,
          alias: :string,
          force: :boolean,
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
      alias_name = (opts[:alias] || "precommit") |> String.trim()
      force? = !!opts[:force]

      unless File.exists?(mix_file) do
        Mix.raise("#{mix_file} not found")
      end

      content = File.read!(mix_file)

      case uninstall_alias(content, alias_name, force?) do
        {:ok, :already_absent} ->
          Mix.shell().info("✓ Alias already absent (#{alias_name})")
          :ok

        {:ok, {:updated, new_content}} ->
          File.write!(mix_file, new_content)
          Mix.shell().info("✓ Removed alias #{alias_name}")
          :ok

        {:error, msg} ->
          Mix.raise(msg)
      end
    end
  end

  defp desired_steps do
    PrecommitAlias.steps()
  end

  defp desired_entry(alias_name) do
    PrecommitAlias.entry(alias_name)
  end

  defp uninstall_alias(content, alias_name, force?) do
    if not Regex.match?(~r/\b#{Regex.escape(alias_name)}\s*:/, content) do
      {:ok, :already_absent}
    else
      case try_remove_from_inline_aliases(content, alias_name, force?) do
        {:ok, updated} ->
          {:ok, {:updated, updated}}

        :no_inline_aliases ->
          case try_remove_from_aliases_function(content, alias_name, force?) do
            {:ok, updated} -> {:ok, {:updated, updated}}
            :no_aliases_function -> {:ok, :already_absent}
            {:error, msg} -> {:error, msg}
          end

        {:error, msg} ->
          {:error, msg}
      end
    end
  end

  defp try_remove_from_inline_aliases(content, alias_name, force?) do
    case Regex.run(~r/\baliases:\s*\[/, content, return: :index) do
      [{start, _len}] ->
        open_bracket_index = Mixfile.find_next_open_bracket!(content, start + String.length("aliases:"))
        {list_start, list_end} = Mixfile.find_bracketed_range!(content, open_bracket_index)
        list = String.slice(content, list_start, list_end - list_start + 1)

        case remove_alias_entry(list, alias_name, force?) do
          {:ok, new_list} -> {:ok, Mixfile.splice(content, list_start, list_end, new_list)}
          {:error, msg} -> {:error, msg}
          :not_present -> {:ok, content}
        end

      _ ->
        :no_inline_aliases
    end
  end

  defp try_remove_from_aliases_function(content, alias_name, force?) do
    case Regex.run(~r/\bdefp\s+aliases\s+do\b/, content, return: :index) do
      [{start, len}] ->
        after_def = start + len

        case Regex.run(~r/\[/, content, return: :index, offset: after_def) do
          [{bracket_idx, _}] ->
            {list_start, list_end} = Mixfile.find_bracketed_range!(content, bracket_idx)
            list = String.slice(content, list_start, list_end - list_start + 1)

            case remove_alias_entry(list, alias_name, force?) do
              {:ok, new_list} -> {:ok, Mixfile.splice(content, list_start, list_end, new_list)}
              {:error, msg} -> {:error, msg}
              :not_present -> {:ok, content}
            end

          _ ->
            {:error, "Could not find aliases list in defp aliases/0"}
        end

      _ ->
        :no_aliases_function
    end
  end

  defp remove_alias_entry(list, alias_name, force?) do
    desired = desired_entry(alias_name)

    cond do
      String.contains?(list, desired) ->
        {:ok, delete_entry(list, alias_name, desired_steps())}

      Regex.match?(~r/\b#{Regex.escape(alias_name)}\s*:/, list) and force? ->
        {:ok, delete_entry_any(list, alias_name)}

      Regex.match?(~r/\b#{Regex.escape(alias_name)}\s*:/, list) ->
        {:error,
         "Alias #{inspect(alias_name)} exists, but does not match the expected command.\n" <>
           "Refusing to remove. Re-run with --force, or edit manually."}

      true ->
        :not_present
    end
  end

  defp delete_entry(list, alias_name, steps) do
    # Conservative: only remove when the alias list contains the expected steps.
    steps_present? = Enum.all?(steps, fn step -> String.contains?(list, "\"#{step}\"") end)

    if not steps_present? do
      list
    else
      delete_entry_any(list, alias_name)
    end
  end

  defp delete_entry_any(list, alias_name) do
    if String.contains?(list, "\n") do
      Regex.replace(
        ~r/^([\t ]*)#{Regex.escape(alias_name)}\s*:\s*\[[^\]]*\]\s*,?\s*\n/m,
        list,
        ""
      )
      |> String.replace(~r/\n\s*\n\s*\]/, "\n]")
    else
      list
      |> Regex.replace(~r/\b#{Regex.escape(alias_name)}\s*:\s*\[[^\]]*\]\s*,?\s*/, "")
      |> String.replace(~r/\[,\s*/, "[")
      |> String.replace(~r/\s+,\s*\]/, "]")
      |> String.replace(~r/\[,\s*\]/, "[]")
    end
  end

  defp help_text do
    """
    mix bumpver.mix.uninstall - remove a precommit Mix alias from mix.exs

    Usage:
      mix bumpver.mix.uninstall
      mix bumpver.mix.uninstall --file path/to/mix.exs
      mix bumpver.mix.uninstall --alias precommit
      mix bumpver.mix.uninstall --force

    Options:
      --file PATH      Path to mix.exs (default: mix.exs)
      --alias NAME     Alias name to remove (default: precommit)
      --force          Remove the alias even if it points elsewhere
      --help           Show this help
    """
  end
end
