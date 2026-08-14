defmodule Tuix.Terminal do
  @moduledoc """
  Owns the terminal: switches it into raw mode and the alternate screen on
  start, and restores it on shutdown — including crash shutdowns.

  Requires OTP 26+ for `:shell.start_interactive({:noshell, :raw})`.
  """

  use GenServer

  alias Tuix.Terminal.ANSI

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

    IO.write([
      ANSI.enter_alternate_screen(),
      ANSI.hide_cursor(),
      ANSI.clear_screen(),
      ANSI.home()
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

      IO.write([
        ANSI.reset(),
        ANSI.show_cursor(),
        ANSI.exit_alternate_screen()
      ])

      exit_raw_mode()
    end
  end
end
