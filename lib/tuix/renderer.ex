defmodule Tuix.Renderer do
  @moduledoc """
  Paints a placed element tree into a `Tuix.Buffer` and serializes frames
  (or frame diffs) into ANSI iodata.
  """

  alias Tuix.Buffer
  alias Tuix.Cell
  alias Tuix.Color
  alias Tuix.Components.Input, as: TextInput
  alias Tuix.Components.ScrollBox
  alias Tuix.Components.Select, as: ListSelect
  alias Tuix.Element
  alias Tuix.Layout.Placed
  alias Tuix.Terminal.ANSI

  @borders %{
    single: {"┌", "─", "┐", "│", "└", "┘"},
    rounded: {"╭", "─", "╮", "│", "╰", "╯"},
    double: {"╔", "═", "╗", "║", "╚", "╝"}
  }

  @doc """
  Renders an element tree at the given size: layout + paint.
  """
  @spec render(Element.t(), pos_integer(), pos_integer()) :: Buffer.t()
  def render(%Element{} = element, width, height) do
    placed = Tuix.Layout.compute(element, width, height)
    paint(placed, Buffer.new(width, height))
  end

  @doc """
  Paints a placed tree into a buffer.
  """
  @spec paint(Placed.t(), Buffer.t()) :: Buffer.t()
  def paint(%Placed{} = placed, %Buffer{} = buffer) do
    do_paint(placed, buffer, {0, 0, buffer.width, buffer.height})
  end

  defp do_paint(
         %Placed{element: %Element{tag: :box} = element, rect: rect} = placed,
         buffer,
         clip
       ) do
    clip = intersect(clip, rect)

    buffer
    |> paint_background(element, rect, clip)
    |> paint_border(element, rect, clip)
    |> paint_children(placed.children, clip)
  end

  defp do_paint(
         %Placed{element: %Element{tag: :scroll_box} = element, rect: rect} = placed,
         buffer,
         clip
       ) do
    clip = intersect(clip, rect)
    props = element.props

    {_vx, vy, _vw, vh} = viewport = ScrollBox.viewport(props, rect)
    content_h = ScrollBox.content_height(placed.children, vy)
    offset = ScrollBox.resolve_offset(props, content_h, vh)

    buffer
    |> paint_background(element, rect, clip)
    |> paint_border(element, rect, clip)
    |> paint_children(scroll(placed.children, offset), intersect(clip, viewport))
    |> paint_scrollbar(element, rect, vh, content_h, offset, clip)
  end

  defp do_paint(%Placed{element: %Element{tag: :text} = element, rect: rect}, buffer, clip) do
    {x, y, _w, _h} = rect
    clip = intersect(clip, rect)

    style = [
      fg: Map.get(element.props, :fg),
      bg: Map.get(element.props, :bg),
      attrs: Map.get(element.props, :attrs, [])
    ]

    element.props
    |> Map.get(:content, "")
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {line, index}, buf ->
      Buffer.put_text(buf, x, y + index, line, style, clip)
    end)
  end

  defp do_paint(
         %Placed{element: %Element{tag: :input} = element, rect: rect},
         buffer,
         clip
       ) do
    {x, y, w, _h} = rect
    clip = intersect(clip, rect)
    props = element.props

    value = display_value(props)

    style = [
      fg: Map.get(props, :fg),
      bg: background(props),
      attrs: Map.get(props, :attrs, [])
    ]

    buffer = paint_background(buffer, element, rect, clip)

    cond do
      Map.get(props, :focused, false) ->
        cursor = Map.get(props, :cursor, String.length(value))
        {prefix, at_cursor, suffix} = TextInput.window(value, cursor, w)
        prefix_width = Buffer.text_width(prefix)
        cursor_style = Keyword.update!(style, :attrs, &[:reverse | &1])

        buffer
        |> Buffer.put_text(x, y, prefix, style, clip)
        |> Buffer.put_text(x + prefix_width, y, at_cursor, cursor_style, clip)
        |> Buffer.put_text(
          x + prefix_width + Buffer.grapheme_width(at_cursor),
          y,
          suffix,
          style,
          clip
        )

      value == "" ->
        placeholder_style = [
          fg: Map.get(props, :placeholder_color, :bright_black),
          bg: background(props)
        ]

        Buffer.put_text(buffer, x, y, Map.get(props, :placeholder, ""), placeholder_style, clip)

      true ->
        Buffer.put_text(buffer, x, y, value, style, clip)
    end
  end

  defp do_paint(
         %Placed{element: %Element{tag: :select} = element, rect: rect},
         buffer,
         clip
       ) do
    {x, y, _w, h} = rect
    clip = intersect(clip, rect)
    props = element.props

    options = ListSelect.options(props)
    selected = ListSelect.selected_index(options, Map.get(props, :value))
    offset = ListSelect.offset(selected, length(options), h)

    marker = ListSelect.marker(props)
    pad = String.duplicate(" ", ListSelect.marker_width(props))

    style = [
      fg: Map.get(props, :fg),
      bg: background(props),
      attrs: Map.get(props, :attrs, [])
    ]

    selected_style = [
      fg: Map.get(props, :selected_fg) || Map.get(props, :fg),
      bg: background(props),
      attrs: Map.get(props, :selected_attrs, [:bold])
    ]

    buffer = paint_background(buffer, element, rect, clip)

    options
    |> Enum.drop(offset)
    |> Enum.take(max(h, 0))
    |> Enum.with_index(offset)
    |> Enum.reduce(buffer, fn {{label, _value}, index}, buf ->
      if index == selected do
        Buffer.put_text(buf, x, y + index - offset, marker <> label, selected_style, clip)
      else
        Buffer.put_text(buf, x, y + index - offset, pad <> label, style, clip)
      end
    end)
  end

  defp display_value(props) do
    value = Map.get(props, :value, "")

    case Map.get(props, :mask) do
      nil -> value
      mask -> String.duplicate(mask, String.length(value))
    end
  end

  defp paint_children(buffer, children, clip) do
    Enum.reduce(children, buffer, &do_paint(&1, &2, clip))
  end

  # Shifts a scroll box's children up by the scroll offset; the viewport
  # clip drops whatever falls outside.
  defp scroll(children, 0), do: children
  defp scroll(children, offset), do: Enum.map(children, &translate(&1, -offset))

  defp translate(%Placed{rect: {x, y, w, h}, children: children} = placed, dy) do
    %{placed | rect: {x, y + dy, w, h}, children: Enum.map(children, &translate(&1, dy))}
  end

  @scrollbar_track "│"
  @scrollbar_thumb "█"

  # Paints the scrollbar in the rect's rightmost column when the content
  # overflows: over the border when the box has one (the border verticals
  # already form the track), otherwise as a track + thumb.
  defp paint_scrollbar(buffer, _element, _rect, viewport_h, content_h, _offset, _clip)
       when content_h <= viewport_h,
       do: buffer

  defp paint_scrollbar(
         buffer,
         %Element{props: props},
         {x, y, w, h},
         viewport_h,
         content_h,
         offset,
         clip
       ) do
    bar_x = x + w - 1
    bordered? = border_style(props) != nil
    {track_y, track_h} = if bordered?, do: {y + 1, max(h - 2, 0)}, else: {y, h}

    {thumb_row, thumb_h} = ScrollBox.thumb(offset, content_h, viewport_h, track_h)
    style = [fg: border_color(props), bg: background(props)]

    buffer =
      if bordered? do
        buffer
      else
        Enum.reduce(track_y..(track_y + track_h - 1)//1, buffer, fn row, buf ->
          Buffer.put_text(buf, bar_x, row, @scrollbar_track, style, clip)
        end)
      end

    thumb_y = track_y + thumb_row

    Enum.reduce(thumb_y..(thumb_y + thumb_h - 1)//1, buffer, fn row, buf ->
      Buffer.put_text(buf, bar_x, row, @scrollbar_thumb, style, clip)
    end)
  end

  defp paint_background(buffer, %Element{props: props}, rect, clip) do
    case background(props) do
      nil -> buffer
      bg -> Buffer.fill(buffer, intersect(clip, rect), %Cell{char: " ", bg: bg})
    end
  end

  defp paint_border(buffer, %Element{props: props} = element, {x, y, w, h}, clip) do
    style = border_style(props)

    case {style, w >= 2 and h >= 2} do
      {nil, _} ->
        buffer

      {_style, false} ->
        buffer

      {style, true} ->
        {tl, horizontal, tr, vertical, bl, br} = Map.fetch!(@borders, style)
        color = border_color(props)
        bg = background(props)
        text_style = [fg: color, bg: bg]

        buffer =
          buffer
          |> Buffer.put_text(x, y, tl, text_style, clip)
          |> Buffer.put_repeat(x + 1, y, horizontal, w - 2, text_style, clip)
          |> Buffer.put_text(x + w - 1, y, tr, text_style, clip)
          |> Buffer.put_text(x, y + h - 1, bl, text_style, clip)
          |> Buffer.put_repeat(x + 1, y + h - 1, horizontal, w - 2, text_style, clip)
          |> Buffer.put_text(x + w - 1, y + h - 1, br, text_style, clip)

        buffer =
          Enum.reduce((y + 1)..(y + h - 2)//1, buffer, fn row, buf ->
            buf
            |> Buffer.put_text(x, row, vertical, text_style, clip)
            |> Buffer.put_text(x + w - 1, row, vertical, text_style, clip)
          end)

        paint_title(buffer, element, {x, y, w, h}, text_style, clip)
    end
  end

  defp paint_title(buffer, %Element{props: props}, {x, y, w, _h}, style, clip) do
    case Map.get(props, :title) do
      nil ->
        buffer

      title ->
        label = " " <> title <> " "
        max_width = max(w - 4, 0)
        label = clip_text(label, max_width)
        Buffer.put_text(buffer, x + 2, y, label, style, clip)
    end
  end

  defp clip_text(text, max_width) do
    text
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {acc, width} ->
      grapheme_width = Buffer.grapheme_width(grapheme)

      if width + grapheme_width > max_width do
        {:halt, {acc, width}}
      else
        {:cont, {[grapheme | acc], width + grapheme_width}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp border_style(props) do
    case Map.get(props, :border, :none) do
      :none -> nil
      false -> nil
      true -> :single
      style when is_map_key(@borders, style) -> style
    end
  end

  # Focused elements (marked by the runtime or Tuix.Focus.mark/3) prefer
  # their focus_* style props. Ancestors of the focused element
  # (focus_within) prefer focus_within_*, falling back to focus_*.
  defp background(props) do
    focus_style(props, :focus_within_bg, :focus_bg) || Map.get(props, :bg)
  end

  defp border_color(props) do
    focus_style(props, :focus_within_border_color, :focus_border_color) ||
      Map.get(props, :border_color) || Map.get(props, :fg)
  end

  defp focus_style(props, within_key, focus_key) do
    cond do
      Map.get(props, :focused, false) ->
        Map.get(props, focus_key)

      Map.get(props, :focus_within, false) ->
        Map.get(props, within_key) || Map.get(props, focus_key)

      true ->
        nil
    end
  end

  defp intersect({x1, y1, w1, h1}, {x2, y2, w2, h2}) do
    x = max(x1, x2)
    y = max(y1, y2)
    {x, y, max(min(x1 + w1, x2 + w2) - x, 0), max(min(y1 + h1, y2 + h2) - y, 0)}
  end

  ## Frame serialization

  @doc """
  Serializes the difference between two frames as ANSI iodata.

  With `old` as `nil`, serializes the full frame (preceded by a clear).

  Rows whose contents are unchanged are skipped with a single term
  comparison. Within a changed row, consecutive changed cells are emitted as
  runs (one cursor move per run), in a single pass over the row.
  """
  @spec to_iodata(Buffer.t(), Buffer.t() | nil) :: iodata()
  def to_iodata(new, old \\ nil)

  def to_iodata(%Buffer{} = new, nil) do
    [ANSI.clear_screen(), diff_rows(new, Buffer.new(new.width, new.height)), ANSI.reset()]
  end

  def to_iodata(%Buffer{} = new, %Buffer{} = old) do
    [diff_rows(new, old), ANSI.reset()]
  end

  @blank %Cell{}

  defp diff_rows(new, old) do
    for y <- 0..(new.height - 1)//1,
        new_row = Buffer.row(new, y) || %{},
        old_row = Buffer.row(old, y) || %{},
        new_row != old_row,
        do: diff_row(new_row, old_row, y, new.width)
  end

  # Walks a row once, accumulating changed cells into runs.
  # A run is `{start_x, current_style, iodata}` or `nil` when not in a run.
  defp diff_row(new_row, old_row, y, width),
    do: diff_cells(0, width, new_row, old_row, y, nil, [])

  defp diff_cells(x, width, _new_row, _old_row, y, run, acc) when x >= width do
    Enum.reverse(flush(run, y, acc))
  end

  defp diff_cells(x, width, new_row, old_row, y, run, acc) do
    new_cell = Map.get(new_row, x, @blank)

    if new_cell == Map.get(old_row, x, @blank) do
      diff_cells(x + 1, width, new_row, old_row, y, nil, flush(run, y, acc))
    else
      diff_cells(x + 1, width, new_row, old_row, y, extend_run(run, x, new_cell), acc)
    end
  end

  # A wide grapheme's continuation cell emits nothing: the head grapheme
  # already advances the cursor two columns.
  defp extend_run(nil, x, %Cell{char: :continuation}), do: {x, :none, []}
  defp extend_run(run, _x, %Cell{char: :continuation}), do: run

  defp extend_run(nil, x, %Cell{char: char} = cell) do
    {x, Cell.style(cell), [style_sequence(cell), char]}
  end

  defp extend_run({start_x, style, iodata}, _x, %Cell{char: char} = cell) do
    case Cell.style(cell) do
      ^style -> {start_x, style, [iodata, char]}
      new_style -> {start_x, new_style, [iodata, style_sequence(cell), char]}
    end
  end

  defp flush(nil, _y, acc), do: acc
  defp flush({_start_x, _style, []}, _y, acc), do: acc
  defp flush({start_x, _style, iodata}, y, acc), do: [[ANSI.move_to(start_x, y) | iodata] | acc]

  defp style_sequence(%Cell{fg: fg, bg: bg, attrs: attrs}) do
    codes =
      [0] ++
        Color.to_sgr(fg, :fg) ++
        Color.to_sgr(bg, :bg) ++
        Enum.map(attrs, &ANSI.attr_code/1)

    ANSI.sgr(codes)
  end
end
