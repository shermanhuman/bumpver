defmodule Bumpver do
  @moduledoc """
  Shared helpers used by the Mix tasks in this project.

  This library focuses on semantic version extraction and bumping for typical
  `mix.exs` layouts.
  """

  @type bump_type :: :major | :minor | :patch

  @doc """
  Parses a bump type from a string.

  Accepts: "major", "minor", "patch" (case-insensitive, surrounding whitespace ignored).
  """
  @spec parse_bump_type(binary()) :: {:ok, bump_type()} | {:error, binary()}
  def parse_bump_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "major" -> {:ok, :major}
      "minor" -> {:ok, :minor}
      "patch" -> {:ok, :patch}
      other -> {:error, "Invalid --bump value: #{inspect(other)} (expected major|minor|patch)"}
    end
  end

  @doc """
  Extracts a bump type from OptionParser opts.

  Supports either:

  - `--bump TYPE` (string)
  - one of `--major`, `--minor`, `--patch`

  Returns `{:ok, nil}` if no bump type was provided.
  """
  @spec bump_type_from_opts(keyword()) :: {:ok, bump_type() | nil} | {:error, binary()}
  def bump_type_from_opts(opts) when is_list(opts) do
    bump_opt = opts[:bump]
    bump_opt? = is_binary(bump_opt) and String.trim(bump_opt) != ""

    flag_types =
      [
        opts[:major] && :major,
        opts[:minor] && :minor,
        opts[:patch] && :patch
      ]
      |> Enum.reject(&is_nil/1)

    cond do
      bump_opt? and flag_types != [] ->
        {:error,
         "Please specify only one bump type (use either --bump TYPE or --major/--minor/--patch)"}

      length(flag_types) > 1 ->
        {:error, "Please specify only one of --major, --minor, --patch"}

      bump_opt? ->
        parse_bump_type(bump_opt)

      flag_types == [] ->
        {:ok, nil}

      true ->
        {:ok, List.first(flag_types)}
    end
  end

  @doc """
  Converts a bump type into args for `mix bumpver`.
  """
  @spec mix_bumpver_args_for_type(bump_type() | nil) :: [binary()]
  def mix_bumpver_args_for_type(nil), do: []
  def mix_bumpver_args_for_type(:major), do: ["--major"]
  def mix_bumpver_args_for_type(:minor), do: ["--minor"]
  def mix_bumpver_args_for_type(:patch), do: ["--patch"]

  @doc """
  Converts a bump type into args for `mix bumpver.check`.
  """
  @spec version_check_args_for_type(bump_type() | nil) :: [binary()]
  def version_check_args_for_type(nil), do: []
  def version_check_args_for_type(:major), do: ["--bump", "major"]
  def version_check_args_for_type(:minor), do: ["--bump", "minor"]
  def version_check_args_for_type(:patch), do: ["--bump", "patch"]

  @doc """
  Extracts a semantic version from a `mix.exs` file content.

  Supports common patterns:

  - `@version "1.2.3"`
  - `version: "1.2.3"`

  If both exist, `version: "..."` wins.
  """
  @spec extract_version(binary()) :: binary() | nil
  def extract_version(content) when is_binary(content) do
    {direct, attr} = extract_versions(content)

    cond do
      is_binary(direct) and direct != "" -> direct
      is_binary(attr) and attr != "" -> attr
      true -> nil
    end
  end

  @doc """
  Extracts both supported version patterns from a `mix.exs` file content.

  Returns `{direct, attr}` where:
  - `direct` is the value from `version: "..."` (if present)
  - `attr` is the value from `@version "..."` (if present)
  """
  @spec extract_versions(binary()) :: {binary() | nil, binary() | nil}
  def extract_versions(content) when is_binary(content) do
    direct = first_capture(~r/\bversion:\s+"([^"]+)"/, content)
    attr = first_capture(~r/@version\s+"([^"]+)"/, content)
    {direct, attr}
  end

  @doc """
  Ensures `mix.exs` content does not contain conflicting version declarations.

  If both `version: "..."` and `@version "..."` exist and differ, this raises.
  """
  @spec ensure_consistent_versions!(binary()) :: :ok
  def ensure_consistent_versions!(content) when is_binary(content) do
    {direct, attr} = extract_versions(content)

    if is_binary(direct) and direct != "" and is_binary(attr) and attr != "" and direct != attr do
      raise ArgumentError,
            "Conflicting versions found in mix.exs: version: #{inspect(direct)} and @version #{inspect(attr)}"
    end

    :ok
  end

  @doc """
  Bumps a semantic version.

  Uses Elixir's `Version` parser. Pre-release/build metadata are dropped on bump.
  """
  @spec bump_version(binary(), bump_type()) :: binary()
  def bump_version(version, type) when is_binary(version) and type in [:major, :minor, :patch] do
    case Version.parse(version) do
      {:ok, v} ->
        v =
          case type do
            :major -> %Version{v | major: v.major + 1, minor: 0, patch: 0, pre: [], build: nil}
            :minor -> %Version{v | minor: v.minor + 1, patch: 0, pre: [], build: nil}
            :patch -> %Version{v | patch: v.patch + 1, pre: [], build: nil}
          end

        to_string(v)

      :error ->
        raise ArgumentError,
              "Invalid version format: #{inspect(version)}. Expected a semantic version like 1.2.3"
    end
  end

  @doc """
  Updates `mix.exs` content by replacing the currently-detected version with `new_version`.

  Only updates patterns that match the extracted `current_version`, to avoid
  accidentally rewriting unrelated strings.
  """
  @spec update_mix_exs_content(binary(), binary()) :: binary()
  def update_mix_exs_content(content, new_version)
      when is_binary(content) and is_binary(new_version) do
    ensure_consistent_versions!(content)
    current_version = extract_version(content)

    if is_nil(current_version) do
      raise ArgumentError, "Could not find version in mix.exs content"
    end

    content
    |> replace_attr_version(current_version, new_version)
    |> replace_direct_version(current_version, new_version)
  end

  defp first_capture(regex, content) do
    case Regex.run(regex, content, capture: :all_but_first) do
      [value] when is_binary(value) -> value
      _ -> nil
    end
  end

  defp replace_attr_version(content, current_version, new_version) do
    Regex.replace(
      ~r/@version\s+"#{Regex.escape(current_version)}"/,
      content,
      "@version \"#{new_version}\""
    )
  end

  defp replace_direct_version(content, current_version, new_version) do
    Regex.replace(
      ~r/\bversion:\s+"#{Regex.escape(current_version)}"/,
      content,
      "version: \"#{new_version}\""
    )
  end
end
