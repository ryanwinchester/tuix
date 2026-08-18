defmodule Tuix.FocusTest do
  use ExUnit.Case, async: true

  import Tuix.Components

  alias Tuix.Focus

  defp tree do
    box do
      box(id: :first, focusable: true)

      box flex_direction: :row do
        box(id: :nested, focusable: true)
        text("not focusable")
        box(id: :plain)
      end

      box(id: :last, focusable: true)
    end
  end

  describe "order/1" do
    test "collects focusable ids in depth-first document order" do
      assert Focus.order(tree()) == [:first, :nested, :last]
    end

    test "returns [] when nothing is focusable" do
      assert Focus.order(box(do: text("hi"))) == []
    end

    test "ignores elements with ids that are not focusable" do
      element =
        box do
          box(id: :a)
          box(id: :b, focusable: true)
        end

      assert Focus.order(element) == [:b]
    end

    test "raises when a focusable element has no id" do
      assert_raise ArgumentError, ~r/requires an :id prop/, fn ->
        Focus.order(box(focusable: true))
      end
    end
  end

  describe "next/2 and prev/2" do
    test "empty order returns nil" do
      assert Focus.next([], nil) == nil
      assert Focus.prev([], :a) == nil
    end

    test "nil current focuses the first / last" do
      assert Focus.next([:a, :b, :c], nil) == :a
      assert Focus.prev([:a, :b, :c], nil) == :c
    end

    test "steps forward and backward" do
      assert Focus.next([:a, :b, :c], :a) == :b
      assert Focus.prev([:a, :b, :c], :c) == :b
    end

    test "wraps around" do
      assert Focus.next([:a, :b, :c], :c) == :a
      assert Focus.prev([:a, :b, :c], :a) == :c
    end

    test "unknown current falls back to first / last" do
      assert Focus.next([:a, :b], :gone) == :a
      assert Focus.prev([:a, :b], :gone) == :b
    end

    test "single element wraps to itself" do
      assert Focus.next([:only], :only) == :only
      assert Focus.prev([:only], :only) == :only
    end
  end

  describe "autofocus/1" do
    test "returns the first focusable element with autofocus in document order" do
      element =
        box do
          box(id: :a, focusable: true)
          box(id: :b, focusable: true, autofocus: true)
          box(id: :c, focusable: true, autofocus: true)
        end

      assert Focus.autofocus(element) == :b
    end

    test "returns nil when nothing has autofocus" do
      assert Focus.autofocus(tree()) == nil
    end

    test "ignores autofocus on non-focusable elements" do
      element =
        box do
          box(id: :a, autofocus: true)
          box(id: :b, focusable: true, autofocus: true)
        end

      assert Focus.autofocus(element) == :b
    end
  end

  describe "mark/2" do
    test "sets focused: true on the matching focusable element" do
      marked = Focus.mark(tree(), :nested)

      [_first, row, last] = marked.children
      [nested | _rest] = row.children

      assert nested.props.focused == true
      refute Map.has_key?(last.props, :focused)
    end

    test "nil id returns the tree unchanged" do
      assert Focus.mark(tree(), nil) == tree()
    end

    test "does not mark non-focusable elements with a matching id" do
      marked = Focus.mark(tree(), :plain)

      [_first, row, _last] = marked.children
      [_nested, _text, plain] = row.children

      refute Map.has_key?(plain.props, :focused)
    end

    test "merges extra props into the focused element" do
      marked = Focus.mark(tree(), :first, %{cursor: 3})

      [first | _rest] = marked.children
      assert first.props.focused == true
      assert first.props.cursor == 3
    end
  end

  describe "find/2" do
    test "finds the focusable element with the given id" do
      assert %Tuix.Element{props: %{id: :nested}} = Focus.find(tree(), :nested)
    end

    test "returns nil for unknown, nil, or non-focusable ids" do
      assert Focus.find(tree(), :missing) == nil
      assert Focus.find(tree(), nil) == nil
      assert Focus.find(tree(), :plain) == nil
    end
  end
end
