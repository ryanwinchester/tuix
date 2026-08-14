defmodule Tuix.Runtime.SignalHandlerTest do
  use ExUnit.Case, async: true

  alias Tuix.Runtime.SignalHandler

  test "forwards sigwinch to the subscribed process" do
    {:ok, pid} = SignalHandler.init(self())

    assert {:ok, ^pid} = SignalHandler.handle_event(:sigwinch, pid)
    assert_received :tuix_check_resize
  end

  test "ignores other signals" do
    {:ok, pid} = SignalHandler.init(self())

    assert {:ok, ^pid} = SignalHandler.handle_event(:sigusr1, pid)
    refute_received :tuix_check_resize
  end
end
