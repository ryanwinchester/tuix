defmodule Tuix.Input.ParserTest do
  use ExUnit.Case, async: true

  alias Tuix.Event.Key
  alias Tuix.Input.Parser

  doctest Tuix.Input.Parser

  test "printable characters" do
    assert {[%Key{key: "a"}, %Key{key: "b"}], ""} = Parser.parse("ab")
  end

  test "utf-8 graphemes" do
    assert {[%Key{key: "é"}, %Key{key: "漢"}], ""} = Parser.parse("é漢")
  end

  test "special keys" do
    assert {[%Key{key: :enter}], ""} = Parser.parse("\r")
    assert {[%Key{key: :tab}], ""} = Parser.parse("\t")
    assert {[%Key{key: :backspace}], ""} = Parser.parse(<<0x7F>>)
    assert {[%Key{key: :space}], ""} = Parser.parse(" ")
  end

  test "ctrl+letter" do
    assert {[%Key{key: "c", ctrl: true}], ""} = Parser.parse(<<3>>)
    assert {[%Key{key: "a", ctrl: true}], ""} = Parser.parse(<<1>>)
  end

  test "arrow keys" do
    assert {[%Key{key: :up}], ""} = Parser.parse("\e[A")
    assert {[%Key{key: :down}], ""} = Parser.parse("\e[B")
    assert {[%Key{key: :right}], ""} = Parser.parse("\e[C")
    assert {[%Key{key: :left}], ""} = Parser.parse("\e[D")
  end

  test "ss3 arrow keys (application mode)" do
    assert {[%Key{key: :up}], ""} = Parser.parse("\eOA")
  end

  test "home/end/page keys" do
    assert {[%Key{key: :home}], ""} = Parser.parse("\e[H")
    assert {[%Key{key: :end}], ""} = Parser.parse("\e[F")
    assert {[%Key{key: :delete}], ""} = Parser.parse("\e[3~")
    assert {[%Key{key: :page_up}], ""} = Parser.parse("\e[5~")
    assert {[%Key{key: :page_down}], ""} = Parser.parse("\e[6~")
  end

  test "modified arrows" do
    assert {[%Key{key: :up, ctrl: true}], ""} = Parser.parse("\e[1;5A")
    assert {[%Key{key: :right, shift: true}], ""} = Parser.parse("\e[1;2C")
    assert {[%Key{key: :left, alt: true}], ""} = Parser.parse("\e[1;3D")
  end

  test "shift-tab" do
    assert {[%Key{key: :backtab}], ""} = Parser.parse("\e[Z")
  end

  test "alt+key" do
    assert {[%Key{key: "x", alt: true}], ""} = Parser.parse("\ex")
  end

  test "bare escape at end of chunk is the escape key" do
    assert {[%Key{key: :escape}], ""} = Parser.parse("\e")
  end

  test "incomplete csi sequence is kept as rest" do
    assert {[], "\e["} = Parser.parse("\e[")
    assert {[], "\e[1;5"} = Parser.parse("\e[1;5")
  end

  test "events before an incomplete sequence are still emitted" do
    assert {[%Key{key: "a"}], "\e["} = Parser.parse("a\e[")
  end

  test "multiple sequences in one chunk" do
    assert {[%Key{key: :up}, %Key{key: "q"}, %Key{key: :down}], ""} = Parser.parse("\e[Aq\e[B")
  end
end
