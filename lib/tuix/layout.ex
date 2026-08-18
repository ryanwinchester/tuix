defmodule Tuix.Layout do
  @moduledoc """
  Flexbox-subset layout engine.

  Resolves an element tree against a viewport into a tree of
  `Tuix.Layout.Placed` nodes with absolute `{x, y, w, h}` rectangles.

  Supported: `:flex_direction` (`:row` / `:column`), `:gap`, `:padding`,
  border insets, fixed and percentage sizes, `:flex_grow`, and cross-axis
  stretch (the default for boxes without an explicit cross size).

  Scroll boxes (`:scroll_box`) lay their children out in a column at full
  content height; the renderer scrolls and clips them to the viewport.

  Not yet supported: wrapping, `justify_content` / `align_items` variants.
  """

  alias Tuix.Buffer
  alias Tuix.Components.Select
  alias Tuix.Element

  @leaf_tags [:text, :input, :select]

  defmodule Placed do
    @moduledoc "An element resolved to an absolute rectangle."

    defstruct [:element, :rect, children: []]

    @type rect :: {integer(), integer(), non_neg_integer(), non_neg_integer()}
    @type t :: %__MODULE__{element: Element.t(), rect: rect(), children: [t()]}
  end

  @doc """
  Computes layout for an element tree within a `width` x `height` viewport.

  The root element behaves like the child of an implicit full-screen column
  box: explicit sizes are honored, otherwise it sizes to content, and its
  width stretches to the viewport (standard flexbox stretch).
  """
  @spec compute(Element.t(), pos_integer(), pos_integer()) :: Placed.t()
  def compute(%Element{} = element, width, height) do
    w = resolve_size(element, :width, width) || width
    h = resolve_size(element, :height, height) || min(intrinsic(element, :height, width), height)

    place(element, {0, 0, min(w, width), min(h, height)})
  end

  # Places an element at an exact rectangle and lays out its children inside.
  defp place(%Element{tag: tag} = element, rect) when tag in @leaf_tags do
    %Placed{element: element, rect: rect}
  end

  defp place(%Element{tag: :box} = element, {x, y, w, h} = rect) do
    inset = border_inset(element) + padding(element)
    content = {x + inset, y + inset, max(w - 2 * inset, 0), max(h - 2 * inset, 0)}

    direction = direction(element)
    children = flex(element.children, content, direction, gap(element))

    %Placed{element: element, rect: rect, children: children}
  end

  # Scroll boxes lay their children out in a column at full content height
  # (nothing is clamped to the visible viewport); the renderer shifts the
  # children by the scroll offset and clips them to the viewport.
  defp place(%Element{tag: :scroll_box} = element, {x, y, w, h} = rect) do
    inset = border_inset(element) + padding(element)
    {cx, cy, cw, ch} = {x + inset, y + inset, max(w - 2 * inset, 0), max(h - 2 * inset, 0)}

    gap = gap(element)
    content_h = content_height(element.children, cw, gap)

    # Without a border or padding, the rect's rightmost column is reserved
    # for the scrollbar when the content overflows (bordered or padded
    # scroll boxes draw the scrollbar over that column anyway).
    cw = if inset == 0 and content_h > ch, do: max(cw - 1, 0), else: cw

    children = flex(element.children, {cx, cy, cw, content_h}, :column, gap)

    %Placed{element: element, rect: rect, children: children}
  end

  # Lays out children along the main axis inside the content rect.
  defp flex([], _content, _direction, _gap), do: []

  defp flex(children, {cx, cy, cw, ch}, direction, gap) do
    {main_avail, cross_avail} =
      case direction do
        :row -> {cw, ch}
        :column -> {ch, cw}
      end

    gap_total = gap * (length(children) - 1)

    # First pass: resolve fixed main sizes; flex_grow children get nil.
    sized =
      Enum.map(children, fn child ->
        cond do
          grow(child) > 0 -> {child, nil}
          true -> {child, main_size(child, direction, main_avail, cross_avail)}
        end
      end)

    fixed_total = sized |> Enum.map(&(elem(&1, 1) || 0)) |> Enum.sum()
    leftover = max(main_avail - fixed_total - gap_total, 0)
    grow_total = children |> Enum.map(&grow/1) |> Enum.sum()

    # Second pass: distribute leftover among flex_grow children.
    {sized, _remaining} =
      Enum.map_reduce(sized, leftover, fn
        {child, nil}, remaining ->
          share =
            if grow_total > 0,
              do: min(div(leftover * grow(child), grow_total), remaining),
              else: 0

          {{child, share}, remaining - share}

        {child, size}, remaining ->
          {{child, size}, remaining}
      end)

    # Third pass: position sequentially along the main axis.
    {placed, _offset} =
      Enum.map_reduce(sized, 0, fn {child, main}, offset ->
        cross = cross_size(child, direction, cross_avail, main)

        rect =
          case direction do
            :row -> {cx + offset, cy, clamp(main, cw - offset), min(cross, ch)}
            :column -> {cx, cy + offset, min(cross, cw), clamp(main, ch - offset)}
          end

        {place(child, rect), offset + main + gap}
      end)

    placed
  end

  # Main-axis size of a child: explicit prop, else intrinsic.
  defp main_size(child, :row, avail, cross_avail),
    do: resolve_size(child, :width, avail) || intrinsic(child, :width, cross_avail)

  defp main_size(child, :column, avail, cross_avail),
    do: resolve_size(child, :height, avail) || intrinsic(child, :height, cross_avail)

  # Cross-axis size: explicit prop, else stretch for boxes / intrinsic for
  # leaves (text, input, select).
  defp cross_size(%Element{tag: tag} = child, :row, avail, _main) when tag in @leaf_tags,
    do: resolve_size(child, :height, avail) || min(intrinsic(child, :height, avail), avail)

  defp cross_size(%Element{tag: tag} = child, :column, avail, _main) when tag in @leaf_tags,
    do: resolve_size(child, :width, avail) || min(intrinsic(child, :width, avail), avail)

  defp cross_size(child, :row, avail, _main), do: resolve_size(child, :height, avail) || avail
  defp cross_size(child, :column, avail, _main), do: resolve_size(child, :width, avail) || avail

  # Intrinsic (content-driven) size along a dimension.
  defp intrinsic(%Element{tag: :text} = element, :width, _cross) do
    element |> lines() |> Enum.map(&Buffer.text_width/1) |> Enum.max(fn -> 0 end)
  end

  defp intrinsic(%Element{tag: :text} = element, :height, _cross) do
    element |> lines() |> length()
  end

  # Inputs are single-row leaves; intrinsic width leaves room for the
  # end-of-value cursor.
  defp intrinsic(%Element{tag: :input, props: props}, :width, _cross) do
    value = Map.get(props, :value, "")
    placeholder = Map.get(props, :placeholder, "")
    max(Buffer.text_width(value), Buffer.text_width(placeholder)) + 1
  end

  defp intrinsic(%Element{tag: :input}, :height, _cross), do: 1

  # Selects render one option per row; width fits the marker plus the
  # widest label.
  defp intrinsic(%Element{tag: :select, props: props}, :width, _cross) do
    labels_max =
      props
      |> Select.options()
      |> Enum.map(fn {label, _value} -> Buffer.text_width(label) end)
      |> Enum.max(fn -> 0 end)

    Select.marker_width(props) + labels_max
  end

  defp intrinsic(%Element{tag: :select, props: props}, :height, _cross),
    do: props |> Select.options() |> length()

  defp intrinsic(%Element{tag: tag} = element, dimension, cross)
       when tag in [:box, :scroll_box] do
    inset = 2 * (border_inset(element) + padding(element))
    direction = direction(element)
    children = element.children

    main_dimension = if direction == :row, do: :width, else: :height

    child_sizes =
      Enum.map(children, fn child ->
        resolve_size(child, dimension, 0) || intrinsic(child, dimension, cross)
      end)

    content =
      cond do
        children == [] ->
          0

        dimension == main_dimension ->
          Enum.sum(child_sizes) + gap(element) * (length(children) - 1)

        true ->
          Enum.max(child_sizes, fn -> 0 end)
      end

    content + inset
  end

  # Resolves an explicit :width/:height prop against the available space.
  defp resolve_size(%Element{props: props}, key, avail) do
    case Map.get(props, key) do
      nil -> nil
      n when is_integer(n) -> n
      {:percent, pct} -> percent(pct, avail)
      binary when is_binary(binary) -> binary |> parse_percent!() |> percent(avail)
    end
  end

  defp parse_percent!(binary) do
    case Integer.parse(binary) do
      {n, "%"} -> n
      _ -> raise ArgumentError, "invalid size: #{inspect(binary)} (expected e.g. \"50%\")"
    end
  end

  defp percent(pct, avail), do: div(avail * pct, 100)

  defp clamp(size, max_size), do: size |> min(max_size) |> max(0)

  # The full height of a scroll box's content: its children stacked in a
  # column, unbounded by the visible viewport.
  defp content_height([], _cross, _gap), do: 0

  defp content_height(children, cross, gap) do
    heights =
      Enum.map(children, fn child ->
        resolve_size(child, :height, 0) || intrinsic(child, :height, cross)
      end)

    Enum.sum(heights) + gap * (length(children) - 1)
  end

  defp direction(%Element{tag: :scroll_box}), do: :column
  defp direction(%Element{props: props}), do: Map.get(props, :flex_direction, :column)
  defp gap(%Element{props: props}), do: Map.get(props, :gap, 0)
  defp padding(%Element{props: props}), do: Map.get(props, :padding, 0)
  defp grow(%Element{props: props}), do: Map.get(props, :flex_grow, 0)

  defp border_inset(%Element{props: props}) do
    case Map.get(props, :border, :none) do
      :none -> 0
      false -> 0
      _ -> 1
    end
  end

  defp lines(%Element{props: props}) do
    props |> Map.get(:content, "") |> String.split("\n")
  end
end
