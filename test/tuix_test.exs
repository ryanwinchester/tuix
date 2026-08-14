defmodule TuixTest do
  use ExUnit.Case
  doctest Tuix

  test "greets the world" do
    assert Tuix.hello() == :world
  end
end
