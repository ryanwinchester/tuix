defmodule Tuix.Terminal do
  @moduledoc """
  Owns the terminal: switches it into raw mode and the alternate screen on
  start, and restores it on shutdown — including crash shutdowns.

  Requires OTP 29+ (raw mode via `:shell.start_interactive/1` and
  `:io_ansi`).

  Static terminal control (alternate screen, cursor visibility, keypad
  transmit mode) goes through OTP 29's `:io_ansi`, which uses the local
  terminfo database and strips sequences the terminal does not support.
  Frame rendering writes precomposed iodata (see `Tuix.Terminal.ANSI`).
  """

  use GenServer

  @restore_flag {__MODULE__, :needs_restore}

  ## Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Writes iodata to the terminal."
  def write(iodata) do
    GenServer.call(__MODULE__, {:write, iodata})
  end

  @doc "Returns the current terminal size as `{columns, rows}`."
  @spec size() :: {pos_integer(), pos_integer()}
  def size do
    columns =
      case :io.columns() do
        {:ok, n} -> n
        _ -> 80
      end

    rows =
      case :io.rows() do
        {:ok, n} -> n
        _ -> 24
      end

    {columns, rows}
  end

  ## Server

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    enter_raw_mode()
    :io.setopts(:standard_io, binary: true)

    :io_ansi.fwrite([
      :alternate_screen,
      :cursor_hide,
      :keypad_transmit_mode,
      :clear
    ])

    # Belt and suspenders: restore even if the VM exits without a clean
    # supervisor shutdown.
    :persistent_term.put(@restore_flag, true)
    System.at_exit(fn _status -> restore() end)

    {:ok, %{}}
  end

  @impl true
  def handle_call({:write, iodata}, _from, state) do
    IO.write(iodata)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    restore()
    :ok
  end

  ## Terminal state management

  defp enter_raw_mode do
    try do
      :shell.start_interactive({:noshell, :raw})
    catch
      _, _ -> :ok
    end
  end

  defp exit_raw_mode do
    try do
      :shell.start_interactive({:noshell, :cooked})
    catch
      _, _ -> :ok
    end
  end

  defp restore do
    if :persistent_term.get(@restore_flag, false) do
      :persistent_term.put(@restore_flag, false)

      try do
        :io_ansi.fwrite([
          :reset,
          :keypad_transmit_mode_off,
          :cursor_show,
          :alternate_screen_off
        ])
      catch
        # The tty may already be gone during VM shutdown.
        _, _ -> :ok
      end

      exit_raw_mode()
    end
  end
end
