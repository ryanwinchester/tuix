defmodule Tuix.App do
  @moduledoc """
  The behaviour for Tuix applications, modeled after Phoenix LiveView.

  An app holds its state in `assigns`, reacts to events and messages, and
  declaratively describes its UI in `c:render/1`. Tuix re-renders after every
  callback and writes only the changed terminal cells.

  ## Example

      defmodule Counter do
        use Tuix.App

        @impl true
        def mount(_opts, app), do: {:ok, assign(app, count: 0)}

        @impl true
        def handle_event(%Tuix.Event.Key{key: :up}, app),
          do: {:noreply, update(app, :count, &(&1 + 1))}

        def handle_event(%Tuix.Event.Key{key: :down}, app),
          do: {:noreply, update(app, :count, &(&1 - 1))}

        def handle_event(%Tuix.Event.Key{key: "q"}, app),
          do: {:stop, :normal, app}

        def handle_event(_event, app), do: {:noreply, app}

        @impl true
        def render(assigns) do
          box border: :rounded, padding: 1 do
            text("Count: \#{assigns.count}", fg: :green)
          end
        end
      end

      Tuix.run(Counter)

  Because the runtime is a regular process, any Elixir message — timer ticks,
  `Task` results, PubSub broadcasts — can drive the UI through
  `c:handle_info/2`.
  """

  alias Tuix.Element

  defstruct assigns: %{}, module: nil, private: %{}

  @type t :: %__MODULE__{assigns: map(), module: module(), private: map()}

  @doc "Initializes state. Receives the options passed to `Tuix.run/2`."
  @callback mount(opts :: keyword(), app :: t()) :: {:ok, t()}

  @doc "Handles keyboard and resize events."
  @callback handle_event(event :: Tuix.Event.t(), app :: t()) ::
              {:noreply, t()} | {:stop, reason :: term(), t()}

  @doc "Handles arbitrary Elixir messages sent to the runtime process."
  @callback handle_info(message :: term(), app :: t()) ::
              {:noreply, t()} | {:stop, reason :: term(), t()}

  @doc "Returns the element tree for the current assigns."
  @callback render(assigns :: map()) :: Element.t()

  @optional_callbacks mount: 2, handle_event: 2, handle_info: 2

  @doc """
  Assigns a key/value pair (or many, from a keyword list or map) into the app.
  """
  def assign(%__MODULE__{} = app, key, value) do
    %{app | assigns: Map.put(app.assigns, key, value)}
  end

  def assign(%__MODULE__{} = app, key_values) do
    %{app | assigns: Map.merge(app.assigns, Map.new(key_values))}
  end

  @doc """
  Updates an existing assign with a function.
  """
  def update(%__MODULE__{} = app, key, fun) when is_function(fun, 1) do
    %{app | assigns: Map.update!(app.assigns, key, fun)}
  end

  @doc """
  Returns the id of the currently focused element, or `nil`.
  """
  @spec focused(t()) :: term() | nil
  def focused(%__MODULE__{} = app), do: Map.get(app.private, :focus)

  @doc """
  Focuses the element with the given id.

  The element should be rendered with `focusable: true` and a matching
  `:id` prop; if it is absent from the next rendered tree, focus is
  cleared. Focusing `nil` is equivalent to `blur/1`.
  """
  @spec focus(t(), term() | nil) :: t()
  def focus(%__MODULE__{} = app, nil), do: blur(app)
  def focus(%__MODULE__{} = app, id), do: %{app | private: Map.put(app.private, :focus, id)}

  @doc """
  Clears focus.
  """
  @spec blur(t()) :: t()
  def blur(%__MODULE__{} = app), do: %{app | private: Map.delete(app.private, :focus)}

  defmacro __using__(_opts) do
    quote do
      @behaviour Tuix.App

      import Tuix.App, only: [assign: 2, assign: 3, update: 3, focused: 1, focus: 2, blur: 1]
      import Tuix.Components

      @impl Tuix.App
      def mount(_opts, app), do: {:ok, app}

      @impl Tuix.App
      def handle_event(_event, app), do: {:noreply, app}

      @impl Tuix.App
      def handle_info(_message, app), do: {:noreply, app}

      defoverridable mount: 2, handle_event: 2, handle_info: 2
    end
  end
end
