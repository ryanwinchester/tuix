defmodule Tuix.LayoutTest do
  use ExUnit.Case, async: true

  import Tuix.Components

  alias Tuix.Layout
  alias Tuix.Layout.Placed

  defp rects(%Placed{children: children}), do: Enum.map(children, & &1.rect)

  test "column stacks children vertically" do
    tree =
      box [] do
        text("one")
        text("two")
      end

    placed = Layout.compute(tree, 20, 10)

    assert placed.rect == {0, 0, 20, 2}
    assert rects(placed) == [{0, 0, 3, 1}, {0, 1, 3, 1}]
  end

  test "row lays children horizontally" do
    tree =
      box flex_direction: :row do
        text("one")
        text("two!")
      end

    placed = Layout.compute(tree, 20, 10)
    assert rects(placed) == [{0, 0, 3, 1}, {3, 0, 4, 1}]
  end

  test "gap separates children" do
    tree =
      box flex_direction: :row, gap: 2 do
        text("ab")
        text("cd")
      end

    placed = Layout.compute(tree, 20, 10)
    assert rects(placed) == [{0, 0, 2, 1}, {4, 0, 2, 1}]
  end

  test "border and padding inset the content" do
    tree =
      box border: :single, padding: 1 do
        text("hi")
      end

    placed = Layout.compute(tree, 20, 10)

    # 1 border + 1 padding on each side
    assert placed.rect == {0, 0, 20, 5}
    assert rects(placed) == [{2, 2, 2, 1}]
  end

  test "explicit width and height are honored" do
    tree = box(width: 10, height: 4)
    placed = Layout.compute(tree, 80, 24)
    assert placed.rect == {0, 0, 10, 4}
  end

  test "percent sizes resolve against available space" do
    tree =
      box flex_direction: :row, height: 5 do
        box(width: "50%", height: 5)
        box(width: {:percent, 25}, height: 5)
      end

    placed = Layout.compute(tree, 40, 24)
    assert rects(placed) == [{0, 0, 20, 5}, {20, 0, 10, 5}]
  end

  test "flex_grow children share leftover space" do
    tree =
      box flex_direction: :row, height: 3 do
        box(width: 10, height: 3)
        box(flex_grow: 1, height: 3)
        box(flex_grow: 1, height: 3)
      end

    placed = Layout.compute(tree, 50, 24)
    assert rects(placed) == [{0, 0, 10, 3}, {10, 0, 20, 3}, {30, 0, 20, 3}]
  end

  test "boxes without explicit cross size stretch" do
    tree =
      box height: 10 do
        box(height: 3)
      end

    placed = Layout.compute(tree, 30, 24)
    assert rects(placed) == [{0, 0, 30, 3}]
  end

  test "multi-line text intrinsic size" do
    tree =
      box [] do
        text("short\na longer line")
      end

    placed = Layout.compute(tree, 40, 10)
    assert rects(placed) == [{0, 0, 13, 2}]
  end

  test "wide graphemes count as two columns" do
    tree =
      box flex_direction: :row do
        text("漢字")
        text("x")
      end

    placed = Layout.compute(tree, 20, 5)
    assert rects(placed) == [{0, 0, 4, 1}, {4, 0, 1, 1}]
  end

  test "root with flex-less content sizes to content height" do
    tree =
      box border: :single do
        text("hello")
      end

    placed = Layout.compute(tree, 80, 24)
    assert placed.rect == {0, 0, 80, 3}
  end

  test "children are clamped to the content rect" do
    tree =
      box height: 3 do
        box(height: 10)
      end

    placed = Layout.compute(tree, 20, 24)
    assert rects(placed) == [{0, 0, 20, 3}]
  end

  test "scroll box children are laid out at full content height" do
    tree =
      scroll_box id: :log, border: :single, height: 4 do
        for n <- 1..6, do: text("line #{n}")
      end

    placed = Layout.compute(tree, 20, 10)

    assert placed.rect == {0, 0, 20, 4}
    assert rects(placed) == for(n <- 0..5, do: {1, 1 + n, 6, 1})
  end

  test "borderless overflowing scroll box reserves the rightmost column" do
    tree =
      scroll_box id: :log, height: 2 do
        text("aaaa")
        text("bbbb")
        text("cccc")
      end

    placed = Layout.compute(tree, 4, 10)
    assert rects(placed) == [{0, 0, 3, 1}, {0, 1, 3, 1}, {0, 2, 3, 1}]
  end

  test "scroll box without overflow reserves nothing" do
    tree =
      scroll_box id: :log, height: 3 do
        text("aaaa")
        text("bbbb")
      end

    placed = Layout.compute(tree, 4, 10)
    assert rects(placed) == [{0, 0, 4, 1}, {0, 1, 4, 1}]
  end

  test "scroll box intrinsic size matches a box" do
    tree =
      scroll_box id: :log, border: :single do
        text("one")
        text("two")
      end

    placed = Layout.compute(tree, 20, 24)
    assert placed.rect == {0, 0, 20, 4}
  end

  test "gap counts toward scroll box content height" do
    tree =
      scroll_box id: :log, height: 2, gap: 1 do
        text("aaaa")
        text("bbbb")
      end

    placed = Layout.compute(tree, 5, 10)

    # 2 rows + 1 gap = 3 > 2: overflows, so the scrollbar column is reserved.
    assert rects(placed) == [{0, 0, 4, 1}, {0, 2, 4, 1}]
  end
end
