defmodule Tuix.ColorTest do
  use ExUnit.Case, async: true

  alias Tuix.Color

  doctest Tuix.Color

  test "hex colors" do
    assert Color.to_sgr("#FF8800", :fg) == [38, 2, 255, 136, 0]
    assert Color.to_sgr("#FF8800", :bg) == [48, 2, 255, 136, 0]
  end

  test "short hex colors" do
    assert Color.to_sgr("#f80", :fg) == [38, 2, 255, 136, 0]
  end

  test "rgb tuples" do
    assert Color.to_sgr({1, 2, 3}, :fg) == [38, 2, 1, 2, 3]
  end

  test "named colors" do
    assert Color.to_sgr(:red, :fg) == [31]
    assert Color.to_sgr(:red, :bg) == [41]
    assert Color.to_sgr(:bright_cyan, :fg) == [96]
    assert Color.to_sgr(:bright_cyan, :bg) == [106]
  end

  test "nil is no codes" do
    assert Color.to_sgr(nil, :fg) == []
  end
end
