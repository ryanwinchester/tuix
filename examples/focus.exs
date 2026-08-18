# Run with: mix run examples/focus.exs
#
# Demonstrates the focus model:
#
#   * Tab / Shift+Tab cycle focus through the three panes
#   * the focused pane gets a cyan border (focus_border_color)
#   * Up / Down adjust only the focused pane, via `target` matching
#   * the first pane is focused on startup (autofocus)
#   * Focus events update the status line
defmodule FocusDemo do
  use Tuix.App

  alias Tuix.Event.Focus
  alias Tuix.Event.Key

  @panes [:one, :two, :three]

  @impl true
  def mount(_opts, app) do
    {:ok, assign(app, counts: Map.new(@panes, &{&1, 0}), last_focus: nil)}
  end

  @impl true
  def handle_event(%Key{key: :up, target: pane}, app) when pane in @panes do
    {:noreply, update(app, :counts, &Map.update!(&1, pane, fn n -> n + 1 end))}
  end

  def handle_event(%Key{key: :down, target: pane}, app) when pane in @panes do
    {:noreply, update(app, :counts, &Map.update!(&1, pane, fn n -> n - 1 end))}
  end

  # Jump focus programmatically with 1 / 2 / 3.
  def handle_event(%Key{key: digit}, app) when digit in ~w(1 2 3) do
    {:noreply, focus(app, Enum.at(@panes, String.to_integer(digit) - 1))}
  end

  def handle_event(%Focus{id: id}, app) do
    {:noreply, assign(app, last_focus: id)}
  end

  def handle_event(%Key{key: "q"}, app), do: {:stop, :normal, app}
  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box padding: 1, gap: 1 do
      box flex_direction: :row, gap: 1 do
        for pane <- @panes do
          box id: pane,
              focusable: true,
              autofocus: pane == :one,
              border: :rounded,
              focus_border_color: :cyan,
              title: "Pane #{pane}",
              padding: 1,
              flex_grow: 1 do
            text "Count: #{assigns.counts[pane]}", attrs: [:bold]
          end
        end
      end

      text "Focused: #{assigns.last_focus || "pane one (autofocus)"}", fg: :bright_black

      text "Tab / Shift+Tab to move focus, 1-3 to jump, Up / Down to change, q to quit",
        fg: :bright_black
    end
  end
end

Tuix.run(FocusDemo)
