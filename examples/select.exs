# Run with: mix run examples/select.exs
#
# Demonstrates the select component:
#
#   * a controlled select (value lives in assigns, updated from
#     %Tuix.Event.Select{} events) — Up/Down/Home/End move the selection
#   * the wrapping box highlights while the select is focused (focus-within)
#   * Enter falls through with `target` set and confirms the choice
#   * Tab moves between the select and the name input
defmodule PlanPicker do
  use Tuix.App

  alias Tuix.Event

  @plans [
    {"Basic — $0/mo", :basic},
    {"Pro — $12/mo", :pro},
    {"Team — $48/mo", :team},
    {"Enterprise — call us", :enterprise}
  ]

  @impl true
  def mount(_opts, app) do
    {:ok, assign(app, name: "", plan: :basic, status: nil)}
  end

  @impl true
  def handle_event(%Event.Input{id: :name, value: value}, app) do
    {:noreply, assign(app, name: value, status: nil)}
  end

  def handle_event(%Event.Select{id: :plan, value: value}, app) do
    {:noreply, assign(app, plan: value, status: nil)}
  end

  def handle_event(%Event.Key{key: :enter}, app) do
    {label, _value} = Enum.find(@plans, &(elem(&1, 1) == app.assigns.plan))
    name = if app.assigns.name == "", do: "stranger", else: app.assigns.name
    {:noreply, assign(app, status: "#{name} picked: #{label}")}
  end

  def handle_event(%Event.Key{key: :escape}, app), do: {:stop, :normal, app}
  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box padding: 1, gap: 1, width: 40 do
      box border: :rounded, title: "Name", focus_border_color: :cyan do
        input id: :name, value: assigns.name, placeholder: "Your name", autofocus: true
      end

      box border: :rounded, title: "Plan", focus_border_color: :cyan do
        select id: :plan, options: @plans, value: assigns.plan, selected_fg: :cyan
      end

      status(assigns.status)

      text "Tab to switch, ↑/↓ to choose, Enter to confirm, Esc to quit", fg: :bright_black
    end
  end

  defp status(nil), do: text("")
  defp status(message), do: text(message, fg: :green, attrs: [:bold])
end

Tuix.run(PlanPicker)
