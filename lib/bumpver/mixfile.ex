defmodule Bumpver.Mixfile do
  @moduledoc false

  @spec find_next_open_bracket!(binary(), non_neg_integer()) :: non_neg_integer()
  def find_next_open_bracket!(content, index) when is_binary(content) and is_integer(index) do
    size = byte_size(content)

    Enum.reduce_while(index..(size - 1), nil, fn i, _acc ->
      ch = :binary.at(content, i)

      cond do
        ch in [?\n, ?\r, ?\t, ?\s] ->
          {:cont, nil}

        ch == ?[ ->
          {:halt, i}

        true ->
          raise "Expected '[' after aliases:, found: #{inspect(<<ch>>)}"
      end
    end) || raise "Expected '[' after aliases:"
  end

  @spec find_bracketed_range!(binary(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  def find_bracketed_range!(content, open_bracket_index)
      when is_binary(content) and is_integer(open_bracket_index) do
    binary = content
    size = byte_size(binary)

    if open_bracket_index < 0 or open_bracket_index >= size do
      raise "Invalid bracket index"
    end

    if :binary.at(binary, open_bracket_index) != ?[ do
      raise "Expected '[' at index #{open_bracket_index}"
    end

    {end_idx, _state} =
      Enum.reduce_while(
        (open_bracket_index + 1)..(size - 1),
        {nil, %{depth: 1, in_str: false, esc: false}},
        fn i, {_, st} ->
          ch = :binary.at(binary, i)

          st =
            cond do
              st.esc ->
                %{st | esc: false}

              st.in_str and ch == ?\\ ->
                %{st | esc: true}

              st.in_str and ch == ?" ->
                %{st | in_str: false}

              not st.in_str and ch == ?" ->
                %{st | in_str: true}

              st.in_str ->
                st

              ch == ?[ ->
                %{st | depth: st.depth + 1}

              ch == ?] ->
                %{st | depth: st.depth - 1}

              true ->
                st
            end

          if not st.in_str and st.depth == 0 do
            {:halt, {i, st}}
          else
            {:cont, {nil, st}}
          end
        end
      )

    if is_nil(end_idx) do
      raise "Unterminated '[' starting at #{open_bracket_index}"
    end

    {open_bracket_index, end_idx}
  end

  @spec splice(binary(), non_neg_integer(), non_neg_integer(), binary()) :: binary()
  def splice(content, start_idx, end_idx, replacement)
      when is_binary(content) and is_integer(start_idx) and is_integer(end_idx) and is_binary(replacement) do
    prefix = binary_part(content, 0, start_idx)
    suffix = binary_part(content, end_idx + 1, byte_size(content) - (end_idx + 1))
    prefix <> replacement <> suffix
  end

  @spec splice_insert_before(binary(), non_neg_integer(), binary()) :: binary()
  def splice_insert_before(content, index, insertion)
      when is_binary(content) and is_integer(index) and is_binary(insertion) do
    prefix = binary_part(content, 0, index)
    suffix = binary_part(content, index, byte_size(content) - index)
    prefix <> insertion <> suffix
  end
end
