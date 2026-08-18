defmodule Tuix.Components.Input do
  @moduledoc """
  The editing core of the `Tuix.Components.input/1` element: pure,
  grapheme-aware functions over a value and a cursor offset.

  Inputs are controlled: the app owns the value in assigns. When a key
  reaches a focused input, the runtime calls `on_key/3` (the
  `Tuix.Component` behaviour) with the value from the last rendered tree
  and the cursor it manages (in `Tuix.App` `private`), then reports value
  changes to the app as `%Tuix.Event.Input{}` events. Keys the input does
  not handle fall through to the app's `c:Tuix.App.handle_event/2` with
  `target` set.

  Cursor offsets are grapheme indices (`0..String.length(value)`), so wide
  characters (CJK, emoji) count as one position.
  """

  @behaviour Tuix.Component

  alias Tuix.Buffer
  alias Tuix.Event
  alias Tuix.Event.Key

  @typedoc "A grapheme offset into the value, `0..String.length(value)`."
  @type cursor :: non_neg_integer()

  @impl Tuix.Component
  def on_key(%Key{} = key, props, state) do
    value = Map.get(props, :value, "")
    cursor = normalize_cursor(state, value)

    case edit(value, cursor, key) do
      {:changed, new_value, new_cursor} ->
        {:emit, %Event.Input{id: Map.get(props, :id), value: new_value}, new_cursor}

      {:moved, new_cursor} ->
        {:update, new_cursor}

      :ignored ->
        :ignored
    end
  end

  @impl Tuix.Component
  def mark_props(props, state) do
    %{cursor: normalize_cursor(state, Map.get(props, :value, ""))}
  end

  # The stored cursor clamped to the value (the app may have shortened it),
  # defaulting to the end of the value on first focus.
  defp normalize_cursor(nil, value), do: String.length(value)
  defp normalize_cursor(cursor, value), do: min(cursor, String.length(value))

  @typedoc """
  The result of applying a key:

    * `{:changed, value, cursor}` - the value changed
    * `{:moved, cursor}` - only the cursor changed (or a consumed no-op,
      e.g. backspace at the start)
    * `:ignored` - the input does not handle this key; it falls through
      to the app
  """
  @type result :: {:changed, String.t(), cursor()} | {:moved, cursor()} | :ignored

  @doc """
  Applies a key event to `value` at `cursor` (clamped to the value length).

  Handled keys: printable graphemes and `:space` (insert), `:backspace`,
  `:delete`, `:left`, `:right`, `:home`, `:end`. Ctrl- and alt-modified
  keys, and everything else (`:enter`, `:escape`, `:up`, ...), are
  `:ignored`.
  """
  @spec edit(String.t(), cursor(), Key.t()) :: result()
  def edit(value, cursor, %Key{} = key) do
    graphemes = String.graphemes(value)
    cursor = cursor |> min(length(graphemes)) |> max(0)
    do_edit(graphemes, cursor, key)
  end

  defp do_edit(_graphemes, _cursor, %Key{ctrl: true}), do: :ignored
  defp do_edit(_graphemes, _cursor, %Key{alt: true}), do: :ignored

  defp do_edit(graphemes, cursor, %Key{key: :space}), do: insert(graphemes, cursor, " ")

  defp do_edit(graphemes, cursor, %Key{key: key}) when is_binary(key),
    do: insert(graphemes, cursor, key)

  defp do_edit(graphemes, cursor, %Key{key: :backspace}) do
    if cursor > 0 do
      {:changed, delete_at(graphemes, cursor - 1), cursor - 1}
    else
      {:moved, cursor}
    end
  end

  defp do_edit(graphemes, cursor, %Key{key: :delete}) do
    if cursor < length(graphemes) do
      {:changed, delete_at(graphemes, cursor), cursor}
    else
      {:moved, cursor}
    end
  end

  defp do_edit(_graphemes, cursor, %Key{key: :left}), do: {:moved, max(cursor - 1, 0)}

  defp do_edit(graphemes, cursor, %Key{key: :right}),
    do: {:moved, min(cursor + 1, length(graphemes))}

  defp do_edit(_graphemes, _cursor, %Key{key: :home}), do: {:moved, 0}
  defp do_edit(graphemes, _cursor, %Key{key: :end}), do: {:moved, length(graphemes)}

  defp do_edit(_graphemes, _cursor, _key), do: :ignored

  defp insert(graphemes, cursor, string) do
    value = graphemes |> List.insert_at(cursor, string) |> IO.iodata_to_binary()
    {:changed, value, cursor + String.length(string)}
  end

  defp delete_at(graphemes, index) do
    graphemes |> List.delete_at(index) |> IO.iodata_to_binary()
  end

  @doc """
  Computes the horizontally scrolled display window for a focused input.

  Returns `{prefix, at_cursor, suffix}`: the visible text before the cursor
  (scrolled so the cursor cell fits within `width` columns), the grapheme
  under the cursor (`" "` when the cursor is at the end), and the remaining
  text (clipped by the paint rect).
  """
  @spec window(String.t(), cursor(), non_neg_integer()) ::
          {String.t(), String.t(), String.t()}
  def window(value, cursor, width) do
    graphemes = String.graphemes(value)
    cursor = cursor |> min(length(graphemes)) |> max(0)
    {before, rest} = Enum.split(graphemes, cursor)

    {at_cursor, suffix} =
      case rest do
        [] -> {" ", []}
        [grapheme | tail] -> {grapheme, tail}
      end

    prefix = scroll(before, width - Buffer.grapheme_width(at_cursor))

    {IO.iodata_to_binary(prefix), at_cursor, IO.iodata_to_binary(suffix)}
  end

  # Drops graphemes from the front until the tail fits in `budget` columns.
  defp scroll(_graphemes, budget) when budget <= 0, do: []

  defp scroll(graphemes, budget) do
    total = graphemes |> Enum.map(&Buffer.grapheme_width/1) |> Enum.sum()
    do_scroll(graphemes, total, budget)
  end

  defp do_scroll(graphemes, total, budget) when total <= budget, do: graphemes

  defp do_scroll([grapheme | rest], total, budget),
    do: do_scroll(rest, total - Buffer.grapheme_width(grapheme), budget)

  defp do_scroll([], _total, _budget), do: []
end
