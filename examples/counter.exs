# Run with: mix run examples/counter.exs
defmodule Counter do
  use Tuix.App

  @impl true
  def mount(_opts, app) do
    {:ok, assign(app, count: 0)}
  end

  @impl true
  def handle_event(%Tuix.Event.Key{key: "+"}, app) do
    {:noreply, update(app, :count, &(&1 + 1))}
  end

  def handle_event(%Tuix.Event.Key{key: "-"}, app) do
    {:noreply, update(app, :count, &(&1 - 1))}
  end

  def handle_event(%Tuix.Event.Key{key: "q"}, app) do
    {:stop, :normal, app}
  end

  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box border: :rounded, title: "Counter", padding: 1, flex_direction: :column, gap: 1 do
      text("Count: #{assigns.count}", fg: "#00FF00", attrs: [:bold])
      text("Press + / - to change, q or Ctrl+C to quit", fg: :bright_black)
    end
  end
end

Tuix.run(Counter)
