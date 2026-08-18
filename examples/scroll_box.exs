# Run with: mix run examples/scroll_box.exs
#
# Demonstrates the scroll box component:
#
#   * a focusable scrolling container — ↑/↓ scroll by a row, PgUp/PgDn by a
#     page, Home/End jump to the boundaries
#   * a proportional scrollbar drawn over the border
#   * a snap: :bottom log that stays pinned to the newest entry as lines
#     arrive (scroll up to detach, End to re-attach)
#   * Tab moves between the two panes
defmodule ScrollBoxDemo do
  use Tuix.App

  alias Tuix.Event

  @impl true
  def mount(_opts, app) do
    :timer.send_interval(1_000, :tick)

    lines = for n <- 1..50, do: "#{String.pad_leading(to_string(n), 3)} · line"
    {:ok, assign(app, lines: lines, log: ["booted"], tick: 0)}
  end

  @impl true
  def handle_event(%Event.Key{key: :escape}, app), do: {:stop, :normal, app}
  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def handle_info(:tick, app) do
    tick = app.assigns.tick + 1

    app =
      app
      |> assign(tick: tick)
      |> update(:log, &(&1 ++ ["tick #{tick}"]))

    {:noreply, app}
  end

  @impl true
  def render(assigns) do
    box padding: 1, gap: 1, flex_direction: :row, height: 14 do
      scroll_box id: :list,
                 border: :rounded,
                 title: "Scroll me",
                 width: 24,
                 autofocus: true,
                 focus_border_color: :cyan do
        for line <- assigns.lines, do: text(line)
      end

      box gap: 1, flex_grow: 1 do
        scroll_box id: :log,
                   snap: :bottom,
                   border: :rounded,
                   title: "Tail (snap: :bottom)",
                   flex_grow: 1,
                   focus_border_color: :cyan do
          for line <- assigns.log, do: text(line, fg: :green)
        end

        text "Tab to switch, ↑/↓ PgUp/PgDn Home/End to scroll, Esc to quit",
          fg: :bright_black
      end
    end
  end
end

Tuix.run(ScrollBoxDemo)
