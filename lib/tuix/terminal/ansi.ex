defmodule Tuix.Terminal.ANSI do
  @moduledoc """
  Builders for the ANSI escape sequences on the frame-rendering hot path.

  All functions return iodata suitable for writing directly to the terminal.

  > #### Why not `io_ansi`? {: .info}
  >
  > Tuix uses OTP 29's `:io_ansi` for static terminal control (alternate
  > screen, cursor visibility, keypad mode - see `Tuix.Terminal`), where its
  > terminfo awareness helps. The sequences here are emitted per frame diff:
  > they are universal, and building them directly lets the renderer batch
  > multiple SGR codes into a single sequence per run, which `:io_ansi`'s
  > one-sequence-per-attribute API cannot do.
  """

  @csi "\e["

  @doc "Clear the entire screen."
  def clear_screen, do: [@csi, "2J"]

  @doc """
  Move the cursor to a 0-based `{x, y}` position.

  The terminal itself is 1-based; this function does the translation.
  """
  def move_to(x, y), do: [@csi, Integer.to_string(y + 1), ";", Integer.to_string(x + 1), "H"]

  @doc "Reset all styling attributes."
  def reset, do: [@csi, "0m"]

  @doc """
  Build an SGR sequence from a list of numeric codes.

  Returns an empty list when no codes are given.
  """
  def sgr([]), do: []

  def sgr(codes) when is_list(codes) do
    [@csi, codes |> Enum.map(&to_string/1) |> Enum.intersperse(";"), "m"]
  end

  @doc "SGR codes for a text attribute."
  def attr_code(:bold), do: 1
  def attr_code(:dim), do: 2
  def attr_code(:italic), do: 3
  def attr_code(:underline), do: 4
  def attr_code(:blink), do: 5
  def attr_code(:reverse), do: 7
  def attr_code(:strikethrough), do: 9
end
