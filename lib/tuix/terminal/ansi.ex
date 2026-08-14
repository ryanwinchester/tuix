defmodule Tuix.Terminal.ANSI do
  @moduledoc """
  Builders for ANSI escape sequences.

  All functions return iodata suitable for writing directly to the terminal.
  """

  @esc "\e"
  @csi "\e["

  ## Screen control

  @doc "Switch to the alternate screen buffer."
  def enter_alternate_screen, do: [@csi, "?1049h"]

  @doc "Return to the main screen buffer."
  def exit_alternate_screen, do: [@csi, "?1049l"]

  @doc "Clear the entire screen."
  def clear_screen, do: [@csi, "2J"]

  @doc "Hide the cursor."
  def hide_cursor, do: [@csi, "?25l"]

  @doc "Show the cursor."
  def show_cursor, do: [@csi, "?25h"]

  ## Cursor movement

  @doc """
  Move the cursor to a 0-based `{x, y}` position.

  The terminal itself is 1-based; this function does the translation.
  """
  def move_to(x, y), do: [@csi, Integer.to_string(y + 1), ";", Integer.to_string(x + 1), "H"]

  @doc "Move the cursor to the home position (top-left)."
  def home, do: [@csi, "H"]

  ## Styling (SGR)

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

  @doc "The raw escape character."
  def esc, do: @esc
end
