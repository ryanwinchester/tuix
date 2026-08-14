defmodule Tuix.Runtime do
  @moduledoc """
  The event loop: holds the `Tuix.App` state, dispatches input and resize
  events to the app's callbacks, and re-renders after every state change.

  Rendering is event-driven — nothing is written to the terminal unless
  state may have changed, and only changed cells are written.
  """

  # :temporary - when the app stops (normally or not), Tuix.run/2 tears the
  # whole tree down rather than the supervisor restarting the runtime.
  use GenServer, restart: :temporary

  alias Tuix.App
  alias Tuix.Event
  alias Tuix.Renderer
  alias Tuix.Terminal

  @resize_poll_ms 250

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    exit_on_ctrl_c = Keyword.get(opts, :exit_on_ctrl_c, true)

    {:ok, app} = call_mount(module, opts)

    {width, height} = Terminal.size()

    state = %{
      module: module,
      app: app,
      size: {width, height},
      prev_buffer: nil,
      exit_on_ctrl_c: exit_on_ctrl_c
    }

    {:ok, _reader} = Tuix.Input.start_link(self())
    Process.send_after(self(), :tuix_resize_poll, @resize_poll_ms)

    {:ok, render_frame(state)}
  end

  @impl true
  def handle_info(
        {:tuix_input, %Event.Key{key: "c", ctrl: true}},
        %{exit_on_ctrl_c: true} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info({:tuix_input, event}, state) do
    dispatch(state, fn -> state.module.handle_event(event, state.app) end)
  end

  def handle_info(:tuix_resize_poll, state) do
    Process.send_after(self(), :tuix_resize_poll, @resize_poll_ms)

    case Terminal.size() do
      size when size == state.size ->
        {:noreply, state}

      {width, height} ->
        # Full repaint on resize.
        state = %{state | size: {width, height}, prev_buffer: nil}
        event = %Event.Resize{width: width, height: height}
        dispatch(state, fn -> state.module.handle_event(event, state.app) end)
    end
  end

  def handle_info(message, state) do
    dispatch(state, fn -> state.module.handle_info(message, state.app) end)
  end

  ## Helpers

  defp dispatch(state, fun) do
    case fun.() do
      {:noreply, %App{} = app} ->
        {:noreply, maybe_render(state, app)}

      {:stop, reason, %App{} = app} ->
        {:stop, reason, %{state | app: app}}
    end
  end

  # render/1 is pure over assigns, so unchanged assigns mean an unchanged
  # frame — unless a resize invalidated the previous buffer.
  defp maybe_render(
         %{app: %{assigns: assigns}, prev_buffer: prev} = state,
         %{assigns: assigns} = app
       )
       when prev != nil do
    %{state | app: app}
  end

  defp maybe_render(state, app) do
    render_frame(%{state | app: app})
  end

  defp render_frame(state) do
    {width, height} = state.size

    buffer =
      state.app.assigns
      |> state.module.render()
      |> Renderer.render(width, height)

    Terminal.write(Renderer.to_iodata(buffer, state.prev_buffer))

    %{state | prev_buffer: buffer}
  end

  defp call_mount(module, opts) do
    app = %App{module: module}

    if function_exported?(module, :mount, 2) do
      module.mount(Keyword.drop(opts, [:module, :exit_on_ctrl_c]), app)
    else
      {:ok, app}
    end
  end
end
