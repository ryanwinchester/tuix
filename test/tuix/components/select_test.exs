defmodule Tuix.Components.SelectTest do
  use ExUnit.Case, async: true

  alias Tuix.Components.Select
  alias Tuix.Event
  alias Tuix.Event.Key

  @props %{id: :plan, options: [{"Basic", :basic}, {"Pro", :pro}, {"Team", :team}]}

  defp key(key, mods \\ []), do: struct!(Key, [key: key] ++ mods)

  describe "on_key/3 navigation" do
    test "down moves to the next option" do
      assert Select.on_key(key(:down), Map.put(@props, :value, :basic), nil) ==
               {:emit, %Event.Select{id: :plan, value: :pro}, nil}
    end

    test "up moves to the previous option" do
      assert Select.on_key(key(:up), Map.put(@props, :value, :team), nil) ==
               {:emit, %Event.Select{id: :plan, value: :pro}, nil}
    end

    test "home and end jump to the boundaries" do
      assert Select.on_key(key(:home), Map.put(@props, :value, :team), nil) ==
               {:emit, %Event.Select{id: :plan, value: :basic}, nil}

      assert Select.on_key(key(:end), Map.put(@props, :value, :basic), nil) ==
               {:emit, %Event.Select{id: :plan, value: :team}, nil}
    end

    test "clamps at the boundaries (consumed no-op, no wrap)" do
      assert Select.on_key(key(:up), Map.put(@props, :value, :basic), nil) == {:update, nil}
      assert Select.on_key(key(:down), Map.put(@props, :value, :team), nil) == {:update, nil}
    end

    test "no current selection: up/down/home select the first, end the last" do
      for k <- [:up, :down, :home] do
        assert Select.on_key(key(k), @props, nil) ==
                 {:emit, %Event.Select{id: :plan, value: :basic}, nil}
      end

      assert Select.on_key(key(:end), @props, nil) ==
               {:emit, %Event.Select{id: :plan, value: :team}, nil}
    end

    test "a value not in the options behaves like no selection" do
      assert Select.on_key(key(:down), Map.put(@props, :value, :gone), nil) ==
               {:emit, %Event.Select{id: :plan, value: :basic}, nil}
    end

    test "empty options consume navigation keys" do
      assert Select.on_key(key(:down), %{id: :plan, options: []}, nil) == {:update, nil}
    end
  end

  describe "on_key/3 fall-through" do
    test "ctrl- and alt-modified keys are ignored" do
      assert Select.on_key(key(:down, ctrl: true), @props, nil) == :ignored
      assert Select.on_key(key(:down, alt: true), @props, nil) == :ignored
    end

    test "unhandled keys are ignored" do
      for k <- [:enter, :space, :escape, :left, :right, "a"] do
        assert Select.on_key(key(k), @props, nil) == :ignored
      end
    end
  end

  describe "helpers" do
    test "options/1 normalizes bare strings to their own value" do
      assert Select.options(%{options: ["One", {"Two", 2}]}) == [{"One", "One"}, {"Two", 2}]
      assert Select.options(%{}) == []
    end

    test "selected_index/2" do
      options = Select.options(@props)
      assert Select.selected_index(options, :pro) == 1
      assert Select.selected_index(options, :gone) == nil
      assert Select.selected_index(options, nil) == nil
    end

    test "offset/3 keeps the selection visible" do
      # Everything fits: no scroll.
      assert Select.offset(2, 3, 3) == 0
      assert Select.offset(nil, 10, 3) == 0

      # Selection below the window scrolls down, keeping it on the last row.
      assert Select.offset(5, 10, 3) == 3
      assert Select.offset(9, 10, 3) == 7

      # Never scrolls past the end, and top stays at 0.
      assert Select.offset(0, 10, 3) == 0
      assert Select.offset(1, 10, 3) == 0

      # Degenerate heights.
      assert Select.offset(5, 10, 0) == 0
    end

    test "mark_props/2 injects nothing" do
      assert Select.mark_props(@props, nil) == %{}
    end
  end
end
