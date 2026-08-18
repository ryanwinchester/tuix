# Run with: mix run examples/login.exs
#
# Demonstrates the input component:
#
#   * two controlled inputs (value lives in assigns, updated from
#     %Tuix.Event.Input{} events)
#   * Tab / Shift+Tab move between them; the focused field's border
#     highlights via focus_border_color on the wrapping box (focus-within)
#   * the password input is masked
#   * Enter submits (falls through to the app with `target` set)
defmodule Login do
  use Tuix.App

  alias Tuix.Event

  @impl true
  def mount(_opts, app) do
    {:ok, assign(app, email: "", password: "", status: nil)}
  end

  @impl true
  def handle_event(%Event.Input{id: :email, value: value}, app) do
    {:noreply, assign(app, email: value, status: nil)}
  end

  def handle_event(%Event.Input{id: :password, value: value}, app) do
    {:noreply, assign(app, password: value, status: nil)}
  end

  def handle_event(%Event.Key{key: :enter}, app) do
    status =
      cond do
        app.assigns.email == "" -> {"Email is required", :red}
        app.assigns.password == "" -> {"Password is required", :red}
        true -> {"Welcome, #{app.assigns.email}!", :green}
      end

    {:noreply, assign(app, status: status)}
  end

  def handle_event(%Event.Key{key: :escape}, app), do: {:stop, :normal, app}
  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box padding: 1, gap: 1, width: 40 do
      field(
        "Email",
        input(
          id: :email,
          value: assigns.email,
          placeholder: "you@example.com",
          autofocus: true
        )
      )

      field(
        "Password",
        input(
          id: :password,
          value: assigns.password,
          placeholder: "hunter2",
          mask: "•"
        )
      )

      status(assigns.status)

      text "Tab to switch, Enter to submit, Esc to quit", fg: :bright_black
    end
  end

  # The box highlights while its input has focus (focus-within): no
  # assigns bookkeeping needed.
  defp field(title, input_element) do
    box border: :rounded, title: title, focus_border_color: :magenta do
      input_element
    end
  end

  defp status(nil), do: text("")
  defp status({message, color}), do: text(message, fg: color, attrs: [:bold])
end

Tuix.run(Login)
