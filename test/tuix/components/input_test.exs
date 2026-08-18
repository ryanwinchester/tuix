defmodule Tuix.Components.InputTest do
  use ExUnit.Case, async: true

  alias Tuix.Components.Input
  alias Tuix.Event.Key

  defp key(key, mods \\ []), do: struct!(Key, [key: key] ++ mods)

  describe "edit/3 insertion" do
    test "inserts a grapheme at the cursor" do
      assert Input.edit("ac", 1, key("b")) == {:changed, "abc", 2}
    end

    test "inserts at the start and end" do
      assert Input.edit("bc", 0, key("a")) == {:changed, "abc", 1}
      assert Input.edit("ab", 2, key("c")) == {:changed, "abc", 3}
    end

    test ":space inserts a space" do
      assert Input.edit("ab", 1, key(:space)) == {:changed, "a b", 2}
    end

    test "inserts wide graphemes as one position" do
      assert Input.edit("ab", 1, key("漢")) == {:changed, "a漢b", 2}
    end

    test "inserts multi-grapheme strings (paste) advancing by grapheme count" do
      assert Input.edit("ad", 1, key("bc")) == {:changed, "abcd", 3}
    end

    test "shift-modified graphemes insert normally" do
      assert Input.edit("a", 1, key("B", shift: true)) == {:changed, "aB", 2}
    end

    test "ctrl- and alt-modified keys are ignored" do
      assert Input.edit("ab", 1, key("a", ctrl: true)) == :ignored
      assert Input.edit("ab", 1, key("a", alt: true)) == :ignored
      assert Input.edit("ab", 1, key(:backspace, ctrl: true)) == :ignored
    end
  end

  describe "edit/3 deletion" do
    test "backspace deletes before the cursor" do
      assert Input.edit("abc", 2, key(:backspace)) == {:changed, "ac", 1}
    end

    test "backspace at the start is a consumed no-op" do
      assert Input.edit("abc", 0, key(:backspace)) == {:moved, 0}
    end

    test "delete removes at the cursor" do
      assert Input.edit("abc", 1, key(:delete)) == {:changed, "ac", 1}
    end

    test "delete at the end is a consumed no-op" do
      assert Input.edit("abc", 3, key(:delete)) == {:moved, 3}
    end

    test "deletes whole graphemes" do
      assert Input.edit("a👍b", 2, key(:backspace)) == {:changed, "ab", 1}
    end
  end

  describe "edit/3 movement" do
    test "left and right move and clamp" do
      assert Input.edit("ab", 1, key(:left)) == {:moved, 0}
      assert Input.edit("ab", 0, key(:left)) == {:moved, 0}
      assert Input.edit("ab", 1, key(:right)) == {:moved, 2}
      assert Input.edit("ab", 2, key(:right)) == {:moved, 2}
    end

    test "home and end jump to the boundaries" do
      assert Input.edit("abc", 1, key(:home)) == {:moved, 0}
      assert Input.edit("abc", 1, key(:end)) == {:moved, 3}
    end

    test "cursor beyond the value is clamped first" do
      assert Input.edit("ab", 99, key(:left)) == {:moved, 1}
      assert Input.edit("ab", 99, key("c")) == {:changed, "abc", 3}
    end
  end

  describe "edit/3 fall-through" do
    test "unhandled keys are ignored" do
      for k <- [:enter, :escape, :up, :down, :page_up, :tab] do
        assert Input.edit("ab", 1, key(k)) == :ignored
      end
    end
  end

  describe "on_key/3 (Tuix.Component)" do
    test "value changes emit an Event.Input with the new cursor state" do
      assert Input.on_key(key("c"), %{id: :name, value: "ab"}, 2) ==
               {:emit, %Tuix.Event.Input{id: :name, value: "abc"}, 3}
    end

    test "cursor-only changes update state" do
      assert Input.on_key(key(:left), %{id: :name, value: "ab"}, 2) == {:update, 1}
    end

    test "unhandled keys are ignored" do
      assert Input.on_key(key(:enter), %{id: :name, value: "ab"}, 2) == :ignored
    end

    test "nil state defaults the cursor to the end of the value" do
      assert Input.on_key(key(:left), %{id: :name, value: "ab"}, nil) == {:update, 1}
    end

    test "stored cursor is clamped when the app shortened the value" do
      assert Input.on_key(key("!"), %{id: :name, value: "ab"}, 99) ==
               {:emit, %Tuix.Event.Input{id: :name, value: "ab!"}, 3}
    end
  end

  describe "mark_props/2" do
    test "injects the normalized cursor" do
      assert Input.mark_props(%{value: "ab"}, nil) == %{cursor: 2}
      assert Input.mark_props(%{value: "ab"}, 1) == %{cursor: 1}
      assert Input.mark_props(%{value: "ab"}, 99) == %{cursor: 2}
    end
  end

  describe "window/3" do
    test "no scroll when the value fits" do
      assert Input.window("abc", 1, 10) == {"a", "b", "c"}
    end

    test "cursor at the end yields a space cursor cell" do
      assert Input.window("abc", 3, 10) == {"abc", " ", ""}
    end

    test "empty value" do
      assert Input.window("", 0, 10) == {"", " ", ""}
    end

    test "scrolls to keep the cursor visible" do
      # width 3: cursor cell needs 1 column, prefix budget is 2.
      assert Input.window("abcdef", 6, 3) == {"ef", " ", ""}
      assert Input.window("abcdef", 4, 3) == {"cd", "e", "f"}
    end

    test "accounts for wide graphemes in the prefix" do
      # "漢" is 2 columns wide. With width 4 the whole prefix fits
      # (budget 3); with width 3 (budget 2) "漢b" (3 cols) does not, and
      # scrolling drops whole graphemes from the front.
      assert Input.window("漢b", 2, 4) == {"漢b", " ", ""}
      assert Input.window("漢b", 2, 3) == {"b", " ", ""}
    end

    test "wide grapheme under the cursor" do
      assert Input.window("ab漢", 2, 3) == {"b", "漢", ""}
    end

    test "clamps the cursor to the value" do
      assert Input.window("ab", 99, 10) == {"ab", " ", ""}
    end
  end
end
