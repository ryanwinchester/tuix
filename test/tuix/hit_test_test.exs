defmodule Tuix.HitTestTest do
  use ExUnit.Case, async: true

  import Tuix.Components

  alias Tuix.Element
  alias Tuix.HitTest
  alias Tuix.Layout
  alias Tuix.Layout.Placed

  defp place(tree, width \\ 20, height \\ 10), do: Layout.compute(tree, width, height)

  test "nil tree hits nothing" do
    assert HitTest.focusable_at(nil, {0, 0}) == nil
  end

  test "a point outside the tree hits nothing" do
    placed = place(box(width: 5, height: 2))
    assert HitTest.focusable_at(placed, {10, 5}) == nil
  end

  test "a hit on non-focusable elements returns nil" do
    tree =
      box width: 10, height: 3 do
        text("hello")
      end

    placed = place(tree)
    assert HitTest.focusable_at(placed, {1, 0}) == nil
  end

  test "the focusable element under the point wins" do
    tree =
      box [] do
        input(id: :email, width: 10, height: 1)
        input(id: :password, width: 10, height: 1)
      end

    placed = place(tree)
    assert HitTest.focusable_at(placed, {3, 0}) == :email
    assert HitTest.focusable_at(placed, {3, 1}) == :password
  end

  test "the innermost focusable wins; the padding falls back to the ancestor" do
    tree =
      box focusable: true, id: :form, padding: 1, height: 3 do
        input(id: :email, width: 10, height: 1)
      end

    placed = place(tree)

    # Inside the input.
    assert HitTest.focusable_at(placed, {2, 1}) == :email
    # In the form's padding.
    assert HitTest.focusable_at(placed, {0, 0}) == :form
  end

  test "border cells hit the focusable box" do
    tree = box(focusable: true, id: :panel, border: :single, width: 10, height: 4)
    placed = place(tree)

    assert HitTest.focusable_at(placed, {0, 0}) == :panel
    assert HitTest.focusable_at(placed, {9, 3}) == :panel
    assert HitTest.focusable_at(placed, {10, 0}) == nil
  end

  test "overlapping focusables: the last painted wins" do
    focusable = fn id, rect ->
      %Placed{element: Element.new(:box, focusable: true, id: id), rect: rect}
    end

    placed = %Placed{
      element: Element.new(:box),
      rect: {0, 0, 10, 10},
      children: [focusable.(:under, {0, 0, 5, 5}), focusable.(:over, {0, 0, 5, 5})]
    }

    assert HitTest.focusable_at(placed, {1, 1}) == :over
  end

  test "scroll box: the pointer is translated by the scroll offset" do
    tree =
      scroll_box id: :log, height: 3, scroll_offset: 2 do
        for i <- 1..6 do
          box(focusable: true, id: :"row_#{i}", height: 1)
        end
      end

    placed = place(tree, 10, 3)

    # Row 1 on screen shows content row 3 (offset 2).
    assert HitTest.focusable_at(placed, {0, 0}) == :row_3
    assert HitTest.focusable_at(placed, {0, 2}) == :row_5
  end

  test "scroll box: the border is outside the viewport and hits the box" do
    tree =
      scroll_box id: :log, height: 4, border: :single, scroll_offset: 1 do
        for i <- 1..6 do
          box(focusable: true, id: :"row_#{i}", height: 1)
        end
      end

    placed = place(tree, 10, 4)

    # Border row: the scroll box itself, never a (clipped) child.
    assert HitTest.focusable_at(placed, {5, 0}) == :log
    # First viewport row shows content row 2 (offset 1).
    assert HitTest.focusable_at(placed, {1, 1}) == :row_2
  end

  test "scroll box: empty viewport space falls back to the scroll box" do
    tree =
      scroll_box id: :log, height: 5 do
        text("only one row")
      end

    placed = place(tree, 20, 5)
    assert HitTest.focusable_at(placed, {0, 4}) == :log
  end

  describe "scroll_box_at/2" do
    test "nil tree and misses hit nothing" do
      assert HitTest.scroll_box_at(nil, {0, 0}) == nil

      placed = place(scroll_box(id: :log, width: 5, height: 3))
      assert HitTest.scroll_box_at(placed, {10, 5}) == nil
    end

    test "a tree without scroll boxes hits nothing" do
      tree =
        box [] do
          input(id: :email, width: 10, height: 1)
        end

      placed = place(tree)
      assert HitTest.scroll_box_at(placed, {3, 0}) == nil
    end

    test "the whole rect counts, border and scrollbar column included" do
      tree =
        scroll_box id: :log, width: 10, height: 4, border: :single do
          for i <- 1..6, do: text("row #{i}")
        end

      placed = place(tree, 10, 4)

      assert HitTest.scroll_box_at(placed, {1, 1}) == :log
      # Border corner and scrollbar column.
      assert HitTest.scroll_box_at(placed, {0, 0}) == :log
      assert HitTest.scroll_box_at(placed, {9, 2}) == :log
      assert HitTest.scroll_box_at(placed, {10, 0}) == nil
    end

    test "a point over a focusable child returns the enclosing scroll box" do
      tree =
        scroll_box id: :log, height: 3 do
          box(focusable: true, id: :row, height: 1)
        end

      placed = place(tree, 10, 3)

      assert HitTest.scroll_box_at(placed, {0, 0}) == :log
      assert HitTest.focusable_at(placed, {0, 0}) == :row
    end

    test "nested scroll boxes: the innermost wins" do
      tree =
        scroll_box id: :outer, height: 6 do
          box(height: 1)

          scroll_box id: :inner, height: 2 do
            for i <- 1..4, do: text("inner #{i}")
          end

          box(height: 1)
        end

      placed = place(tree, 10, 6)

      assert HitTest.scroll_box_at(placed, {0, 0}) == :outer
      assert HitTest.scroll_box_at(placed, {0, 1}) == :inner
      assert HitTest.scroll_box_at(placed, {0, 2}) == :inner
      assert HitTest.scroll_box_at(placed, {0, 3}) == :outer
    end

    test "an inner scroll box is reached through a scrolled outer box" do
      tree =
        scroll_box id: :outer, height: 4, scroll_offset: 2 do
          for i <- 1..4, do: box(height: 1)

          scroll_box id: :inner, height: 2 do
            for i <- 1..4, do: text("inner #{i}")
          end
        end

      placed = place(tree, 10, 4)

      # Content is 6 rows (4 boxes + the 2-row inner box); offset 2 shows
      # content rows 2..5, so the inner box (content rows 4..5) sits on
      # screen rows 2..3.
      assert HitTest.scroll_box_at(placed, {0, 0}) == :outer
      assert HitTest.scroll_box_at(placed, {0, 1}) == :outer
      assert HitTest.scroll_box_at(placed, {0, 2}) == :inner
      assert HitTest.scroll_box_at(placed, {0, 3}) == :inner
    end
  end
end
