defmodule Tuix.AppTest do
  use ExUnit.Case, async: true

  alias Tuix.App
  alias Tuix.TestRenderer

  defmodule Counter do
    use Tuix.App

    @impl true
    def mount(opts, app) do
      {:ok, assign(app, count: Keyword.get(opts, :count, 0))}
    end

    @impl true
    def handle_event(%Tuix.Event.Key{key: "+"}, app) do
      {:noreply, update(app, :count, &(&1 + 1))}
    end

    def handle_event(%Tuix.Event.Key{key: "q"}, app), do: {:stop, :normal, app}
    def handle_event(_event, app), do: {:noreply, app}

    @impl true
    def render(assigns) do
      box border: :single, width: 14, height: 3 do
        text("Count: #{assigns.count}")
      end
    end
  end

  test "assign and update helpers" do
    app = %App{}

    app = App.assign(app, :a, 1)
    assert app.assigns == %{a: 1}

    app = App.assign(app, b: 2, c: 3)
    assert app.assigns == %{a: 1, b: 2, c: 3}

    app = App.update(app, :a, &(&1 + 10))
    assert app.assigns.a == 11
  end

  test "default callbacks from use Tuix.App" do
    defmodule Minimal do
      use Tuix.App

      @impl true
      def render(_assigns), do: text("static")
    end

    app = %App{module: Minimal}
    assert {:ok, ^app} = Minimal.mount([], app)
    assert {:noreply, ^app} = Minimal.handle_event(:anything, app)
    assert {:noreply, ^app} = Minimal.handle_info(:anything, app)
  end

  test "renders an app module through the test renderer" do
    assert TestRenderer.render_to_text(Counter, 14, 3, count: 42) ==
             """
             ┌────────────┐
             │Count: 42   │
             └────────────┘
             """
             |> String.trim_trailing()
  end

  test "event flow updates state" do
    {:ok, app} = Counter.mount([], %App{module: Counter})

    {:noreply, app} = Counter.handle_event(%Tuix.Event.Key{key: "+"}, app)
    {:noreply, app} = Counter.handle_event(%Tuix.Event.Key{key: "+"}, app)
    assert app.assigns.count == 2

    assert {:stop, :normal, _app} = Counter.handle_event(%Tuix.Event.Key{key: "q"}, app)
  end
end
