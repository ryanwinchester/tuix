defmodule Tuix.Components.Select do
  @moduledoc """
  The behaviour implementation and pure helpers behind
  `Tuix.Components.select/1`, a vertical list picker.

  Selects are controlled and stateless: the selection follows the highlight,
  so `:up` / `:down` / `:home` / `:end` emit `%Tuix.Event.Select{}` with the
  new value immediately, and the highlighted row is simply the option
  matching `props.value` — owned by the app. Navigation is clamped (no
  wrap-around); boundary presses and empty option lists are consumed.
  Everything else (`:enter`, `:space`, ctrl combos) falls through to the
  app with `target` set, so commit-on-Enter flows are one
  `%Key{key: :enter, target: id}` clause away.
  """

  @behaviour Tuix.Component

  alias Tuix.Buffer
  alias Tuix.Event
  alias Tuix.Event.Key

  @impl Tuix.Component
  def on_key(%Key{ctrl: true}, _props, _state), do: :ignored
  def on_key(%Key{alt: true}, _props, _state), do: :ignored

  def on_key(%Key{key: key}, props, state) when key in [:up, :down, :home, :end] do
    options = options(props)
    count = length(options)

    if count == 0 do
      {:update, state}
    else
      index = selected_index(options, Map.get(props, :value))

      new_index =
        case {key, index} do
          {:home, _index} -> 0
          {:end, _index} -> count - 1
          {_key, nil} -> 0
          {:up, index} -> max(index - 1, 0)
          {:down, index} -> min(index + 1, count - 1)
        end

      if new_index == index do
        {:update, state}
      else
        {_label, value} = Enum.at(options, new_index)
        {:emit, %Event.Select{id: Map.get(props, :id), value: value}, state}
      end
    end
  end

  def on_key(%Key{}, _props, _state), do: :ignored

  @impl Tuix.Component
  def mark_props(_props, _state), do: %{}

  @doc """
  Normalizes the `:options` prop to `{label, value}` tuples. Bare strings
  are their own value.
  """
  @spec options(map()) :: [{String.t(), term()}]
  def options(props) do
    props
    |> Map.get(:options, [])
    |> Enum.map(fn
      {label, value} -> {label, value}
      label when is_binary(label) -> {label, label}
    end)
  end

  @doc """
  The index of the option whose value matches, or `nil`.
  """
  @spec selected_index([{String.t(), term()}], term()) :: non_neg_integer() | nil
  def selected_index(options, value) do
    Enum.find_index(options, fn {_label, option_value} -> option_value == value end)
  end

  @doc """
  The scroll offset (in rows) that keeps the selected row visible in
  `height` rows: `max(0, selected - height + 1)`, clamped so the window
  never extends past the last option. Pure — like an input's horizontal
  scroll, no stored state.
  """
  @spec offset(non_neg_integer() | nil, non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def offset(_selected, count, height) when height <= 0 or count <= height, do: 0
  def offset(nil, _count, _height), do: 0

  def offset(selected, count, height) do
    (selected - height + 1)
    |> max(0)
    |> min(count - height)
  end

  @doc """
  The display width of the marker prefix for the given props.
  """
  @spec marker(map()) :: String.t()
  def marker(props), do: Map.get(props, :marker, "❯ ")

  @doc false
  @spec marker_width(map()) :: non_neg_integer()
  def marker_width(props), do: props |> marker() |> Buffer.text_width()
end
