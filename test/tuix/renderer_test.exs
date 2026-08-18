defmodule Tuix.RendererTest do
  use ExUnit.Case, async: true

  import Tuix.Components

  alias Tuix.Buffer
  alias Tuix.Cell
  alias Tuix.Renderer
  alias Tuix.TestRenderer

  describe "painting" do
    test "renders text" do
      assert TestRenderer.render_to_text(text("hello"), 10, 1) == "hello"
    end

    test "renders a bordered box" do
      element =
        box border: :single, width: 7, height: 3 do
          text("hi")
        end

      assert TestRenderer.render_to_text(element, 7, 3) ==
               """
               ┌─────┐
               │hi   │
               └─────┘
               """
               |> String.trim_trailing()
    end

    test "renders rounded borders with a title" do
      element = box(border: :rounded, title: "Hi", width: 10, height: 3)

      assert TestRenderer.render_to_text(element, 10, 3) ==
               """
               ╭─ Hi ───╮
               │        │
               ╰────────╯
               """
               |> String.trim_trailing()
    end

    test "renders nested layout with padding and gap" do
      element =
        box border: :single, padding: 1, gap: 1, width: 12, height: 7 do
          text("one")
          text("two")
        end

      assert TestRenderer.render_to_text(element, 12, 7) ==
               """
               ┌──────────┐
               │          │
               │ one      │
               │          │
               │ two      │
               │          │
               └──────────┘
               """
               |> String.trim_trailing()
    end

    test "text styles land in cells" do
      buffer = TestRenderer.render(text("a", fg: :red, attrs: [:bold]), 3, 1)
      assert %Cell{char: "a", fg: :red, attrs: [:bold]} = Buffer.at(buffer, 0, 0)
    end

    test "background fill" do
      buffer = TestRenderer.render(box(bg: :blue, width: 2, height: 1), 4, 1)
      assert %Cell{char: " ", bg: :blue} = Buffer.at(buffer, 0, 0)
      assert %Cell{char: " ", bg: nil} = Buffer.at(buffer, 2, 0)
    end

    test "wide graphemes occupy two cells" do
      buffer = TestRenderer.render(text("漢x"), 5, 1)
      assert %Cell{char: "漢"} = Buffer.at(buffer, 0, 0)
      assert %Cell{char: :continuation} = Buffer.at(buffer, 1, 0)
      assert %Cell{char: "x"} = Buffer.at(buffer, 2, 0)
    end

    test "text is clipped to its box" do
      element =
        box width: 6, height: 3, border: :single do
          text("overflowing content")
        end

      assert TestRenderer.render_to_text(element, 6, 3) ==
               """
               ┌────┐
               │over│
               └────┘
               """
               |> String.trim_trailing()
    end
  end

  describe "focus styles" do
    test "focus_border_color applies when focused via the :focus option" do
      element =
        box(id: :pane, focusable: true, border: :single, focus_border_color: :cyan, width: 4)

      focused = TestRenderer.render(element, 4, 3, focus: :pane)
      assert %Cell{char: "┌", fg: :cyan} = Buffer.at(focused, 0, 0)

      unfocused = TestRenderer.render(element, 4, 3)
      assert %Cell{char: "┌", fg: nil} = Buffer.at(unfocused, 0, 0)
    end

    test "focus_border_color overrides border_color" do
      element =
        box(
          id: :pane,
          focusable: true,
          border: :single,
          border_color: :red,
          focus_border_color: :cyan,
          width: 4
        )

      focused = TestRenderer.render(element, 4, 3, focus: :pane)
      assert %Cell{fg: :cyan} = Buffer.at(focused, 0, 0)

      unfocused = TestRenderer.render(element, 4, 3)
      assert %Cell{fg: :red} = Buffer.at(unfocused, 0, 0)
    end

    test "focus_bg overrides bg when focused" do
      element = box(id: :pane, focusable: true, bg: :blue, focus_bg: :green, width: 2, height: 1)

      focused = TestRenderer.render(element, 2, 1, focus: :pane)
      assert %Cell{char: " ", bg: :green} = Buffer.at(focused, 0, 0)

      unfocused = TestRenderer.render(element, 2, 1)
      assert %Cell{char: " ", bg: :blue} = Buffer.at(unfocused, 0, 0)
    end

    test "focus styles only apply to the focused element" do
      element =
        box flex_direction: :row do
          box(id: :a, focusable: true, border: :single, focus_border_color: :cyan, width: 3)
          box(id: :b, focusable: true, border: :single, focus_border_color: :cyan, width: 3)
        end

      buffer = TestRenderer.render(element, 6, 3, focus: :b)
      assert %Cell{fg: nil} = Buffer.at(buffer, 0, 0)
      assert %Cell{fg: :cyan} = Buffer.at(buffer, 3, 0)
    end
  end

  describe "input painting" do
    test "shows the placeholder when empty and unfocused" do
      element = input(id: :name, placeholder: "Your name")
      buffer = TestRenderer.render(element, 12, 1)

      assert Buffer.to_text(buffer) == "Your name"
      assert %Cell{char: "Y", fg: :bright_black} = Buffer.at(buffer, 0, 0)
    end

    test "shows the value when unfocused, without a cursor" do
      buffer = TestRenderer.render(input(id: :name, value: "hi"), 6, 1)

      assert Buffer.to_text(buffer) == "hi"
      assert %Cell{attrs: []} = Buffer.at(buffer, 0, 0)
      assert %Cell{attrs: []} = Buffer.at(buffer, 1, 0)
    end

    test "focused input draws a reverse-video cursor at the offset" do
      element = input(id: :name, value: "abc")
      buffer = TestRenderer.render(element, 6, 1, focus: :name, cursor: 1)

      assert %Cell{char: "a", attrs: []} = Buffer.at(buffer, 0, 0)
      assert %Cell{char: "b", attrs: [:reverse]} = Buffer.at(buffer, 1, 0)
      assert %Cell{char: "c", attrs: []} = Buffer.at(buffer, 2, 0)
    end

    test "cursor defaults to the end of the value" do
      buffer = TestRenderer.render(input(id: :name, value: "ab"), 6, 1, focus: :name)

      assert %Cell{char: " ", attrs: [:reverse]} = Buffer.at(buffer, 2, 0)
    end

    test "focused empty input shows the cursor, not the placeholder" do
      element = input(id: :name, placeholder: "Your name")
      buffer = TestRenderer.render(element, 12, 1, focus: :name)

      assert %Cell{char: " ", attrs: [:reverse]} = Buffer.at(buffer, 0, 0)
      assert Buffer.to_text(buffer) == ""
    end

    test "scrolls horizontally to keep the cursor visible" do
      element = input(id: :name, value: "abcdef", width: 3)
      buffer = TestRenderer.render(element, 3, 1, focus: :name, cursor: 6)

      assert Buffer.to_text(buffer) == "ef"
      assert %Cell{char: " ", attrs: [:reverse]} = Buffer.at(buffer, 2, 0)
    end

    test "mask hides the value" do
      element = input(id: :password, value: "secret", mask: "•")
      buffer = TestRenderer.render(element, 8, 1)

      assert Buffer.to_text(buffer) == "••••••"
    end

    test "input is focusable by default and requires an id" do
      assert Tuix.Focus.order(box(do: input(id: :a))) == [:a]

      assert_raise ArgumentError, ~r/requires an :id prop/, fn ->
        input(placeholder: "nope")
      end
    end
  end

  describe "frame diffing" do
    test "identical frames produce only a style reset" do
      buffer = TestRenderer.render(text("same"), 10, 1)
      iodata = Renderer.to_iodata(buffer, buffer)
      assert IO.iodata_to_binary(iodata) == "\e[0m"
    end

    test "changed cells are written with cursor moves" do
      old = TestRenderer.render(text("aaa"), 10, 1)
      new = TestRenderer.render(text("aba"), 10, 1)

      output = IO.iodata_to_binary(Renderer.to_iodata(new, old))

      # Only the changed column (x=1 -> column 2) is addressed.
      assert output =~ "\e[1;2H"
      refute output =~ "\e[1;1H"
      refute output =~ "\e[1;3H"
      assert output =~ "b"
    end

    test "full frame render clears the screen first" do
      buffer = TestRenderer.render(text("hi"), 5, 1)
      output = IO.iodata_to_binary(Renderer.to_iodata(buffer, nil))
      assert String.starts_with?(output, "\e[2J")
      assert output =~ "hi"
    end

    test "style changes are detected as diffs" do
      old = TestRenderer.render(text("x"), 3, 1)
      new = TestRenderer.render(text("x", fg: :red), 3, 1)

      output = IO.iodata_to_binary(Renderer.to_iodata(new, old))
      assert output =~ "\e[0;31m"
    end
  end
end
