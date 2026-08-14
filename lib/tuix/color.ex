defmodule Tuix.Color do
  @moduledoc """
  Color parsing and SGR code generation.

  Accepted color inputs:

    * Hex strings: `"#FF8800"` or `"#f80"`
    * RGB tuples: `{255, 136, 0}`
    * Named atoms: `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`,
      `:cyan`, `:white` and their `:bright_*` variants
    * `nil` for the terminal default

  """

  @named %{
    black: 0,
    red: 1,
    green: 2,
    yellow: 3,
    blue: 4,
    magenta: 5,
    cyan: 6,
    white: 7
  }

  @type t :: nil | atom() | String.t() | {0..255, 0..255, 0..255}

  @doc """
  Returns the SGR codes (a list of integers) for a color in the given layer
  (`:fg` or `:bg`). Returns `[]` for `nil`.

  ## Examples

      iex> Tuix.Color.to_sgr("#FF8800", :fg)
      [38, 2, 255, 136, 0]

      iex> Tuix.Color.to_sgr(:red, :bg)
      [41]

      iex> Tuix.Color.to_sgr(nil, :fg)
      []

  """
  @spec to_sgr(t(), :fg | :bg) :: [non_neg_integer()]
  def to_sgr(nil, _layer), do: []

  def to_sgr({r, g, b}, layer)
      when r in 0..255 and g in 0..255 and b in 0..255 do
    [truecolor_intro(layer), 2, r, g, b]
  end

  def to_sgr("#" <> hex, layer) do
    {r, g, b} = parse_hex!(hex)
    to_sgr({r, g, b}, layer)
  end

  def to_sgr(name, layer) when is_atom(name) do
    case Atom.to_string(name) do
      "bright_" <> base ->
        [bright_base(layer) + Map.fetch!(@named, String.to_existing_atom(base))]

      _ ->
        [base(layer) + Map.fetch!(@named, name)]
    end
  end

  defp truecolor_intro(:fg), do: 38
  defp truecolor_intro(:bg), do: 48

  defp base(:fg), do: 30
  defp base(:bg), do: 40

  defp bright_base(:fg), do: 90
  defp bright_base(:bg), do: 100

  defp parse_hex!(<<r::binary-2, g::binary-2, b::binary-2>>) do
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  defp parse_hex!(<<r::binary-1, g::binary-1, b::binary-1>>) do
    {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16), String.to_integer(b <> b, 16)}
  end
end
