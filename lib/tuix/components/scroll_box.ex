defmodule Tuix.Components.ScrollBox do
  @moduledoc """
  The behaviour implementation and pure helpers behind
  `Tuix.Components.scroll_box/2`, a focusable, vertically scrolling
  container.

  Scroll boxes are built on the focus model: focus one (Tab traversal or
  `autofocus`) and `:up` / `:down` scroll by a row, `:page_up` /
  `:page_down` by a viewport, and `:home` / `:end` jump to the boundaries.
  The offset is ephemeral framework state (like an input's cursor): no
  event reaches the app and there is nothing to assign back. Scrolling is
  clamped (boundary presses are consumed); everything else falls through
  to the app with `target` set.

  The stored state is `%{offset: n, viewport: h, max_offset: m}` — the
  runtime refreshes `viewport` and `max_offset` from each layout (see
  `Tuix.Runtime`), so `on_key/3` can page and clamp without recomputing
  layout. With `snap: :bottom`, a box whose offset sits at `max_offset`
  is pinned: it stays at the bottom as content grows.
  """

  @behaviour Tuix.Component

  alias Tuix.Event.Key
  alias Tuix.Layout.Placed

  @typedoc """
  The framework-managed scroll state: the current offset (rows scrolled
  past the top), the viewport height, and the scrollable range — the
  latter two measured by the last layout.
  """
  @type state :: %{
          offset: non_neg_integer(),
          viewport: non_neg_integer(),
          max_offset: non_neg_integer()
        }

  @impl Tuix.Component
  def on_key(%Key{ctrl: true}, _props, _state), do: :ignored
  def on_key(%Key{alt: true}, _props, _state), do: :ignored

  def on_key(%Key{key: key}, _props, state)
      when key in [:up, :down, :page_up, :page_down, :home, :end] do
    %{offset: offset, viewport: viewport, max_offset: max_offset} = state = normalize(state)

    new_offset =
      case key do
        :up -> offset - 1
        :down -> offset + 1
        :page_up -> offset - viewport
        :page_down -> offset + viewport
        :home -> 0
        :end -> max_offset
      end
      |> min(max_offset)
      |> max(0)

    {:update, %{state | offset: new_offset}}
  end

  def on_key(%Key{}, _props, _state), do: :ignored

  @impl Tuix.Component
  def mark_props(props, state) do
    %{offset: offset, max_offset: max_offset} = normalize(state)

    if snap_bottom?(props) and offset >= max_offset do
      %{scroll_offset: :bottom}
    else
      %{scroll_offset: offset}
    end
  end

  # Unsynced state (before the first layout) behaves like an unscrolled,
  # degenerate viewport: navigation keys are consumed no-ops.
  defp normalize(nil), do: %{offset: 0, viewport: 0, max_offset: 0}
  defp normalize(%{} = state), do: state

  @doc """
  Resolves the paint-time scroll offset from the marked props: the
  framework-injected `:scroll_offset` (an integer, or `:bottom` for a box
  pinned by `snap: :bottom`) clamped to the scrollable range. Without a
  stored offset, `snap: :bottom` boxes start at the bottom.
  """
  @spec resolve_offset(map(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def resolve_offset(props, content_height, viewport_height) do
    max_offset = max_offset(content_height, viewport_height)

    case Map.get(props, :scroll_offset) do
      nil -> if snap_bottom?(props), do: max_offset, else: 0
      :bottom -> max_offset
      offset when is_integer(offset) -> offset |> min(max_offset) |> max(0)
    end
  end

  @doc """
  The scrollable range: how far the content extends past the viewport.
  """
  @spec max_offset(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def max_offset(content_height, viewport_height),
    do: max(content_height - viewport_height, 0)

  @doc """
  Scrollbar thumb geometry: `{row, height}` within a `track_height`-row
  track. The thumb height is the visible share of the content (at least
  one row), and its row is proportional to the offset — exactly at the
  end of the track when fully scrolled.
  """
  @spec thumb(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def thumb(_offset, _content_height, _viewport_height, track_height) when track_height <= 0,
    do: {0, 0}

  def thumb(offset, content_height, viewport_height, track_height) do
    height =
      (track_height * viewport_height)
      |> div(max(content_height, 1))
      |> max(1)
      |> min(track_height)

    row =
      case max_offset(content_height, viewport_height) do
        0 -> 0
        max_offset -> round((track_height - height) * min(offset, max_offset) / max_offset)
      end

    {row, height}
  end

  @doc false
  # The viewport (content area) rect: the box rect inset by border and
  # padding. Shared by the renderer and the runtime's state sync.
  @spec viewport(map(), Placed.rect()) :: Placed.rect()
  def viewport(props, {x, y, w, h}) do
    inset = inset(props)
    {x + inset, y + inset, max(w - 2 * inset, 0), max(h - 2 * inset, 0)}
  end

  @doc false
  # The full content height: how far the placed (unscrolled) children
  # extend below the viewport's top edge.
  @spec content_height([Placed.t()], integer()) :: non_neg_integer()
  def content_height(children, viewport_y) do
    children
    |> Enum.map(fn %Placed{rect: {_x, y, _w, h}} -> y + h end)
    |> Enum.max(fn -> viewport_y end)
    |> Kernel.-(viewport_y)
    |> max(0)
  end

  defp inset(props) do
    padding = Map.get(props, :padding, 0)

    case Map.get(props, :border, :none) do
      :none -> padding
      false -> padding
      _ -> padding + 1
    end
  end

  defp snap_bottom?(props), do: Map.get(props, :snap) == :bottom
end
