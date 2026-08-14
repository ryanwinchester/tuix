defmodule Tuix.Cell do
  @moduledoc """
  A single terminal cell: one grapheme plus its styling.

  Wide graphemes (CJK, emoji) occupy two columns; the second column holds a
  cell whose `char` is `:continuation` and is skipped when writing output.
  """

  defstruct char: " ", fg: nil, bg: nil, attrs: []

  @type t :: %__MODULE__{
          char: String.t() | :continuation,
          fg: Tuix.Color.t(),
          bg: Tuix.Color.t(),
          attrs: [atom()]
        }

  @doc "The default blank cell."
  def blank, do: %__MODULE__{}

  @doc "Returns the `{fg, bg, attrs}` style triple of a cell."
  def style(%__MODULE__{fg: fg, bg: bg, attrs: attrs}), do: {fg, bg, attrs}
end
