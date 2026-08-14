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
