defmodule Tuix.HitTest do
  @moduledoc """
  Maps pointer coordinates to elements: which element is under the mouse.

  Pure functions over the `Tuix.Layout.Placed` tree from the last layout,
  mirroring the renderer's painting model: children are searched in
  reverse document order (later siblings paint on top), a point only hits
  a descendant when it also hits every ancestor, and scroll box children
  are tested in content space — the pointer translated down by the scroll
  offset and clipped to the viewport.
  """

  alias Tuix.Components.ScrollBox
  alias Tuix.Element
  alias Tuix.Layout.Placed

  @doc """
  The id of the innermost focusable element under `{x, y}`, or `nil`.

  Focusable means `focusable: true` with an `:id` prop, exactly as in
  `Tuix.Focus`. When focusables overlap, the deepest match in the last
  painted (topmost) subtree wins. Coordinates are 0-based cells.
  """
  @spec focusable_at(Placed.t() | nil, {integer(), integer()}) :: term() | nil
  def focusable_at(nil, _point), do: nil
  def focusable_at(%Placed{} = placed, {x, y}), do: hit(placed, x, y, &focusable_id/1)

  @doc """
  The id of the innermost scroll box under `{x, y}`, or `nil`.

  The whole rect counts — border and scrollbar included, not just the
  inner viewport. Used by the runtime to route mouse-wheel events.
  """
  @spec scroll_box_at(Placed.t() | nil, {integer(), integer()}) :: term() | nil
  def scroll_box_at(nil, _point), do: nil
  def scroll_box_at(%Placed{} = placed, {x, y}), do: hit(placed, x, y, &scroll_box_id/1)

  defp hit(%Placed{rect: rect} = placed, x, y, matcher) do
    if contains?(rect, x, y) do
      child_hit(placed, x, y, matcher) || matcher.(placed.element)
    end
  end

  # Scroll box children rects are stored unscrolled (the renderer shifts
  # them up by the offset at paint time), so the pointer is translated
  # down by the same offset — and hits nothing when outside the viewport.
  defp child_hit(
         %Placed{element: %Element{tag: :scroll_box, props: props}, rect: rect} = placed,
         x,
         y,
         matcher
       ) do
    {_vx, vy, _vw, vh} = viewport = ScrollBox.viewport(props, rect)
    content_h = ScrollBox.content_height(placed.children, vy)
    offset = ScrollBox.resolve_offset(props, content_h, vh)

    if contains?(viewport, x, y) do
      find_in_children(placed.children, x, y + offset, matcher)
    end
  end

  defp child_hit(%Placed{children: children}, x, y, matcher) do
    find_in_children(children, x, y, matcher)
  end

  defp find_in_children(children, x, y, matcher) do
    children
    |> Enum.reverse()
    |> Enum.find_value(&hit(&1, x, y, matcher))
  end

  defp focusable_id(%Element{props: props}) do
    if Map.get(props, :focusable, false), do: Map.get(props, :id)
  end

  # :id is guaranteed: build_scroll_box/2 raises without one.
  defp scroll_box_id(%Element{tag: :scroll_box, props: props}), do: Map.get(props, :id)
  defp scroll_box_id(%Element{}), do: nil

  defp contains?({rx, ry, rw, rh}, x, y) do
    x >= rx and x < rx + rw and y >= ry and y < ry + rh
  end
end
