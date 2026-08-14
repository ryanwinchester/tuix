defmodule Tuix.Runtime.SignalHandler do
  @moduledoc false
  # A :gen_event handler installed on :erl_signal_server that forwards
  # SIGWINCH (terminal resize) to the runtime process. Installed with
  # add_sup_handler/3 so it is removed automatically when the runtime dies.

  @behaviour :gen_event

  @impl true
  def init(pid), do: {:ok, pid}

  @impl true
  def handle_event(:sigwinch, pid) do
    send(pid, :tuix_check_resize)
    {:ok, pid}
  end

  def handle_event(_event, pid), do: {:ok, pid}

  @impl true
  def handle_call(_request, pid), do: {:ok, :ok, pid}
end
