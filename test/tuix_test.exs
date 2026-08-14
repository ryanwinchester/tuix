defmodule TuixTest do
  use ExUnit.Case, async: true

  import Tuix.Components

  alias Tuix.Element

  doctest Tuix

  describe "components" do
    test "box with do block collects children" do
      element =
        box border: :single do
          text("a")
          text("b")
        end

      assert %Element{tag: :box, props: %{border: :single}, children: [_, _]} = element
    end

    test "box with children list" do
      element = box([], [text("a"), text("b")])
      assert length(element.children) == 2
    end

    test "nil and nested-list children are normalized" do
      show = Enum.empty?([:something])

      element =
        box [] do
          if show, do: text("hidden")
          for i <- 1..2, do: text("item #{i}")
        end

      assert [%Element{props: %{content: "item 1"}}, %Element{props: %{content: "item 2"}}] =
               element.children
    end

    test "text sets content prop" do
      assert %Element{tag: :text, props: %{content: "hi", fg: :red}} = text("hi", fg: :red)
    end
  end
end
