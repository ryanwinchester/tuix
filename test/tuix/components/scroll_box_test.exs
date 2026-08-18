defmodule Tuix.Components.ScrollBoxTest do
  use ExUnit.Case, async: true

  alias Tuix.Components.ScrollBox
  alias Tuix.Event.Key

  @props %{id: :log}
  @state %{offset: 5, viewport: 4, max_offset: 10}

  defp key(key, mods \\ []), do: struct!(Key, [key: key] ++ mods)

  describe "on_key/3 scrolling" do
    test "up and down scroll by one row" do
      assert ScrollBox.on_key(key(:up), @props, @state) == {:update, %{@state | offset: 4}}
      assert ScrollBox.on_key(key(:down), @props, @state) == {:update, %{@state | offset: 6}}
    end

    test "page_up and page_down scroll by the viewport height" do
      assert ScrollBox.on_key(key(:page_up), @props, @state) == {:update, %{@state | offset: 1}}

      assert ScrollBox.on_key(key(:page_down), @props, @state) ==
               {:update, %{@state | offset: 9}}
    end

    test "home and end jump to the boundaries" do
      assert ScrollBox.on_key(key(:home), @props, @state) == {:update, %{@state | offset: 0}}
      assert ScrollBox.on_key(key(:end), @props, @state) == {:update, %{@state | offset: 10}}
    end

    test "clamps at the boundaries (consumed no-op)" do
      top = %{@state | offset: 0}
      bottom = %{@state | offset: 10}

      assert ScrollBox.on_key(key(:up), @props, top) == {:update, top}
      assert ScrollBox.on_key(key(:page_up), @props, top) == {:update, top}
      assert ScrollBox.on_key(key(:down), @props, bottom) == {:update, bottom}
      assert ScrollBox.on_key(key(:page_down), @props, bottom) == {:update, bottom}
    end

    test "paging clamps mid-range" do
      assert ScrollBox.on_key(key(:page_up), @props, %{@state | offset: 2}) ==
               {:update, %{@state | offset: 0}}

      assert ScrollBox.on_key(key(:page_down), @props, %{@state | offset: 8}) ==
               {:update, %{@state | offset: 10}}
    end

    test "unsynced (nil) state consumes navigation as a no-op" do
      assert ScrollBox.on_key(key(:down), @props, nil) ==
               {:update, %{offset: 0, viewport: 0, max_offset: 0}}
    end
  end

  describe "on_key/3 fall-through" do
    test "ctrl- and alt-modified keys are ignored" do
      assert ScrollBox.on_key(key(:down, ctrl: true), @props, @state) == :ignored
      assert ScrollBox.on_key(key(:down, alt: true), @props, @state) == :ignored
    end

    test "unhandled keys are ignored" do
      for k <- [:enter, :space, :escape, :left, :right, :tab, "a"] do
        assert ScrollBox.on_key(key(k), @props, @state) == :ignored
      end
    end
  end

  describe "mark_props/2" do
    test "injects the stored offset" do
      assert ScrollBox.mark_props(@props, @state) == %{scroll_offset: 5}
    end

    test "nil state marks an unscrolled box" do
      assert ScrollBox.mark_props(@props, nil) == %{scroll_offset: 0}
    end

    test "snap: :bottom pins the box while at the bottom" do
      props = Map.put(@props, :snap, :bottom)

      assert ScrollBox.mark_props(props, %{@state | offset: 10}) == %{scroll_offset: :bottom}
      assert ScrollBox.mark_props(props, nil) == %{scroll_offset: :bottom}

      # Scrolled up: detached, keeps the plain offset.
      assert ScrollBox.mark_props(props, @state) == %{scroll_offset: 5}
    end
  end

  describe "resolve_offset/3" do
    test "defaults to the top without a stored offset" do
      assert ScrollBox.resolve_offset(%{}, 10, 4) == 0
    end

    test "snap: :bottom defaults to the bottom" do
      assert ScrollBox.resolve_offset(%{snap: :bottom}, 10, 4) == 6
    end

    test ":bottom resolves to the scrollable range" do
      assert ScrollBox.resolve_offset(%{scroll_offset: :bottom}, 10, 4) == 6
    end

    test "integer offsets are clamped" do
      assert ScrollBox.resolve_offset(%{scroll_offset: 3}, 10, 4) == 3
      assert ScrollBox.resolve_offset(%{scroll_offset: 99}, 10, 4) == 6
      assert ScrollBox.resolve_offset(%{scroll_offset: -1}, 10, 4) == 0
    end

    test "content that fits never scrolls" do
      assert ScrollBox.resolve_offset(%{scroll_offset: 3}, 4, 10) == 0
      assert ScrollBox.resolve_offset(%{scroll_offset: :bottom}, 4, 10) == 0
    end
  end

  describe "thumb/4" do
    test "thumb height is the visible share of the content" do
      # 10-row track, half the content visible: 5-row thumb.
      assert ScrollBox.thumb(0, 20, 10, 10) == {0, 5}
    end

    test "thumb is at least one row" do
      assert {_row, 1} = ScrollBox.thumb(0, 1000, 10, 10)
    end

    test "thumb position tracks the offset, hitting both ends exactly" do
      # content 20, viewport 10 -> max_offset 10; track 10, thumb 5.
      assert ScrollBox.thumb(0, 20, 10, 10) == {0, 5}
      assert ScrollBox.thumb(5, 20, 10, 10) == {3, 5}
      assert ScrollBox.thumb(10, 20, 10, 10) == {5, 5}
    end

    test "content that fits fills the track at the top" do
      assert ScrollBox.thumb(0, 5, 10, 10) == {0, 10}
    end

    test "degenerate track" do
      assert ScrollBox.thumb(0, 20, 10, 0) == {0, 0}
    end
  end
end
