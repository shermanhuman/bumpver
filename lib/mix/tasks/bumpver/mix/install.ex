defmodule Mix.Tasks.Bumpver.Mix.Install do
  @moduledoc """
  Installs a `precommit` (or custom) Mix alias into a project's `mix.exs`.

  This is intentionally conservative and idempotent:

  - If the alias is already present and points at the desired command, nothing changes.
  - If the alias exists but differs, this task refuses unless `--force` is provided.
  - If the file layout is too unusual to patch safely, it prints manual instructions.

  ## Usage

      mix bumpver.mix.install

  ## Options

    * `--file PATH`    Path to `mix.exs` (default: `mix.exs`)
    * `--alias NAME`   Alias name to install (default: `precommit`)
    * `--force`        Replace an existing alias entry
    * `--help`         Show this help
  """

  use Mix.Task

  alias Bumpver.{Mixfile, PrecommitAlias}

  @shortdoc "Install a precommit Mix alias"

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

      validate_identifier!(alias_name)

      unless File.exists?(mix_file) do
        Mix.raise("#{mix_file} not found")
      end

      content = File.read!(mix_file)

      case install_alias(content, alias_name, force?) do
        {:ok, :already_installed} ->
          Mix.shell().info("✓ Alias already installed (#{alias_name})")
          :ok

        {:ok, {:updated, new_content}} ->
          File.write!(mix_file, new_content)
          Mix.shell().info("✓ Installed alias #{alias_name}")
          :ok

        {:error, msg} ->
          Mix.raise(msg)
      end
    end
  end

  defp validate_identifier!(name) do
    if name == "" do
      Mix.raise("--alias cannot be empty")
    end

    if not Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) do
      Mix.raise(
        "Invalid --alias value: #{inspect(name)} (expected an atom-like name, e.g. precommit)"
      )
    end
  end

  defp desired_steps do
    PrecommitAlias.steps()
  end

  defp desired_entry(alias_name) do
    PrecommitAlias.entry(alias_name)
  end

  defp install_alias(content, alias_name, force?) do
    desired_entry = desired_entry(alias_name)

    cond do
      already_installed?(content, alias_name) ->
        {:ok, :already_installed}

      true ->
        with {:ok, updated} <-
               try_install_into_inline_aliases(content, alias_name, force?),
             {:ok, ensured} <- ensure_project_references_aliases_fun(updated) do
          {:ok, {:updated, ensured}}
        else
          :no_inline_aliases ->
            case try_install_into_aliases_function(content, alias_name, force?) do
              {:ok, updated} ->
                case ensure_project_references_aliases_fun(updated) do
                  {:ok, ensured} -> {:ok, {:updated, ensured}}
                  {:error, msg} -> {:error, msg}
                end

              :no_aliases_function ->
                add_aliases_function_and_reference(content, desired_entry)

              {:error, msg} ->
                {:error, msg}
            end

          {:error, msg} ->
            {:error, msg}
        end
    end
  end

  defp already_installed?(content, alias_name) do
    case Regex.run(
           ~r/\b#{Regex.escape(alias_name)}\s*:\s*\[(?<list>[^\]]*)\]/,
           content,
           capture: :all_names
         ) do
      [%{"list" => list}] ->
        Enum.all?(desired_steps(), fn step ->
          String.contains?(list, "\"#{step}\"")
        end)

      _ ->
        false
    end
  end

  defp try_install_into_inline_aliases(content, alias_name, force?) do
    case Regex.run(~r/\baliases:\s*\[/, content, return: :index) do
      [{start, _len}] ->
        open_bracket_index = Mixfile.find_next_open_bracket!(content, start + String.length("aliases:"))
        {list_start, list_end} = Mixfile.find_bracketed_range!(content, open_bracket_index)
        list = String.slice(content, list_start, list_end - list_start + 1)

        case upsert_alias_entry(list, alias_name, force?) do
          {:ok, new_list} ->
            {:ok, Mixfile.splice(content, list_start, list_end, new_list)}

          {:error, msg} ->
            {:error, msg}
        end

      _ ->
        :no_inline_aliases
    end
  end

  defp try_install_into_aliases_function(content, alias_name, force?) do
    case Regex.run(~r/\bdefp\s+aliases\s+do\b/, content, return: :index) do
      [{start, len}] ->
        after_def = start + len

        case Regex.run(~r/\[/, content, return: :index, offset: after_def) do
          [{bracket_idx, _}] ->
            {list_start, list_end} = Mixfile.find_bracketed_range!(content, bracket_idx)
            list = String.slice(content, list_start, list_end - list_start + 1)

            case upsert_alias_entry(list, alias_name, force?) do
              {:ok, new_list} ->
                {:ok, Mixfile.splice(content, list_start, list_end, new_list)}

              {:error, msg} ->
                {:error, msg}
            end

          _ ->
            {:error, "Could not find aliases list in defp aliases/0"}
        end

      _ ->
        :no_aliases_function
    end
  end

  defp ensure_project_references_aliases_fun(content) do
    if Regex.match?(~r/\baliases:\s*aliases\(\)\b/, content) do
      {:ok, content}
    else
      case Regex.run(~r/\bdef\s+project\s+do\b/, content, return: :index) do
        [{start, len}] ->
          after_def = start + len

          case Regex.run(~r/\[/, content, return: :index, offset: after_def) do
            [{bracket_idx, _}] ->
              {list_start, list_end} = Mixfile.find_bracketed_range!(content, bracket_idx)
              list = String.slice(content, list_start, list_end - list_start + 1)

              if Regex.match?(~r/\baliases:\s*/, list) do
                {:ok, content}
              else
                {:ok, Mixfile.splice(content, list_start, list_end, insert_project_aliases_ref(list))}
              end

            _ ->
              {:error,
               "Could not safely install aliases: expected a keyword list in def project/0.\n" <>
                 manual_instructions("precommit")}
          end

        _ ->
          {:error,
           "Could not find def project/0 to install alias reference.\n" <>
             manual_instructions("precommit")}
      end
    end
  end

  defp insert_project_aliases_ref(list) do
    if String.contains?(list, "\n") do
      indent = detect_inner_indent(list) || "    "

      if Regex.match?(~r/,\s*\n\s*\]\s*$/, list) do
        String.replace(list, ~r/\n\s*\]\s*$/, "\n#{indent}aliases: aliases(),\n]")
      else
        String.replace(list, ~r/\n\s*\]\s*$/, ",\n#{indent}aliases: aliases(),\n]")
      end
    else
      String.replace(list, ~r/\]\s*$/, ", aliases: aliases()]")
    end
  end

  defp add_aliases_function_and_reference(content, desired_entry) do
    with {:ok, with_ref} <- ensure_project_references_aliases_fun(content),
         {:ok, updated} <- append_aliases_function(with_ref, desired_entry) do
      {:ok, {:updated, updated}}
    else
      {:error, msg} -> {:error, msg}
    end
  end

  defp append_aliases_function(content, desired_entry) do
    if Regex.match?(~r/\bdefp\s+aliases\s+do\b/, content) do
      {:ok, content}
    else
      insertion =
        "\n\n  defp aliases do\n" <>
          "    [\n" <>
          "      #{desired_entry}\n" <>
          "    ]\n" <>
          "  end\n"

      case Regex.run(~r/\nend\s*\z/, content, return: :index) do
        [{end_start, _}] ->
          {:ok, Mixfile.splice_insert_before(content, end_start, insertion)}

        _ ->
          {:error,
           "Could not safely append defp aliases/0.\n" <>
             manual_instructions("precommit")}
      end
    end
  end

  defp upsert_alias_entry(list, alias_name, force?) do
    desired = desired_entry(alias_name)

    if Regex.match?(~r/\b#{Regex.escape(alias_name)}\s*:/, list) do
      if already_installed?(list, alias_name) do
        {:ok, list}
      else
        if force? do
          {:ok, replace_alias_entry(list, alias_name, desired)}
        else
          {:error,
           "Alias #{inspect(alias_name)} already exists in mix.exs.\n" <>
             "Refusing to overwrite. Re-run with --force, or edit manually.\n" <>
             manual_instructions(alias_name)}
        end
      end
    else
      {:ok, insert_alias_entry(list, desired)}
    end
  end

  defp replace_alias_entry(list, alias_name, desired) do
    if String.contains?(list, "\n") do
      Regex.replace(
        ~r/^([\t ]*)#{Regex.escape(alias_name)}\s*:\s*\[[^\]]*\]\s*,?\s*$/m,
        list,
        "\\1#{desired},"
      )
    else
      Regex.replace(
        ~r/\b#{Regex.escape(alias_name)}\s*:\s*\[[^\]]*\]\s*,?\s*/,
        list,
        "#{desired}, "
      )
      |> String.replace(~r/,\s*\]/, "]")
    end
  end

  defp insert_alias_entry(list, desired) do
    if String.contains?(list, "\n") do
      indent = detect_inner_indent(list) || "    "

      String.replace(
        list,
        ~r/\n\s*\]\s*$/,
        "\n#{indent}#{desired},\n]"
      )
    else
      String.replace(list, ~r/\]\s*$/, ", #{desired}]")
    end
  end

  defp detect_inner_indent(list) do
    case Regex.run(~r/\n([\t ]+)\S/, list, capture: :all_but_first) do
      [indent] -> indent
      _ -> nil
    end
  end

  defp manual_instructions(alias_name) do
    steps = desired_steps() |> Enum.map(&"\"#{&1}\"") |> Enum.join(", ")

    "\nAdd this to your project's aliases in mix.exs:\n\n" <>
      "    #{alias_name}: [#{steps}]\n"
  end

  defp help_text do
    """
    mix bumpver.mix.install - install a precommit Mix alias into mix.exs

    Usage:
      mix bumpver.mix.install
      mix bumpver.mix.install --file path/to/mix.exs
      mix bumpver.mix.install --alias precommit
      mix bumpver.mix.install --force

    Options:
      --file PATH      Path to mix.exs (default: mix.exs)
      --alias NAME     Alias name to install (default: precommit)
      --force          Replace an existing alias entry
      --help           Show this help
    """
  end
end
