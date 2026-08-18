# Run with: mix run examples/chat.exs
defmodule Chat do
  use Tuix.App

  alias Tuix.Event

  @bot_names [
    "Alice",
    "Bob",
    "Charlotte",
    "Diego",
    "Emma",
    "Felix",
    "Grace",
    "Henrik",
    "Isabella",
    "Jamal"
  ]

  @bot_phrases [
    "Interesting, tell me more.",
    "I hadn't thought of it that way.",
    "Beep boop. Processing...",
    "That's a great point!",
    "Could you rephrase that?",
    "I'm just a simple bot, but I agree.",
    "Have you tried turning it off and on again?",
    "Fascinating. Go on.",
    "01001000 01101001 (that means hi)",
    "Let me consult my random number generator."
  ]

  # The bot "types" for a random 2-4 seconds before replying.
  @bot_delay_range_ms 1_000..3_000

  @impl true
  def mount(_opts, app) do
    app =
      assign(app,
        screen: :login,
        username: "",
        bot_name: Enum.random(@bot_names),
        messages: [],
        draft: "",
        bot_typing: false,
        height: 24
      )

    {:ok, app}
  end

  # -- Login screen events --

  @impl true
  def handle_event(%Event.Input{id: :username, value: value}, app) do
    {:noreply, assign(app, username: value)}
  end

  def handle_event(%Event.Key{key: :enter, target: :username}, app) do
    case String.trim(app.assigns.username) do
      "" ->
        {:noreply, app}

      username ->
        app =
          app
          |> assign(username: username, screen: :chat)
          |> focus(:draft)

        {:noreply, app}
    end
  end

  # -- Chat screen events --

  def handle_event(%Event.Input{id: :draft, value: value}, app) do
    {:noreply, assign(app, draft: value)}
  end

  def handle_event(%Event.Key{key: :enter, target: :draft}, app) do
    case String.trim(app.assigns.draft) do
      "" ->
        {:noreply, app}

      message ->
        Process.send_after(self(), :bot_reply, Enum.random(@bot_delay_range_ms))

        app =
          app
          |> update(:messages, &(&1 ++ [{:you, message}]))
          |> assign(draft: "", bot_typing: true)

        {:noreply, app}
    end
  end

  def handle_event(%Event.Resize{height: height}, app) do
    {:noreply, assign(app, height: height)}
  end

  def handle_event(%Event.Key{key: :escape}, app), do: {:stop, :normal, app}
  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def handle_info(:bot_reply, app) do
    reply = Enum.random(@bot_phrases)

    app =
      app
      |> update(:messages, &(&1 ++ [{:bot, reply}]))
      |> assign(bot_typing: false)

    {:noreply, app}
  end

  @impl true
  def render(%{screen: :login} = assigns), do: login_screen(assigns)
  def render(%{screen: :chat} = assigns), do: chat_screen(assigns)

  # -- Login screen --

  defp login_screen(assigns) do
    box padding: 1, gap: 1, width: 44 do
      box border: :rounded, title: "Join the chat", focus_border_color: :cyan do
        input(
          id: :username,
          value: assigns.username,
          placeholder: "Pick a username...",
          autofocus: true
        )
      end

      text "Enter to join, Esc to quit", fg: :bright_black
    end
  end

  # -- Chat screen --

  defp chat_screen(assigns) do
    box padding: 1, gap: 1, flex_direction: :column, width: "100%", height: "100%" do
      box flex_direction: :row, gap: 1, flex_grow: 1 do
        box border: :rounded, title: "Chat", padding: 1, flex_grow: 1 do
          for message <- visible_messages(assigns) do
            bubble(message, assigns)
          end

          if assigns.bot_typing do
            text "#{assigns.bot_name} is typing...", fg: :bright_black, attrs: [:italic]
          end
        end

        sidebar(assigns)
      end

      box border: :rounded, title: "Message", focus_border_color: :cyan do
        input id: :draft, value: assigns.draft, placeholder: "Say something..."
      end

      text "Enter to send, Esc to quit", fg: :bright_black
    end
  end

  defp sidebar(assigns) do
    box border: :rounded, title: "Members", padding: 1, width: 20 do
      member(assigns.username <> " (you)", :cyan)
      member(assigns.bot_name, :green)
    end
  end

  defp member(name, color) do
    box flex_direction: :row do
      text "● ", fg: color
      text name
    end
  end

  defp bubble({:you, message}, assigns), do: text("#{assigns.username}: #{message}", fg: :cyan)
  defp bubble({:bot, message}, assigns), do: text("#{assigns.bot_name}: #{message}", fg: :green)

  # No ScrollBox yet, so keep only the messages that fit in the history pane.
  # Chrome outside the history: outer padding (2), gaps (2), input box (3),
  # help line (1), history border + padding (4).
  defp visible_messages(assigns) do
    max_visible = max(assigns.height - 12 - if(assigns.bot_typing, do: 1, else: 0), 1)
    Enum.take(assigns.messages, -max_visible)
  end
end

Tuix.run(Chat)
