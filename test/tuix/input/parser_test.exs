defmodule Tuix.Input.ParserTest do
  use ExUnit.Case, async: true

  alias Tuix.Event.Key
  alias Tuix.Event.Mouse
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

  describe "SGR mouse reports" do
    test "press and release translate to 0-based coordinates" do
      assert {[%Mouse{kind: :press, button: :left, x: 9, y: 4}], ""} =
               Parser.parse("\e[<0;10;5M")

      assert {[%Mouse{kind: :release, button: :left, x: 9, y: 4}], ""} =
               Parser.parse("\e[<0;10;5m")
    end

    test "middle and right buttons" do
      assert {[%Mouse{kind: :press, button: :middle}], ""} = Parser.parse("\e[<1;1;1M")
      assert {[%Mouse{kind: :press, button: :right}], ""} = Parser.parse("\e[<2;1;1M")
    end

    test "drag while a button is held" do
      assert {[%Mouse{kind: :drag, button: :left, x: 3, y: 2}], ""} =
               Parser.parse("\e[<32;4;3M")
    end

    test "wheel" do
      assert {[%Mouse{kind: :scroll_up, button: nil, x: 0, y: 0}], ""} =
               Parser.parse("\e[<64;1;1M")

      assert {[%Mouse{kind: :scroll_down, button: nil}], ""} = Parser.parse("\e[<65;1;1M")
    end

    test "modifiers" do
      assert {[%Mouse{kind: :press, button: :left, shift: true}], ""} =
               Parser.parse("\e[<4;1;1M")

      assert {[%Mouse{kind: :press, button: :left, alt: true}], ""} = Parser.parse("\e[<8;1;1M")

      assert {[%Mouse{kind: :press, button: :left, ctrl: true}], ""} =
               Parser.parse("\e[<16;1;1M")

      assert {[%Mouse{kind: :scroll_up, ctrl: true}], ""} = Parser.parse("\e[<80;1;1M")
    end

    test "incomplete report is kept as rest" do
      assert {[], "\e[<0;10"} = Parser.parse("\e[<0;10")
      assert {[], "\e[<0;10;5"} = Parser.parse("\e[<0;10;5")
    end

    test "malformed report is dropped" do
      assert {[], ""} = Parser.parse("\e[<0;10M")
      assert {[], ""} = Parser.parse("\e[<0;;5M")
    end

    test "mixed with keys in one chunk" do
      assert {[%Key{key: "a"}, %Mouse{kind: :press, x: 0, y: 0}, %Key{key: :up}], ""} =
               Parser.parse("a\e[<0;1;1M\e[A")
    end
  end

  describe "X10 mouse reports" do
    test "press with byte-encoded coordinates" do
      # cb = 32 (left press), cx = 33 (column 1), cy = 37 (row 5)
      assert {[%Mouse{kind: :press, button: :left, x: 0, y: 4}], ""} =
               Parser.parse(<<"\e[M", 32, 33, 37>>)
    end

    test "release does not report a button" do
      assert {[%Mouse{kind: :release, button: nil, x: 0, y: 0}], ""} =
               Parser.parse(<<"\e[M", 35, 33, 33>>)
    end

    test "wheel" do
      assert {[%Mouse{kind: :scroll_up}], ""} = Parser.parse(<<"\e[M", 96, 33, 33>>)
      assert {[%Mouse{kind: :scroll_down}], ""} = Parser.parse(<<"\e[M", 97, 33, 33>>)
    end

    test "incomplete report is kept as rest" do
      assert {[], "\e[M"} = Parser.parse("\e[M")
      assert {[], <<"\e[M", 32>>} = Parser.parse(<<"\e[M", 32>>)
      assert {[], <<"\e[M", 32, 33>>} = Parser.parse(<<"\e[M", 32, 33>>)
    end

    test "payload bytes are not misparsed as keys" do
      assert {[%Mouse{kind: :press}, %Key{key: "q"}], ""} =
               Parser.parse(<<"\e[M", 32, 33, 33, "q">>)
    end
  end
end
