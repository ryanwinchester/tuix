defmodule Tuix.Buffer do
  @moduledoc """
  A 2D grid of `Tuix.Cell`s representing one terminal frame.

  The grid is row-oriented and sparse: `rows` maps a row index to a map of
  column index to cell, and rows or cells that were never written are blank.
  Row orientation lets frame diffing skip unchanged rows with a single term
  comparison, which is the common case for incremental updates.

  Coordinates are 0-based with `{0, 0}` at the top-left.
  """

  alias Tuix.Cell

  @blank %Cell{}

  defstruct width: 0, height: 0, rows: %{}

  @type row :: %{non_neg_integer() => Cell.t()}
  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          rows: %{non_neg_integer() => row()}
        }

  @doc "Creates an empty buffer of the given size."
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(width, height), do: %__MODULE__{width: width, height: height}

  @doc "Returns the cell at `{x, y}`, or a blank cell if unset."
  @spec at(t(), non_neg_integer(), non_neg_integer()) :: Cell.t()
  def at(%__MODULE__{rows: rows}, x, y) do
    rows |> Map.get(y, %{}) |> Map.get(x, @blank)
  end

  @doc "Returns row `y` as a sparse column map, or `nil` if the row is blank."
  @spec row(t(), non_neg_integer()) :: row() | nil
  def row(%__MODULE__{rows: rows}, y), do: Map.get(rows, y)

  @doc "Puts a cell at `{x, y}`. Out-of-bounds writes are ignored."
  @spec put(t(), integer(), integer(), Cell.t()) :: t()
  def put(%__MODULE__{width: w, height: h} = buffer, x, y, _cell)
      when x < 0 or y < 0 or x >= w or y >= h,
      do: buffer

  def put(%__MODULE__{rows: rows} = buffer, x, y, %Cell{} = cell) do
    row = rows |> Map.get(y, %{}) |> Map.put(x, cell)
    %{buffer | rows: Map.put(rows, y, row)}
  end

  @doc """
  Writes a single-line string starting at `{x, y}`, clipped to `clip`
  (a `{cx, cy, cw, ch}` rectangle). Handles wide graphemes: a 2-column
  grapheme occupies its cell plus a `:continuation` cell.
  """
  @spec put_text(t(), integer(), integer(), String.t(), keyword(), tuple() | nil) :: t()
  def put_text(buffer, x, y, string, style \\ [], clip \\ nil)

  def put_text(
        %__MODULE__{width: width, height: height, rows: rows} = buffer,
        x,
        y,
        string,
        style,
        clip
      ) do
    {cx, cy, cw, ch} = clip || {0, 0, width, height}

    if y < max(cy, 0) or y >= min(cy + ch, height) do
      buffer
    else
      cell = %Cell{
        char: nil,
        fg: Keyword.get(style, :fg),
        bg: Keyword.get(style, :bg),
        attrs: Keyword.get(style, :attrs, [])
      }

      x_min = max(cx, 0)
      x_max = min(cx + cw, width) - 1

      row = Map.get(rows, y, %{})
      row = write_graphemes(string, x, row, cell, x_min, x_max)
      %{buffer | rows: Map.put(rows, y, row)}
    end
  end

  defp write_graphemes(<<>>, _x, row, _proto, _x_min, _x_max), do: row

  # Fast path: a printable ASCII byte not followed by a non-ASCII byte is a
  # complete single-width grapheme (combining marks are never ASCII), so we
  # can skip grapheme segmentation and width lookup entirely.
  defp write_graphemes(<<c, rest::binary>> = string, x, row, proto, x_min, x_max)
       when c >= 32 and c <= 126 do
    case rest do
      <<next, _::binary>> when next >= 128 ->
        write_grapheme(string, x, row, proto, x_min, x_max)

      _ ->
        row = if x >= x_min and x <= x_max, do: Map.put(row, x, %{proto | char: <<c>>}), else: row
        write_graphemes(rest, x + 1, row, proto, x_min, x_max)
    end
  end

  defp write_graphemes(string, x, row, proto, x_min, x_max) do
    write_grapheme(string, x, row, proto, x_min, x_max)
  end

  defp write_grapheme(string, x, row, proto, x_min, x_max) do
    {grapheme, rest} = String.next_grapheme(string)
    width = grapheme_width(grapheme)

    row =
      if x >= x_min and x + width - 1 <= x_max do
        row = Map.put(row, x, %{proto | char: grapheme})

        if width == 2 do
          Map.put(row, x + 1, %{proto | char: :continuation})
        else
          row
        end
      else
        row
      end

    write_graphemes(rest, x + width, row, proto, x_min, x_max)
  end

  @doc """
  Writes `count` copies of a single-width grapheme horizontally starting at
  `{x, y}`, clipped to `clip`. Faster than `put_text/6` with a duplicated
  string: the cell is built once and stamped per column.
  """
  @spec put_repeat(
          t(),
          integer(),
          integer(),
          String.t(),
          non_neg_integer(),
          keyword(),
          tuple() | nil
        ) :: t()
  def put_repeat(buffer, x, y, grapheme, count, style \\ [], clip \\ nil)

  def put_repeat(
        %__MODULE__{width: width, height: height, rows: rows} = buffer,
        x,
        y,
        grapheme,
        count,
        style,
        clip
      ) do
    {cx, cy, cw, ch} = clip || {0, 0, width, height}

    if count <= 0 or y < max(cy, 0) or y >= min(cy + ch, height) do
      buffer
    else
      cell = %Cell{
        char: grapheme,
        fg: Keyword.get(style, :fg),
        bg: Keyword.get(style, :bg),
        attrs: Keyword.get(style, :attrs, [])
      }

      x_first = max(x, max(cx, 0))
      x_last = min(x + count - 1, min(cx + cw, width) - 1)

      row =
        Enum.reduce(x_first..x_last//1, Map.get(rows, y, %{}), fn fx, row ->
          Map.put(row, fx, cell)
        end)

      %{buffer | rows: Map.put(rows, y, row)}
    end
  end

  @doc "Fills a `{x, y, w, h}` rectangle with a cell."
  @spec fill(t(), tuple(), Cell.t()) :: t()
  def fill(
        %__MODULE__{width: width, height: height, rows: rows} = buffer,
        {x, y, w, h},
        %Cell{} = cell
      ) do
    xs = max(x, 0)..(min(x + w, width) - 1)//1
    ys = max(y, 0)..(min(y + h, height) - 1)//1

    rows =
      Enum.reduce(ys, rows, fn fy, rows ->
        row = Enum.reduce(xs, Map.get(rows, fy, %{}), &Map.put(&2, &1, cell))
        Map.put(rows, fy, row)
      end)

    %{buffer | rows: rows}
  end

  @doc "Returns the display width of a grapheme (1 or 2 columns)."
  @spec grapheme_width(String.t()) :: 1 | 2
  def grapheme_width(grapheme) do
    case Ucwidth.width(grapheme) do
      2 -> 2
      _ -> 1
    end
  end

  @doc "Returns the display width of a full string."
  @spec text_width(String.t()) :: non_neg_integer()
  def text_width(string), do: text_width(string, 0)

  defp text_width(<<>>, acc), do: acc

  # Same ASCII fast path as write_graphemes/6.
  defp text_width(<<c, rest::binary>> = string, acc) when c >= 32 and c <= 126 do
    case rest do
      <<next, _::binary>> when next >= 128 -> grapheme_text_width(string, acc)
      _ -> text_width(rest, acc + 1)
    end
  end

  defp text_width(string, acc), do: grapheme_text_width(string, acc)

  defp grapheme_text_width(string, acc) do
    {grapheme, rest} = String.next_grapheme(string)
    text_width(rest, acc + grapheme_width(grapheme))
  end

  @doc """
  Renders the buffer to a plain-text string (no styling), one line per row,
  with trailing whitespace trimmed. Useful for tests.
  """
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{width: w, height: h} = buffer) do
    for y <- 0..(h - 1)//1 do
      0..(w - 1)//1
      |> Enum.map(fn x ->
        case at(buffer, x, y) do
          %Cell{char: :continuation} -> ""
          %Cell{char: char} -> char
        end
      end)
      |> IO.iodata_to_binary()
      |> String.trim_trailing()
    end
    |> Enum.join("\n")
  end
end
