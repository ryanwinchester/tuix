defmodule Tuix.Runtime do
  @moduledoc """
  The event loop: holds the `Tuix.App` state, dispatches input and resize
  events to the app's callbacks, manages keyboard focus (Tab / Shift+Tab
  traversal over `focusable` elements, click-to-focus for mouse presses),
  routes keys to the focused component element (see `Tuix.Component`),
  stamps mouse events with the hit-tested target (see `Tuix.HitTest`),
  scrolls the scroll box under the pointer on wheel events, synthesizes
  `:click` events from press/release pairs (see `Tuix.Runtime.Click`), and
  re-renders after every state change.

  Rendering is event-driven — nothing is written to the terminal unless
  state may have changed, and only changed cells are written.
  """

  # :temporary - when the app stops (normally or not), Tuix.run/2 tears the
  # whole tree down rather than the supervisor restarting the runtime.
  use GenServer, restart: :temporary

  alias Tuix.App
  alias Tuix.Buffer
  alias Tuix.Components.ScrollBox
  alias Tuix.Element
  alias Tuix.Event
  alias Tuix.Focus
  alias Tuix.HitTest
  alias Tuix.Layout
  alias Tuix.Layout.Placed
  alias Tuix.Renderer
  alias Tuix.Runtime.Click
  alias Tuix.Terminal

  @resize_poll_ms 250

  # Tag -> Tuix.Component module for focusable, stateful element kinds.
  @components %{
    input: Tuix.Components.Input,
    select: Tuix.Components.Select,
    scroll_box: Tuix.Components.ScrollBox
  }

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
      exit_on_ctrl_c: exit_on_ctrl_c,
      resize: subscribe_resize(),
      tree: nil,
      placed: nil,
      pressed: nil,
      focus_order: [],
      autofocused: false
    }

    {:ok, _reader} = Tuix.Input.start_link(self())
    if state.resize == :poll, do: schedule_resize_poll()

    {:ok, render_frame(state)}
  end

  @impl true
  def handle_info(
        {:tuix_input, %Event.Key{key: "c", ctrl: true}},
        %{exit_on_ctrl_c: true} = state
      ) do
    {:stop, :normal, state}
  end

  # Tab / Shift+Tab move focus through the focus order collected from the
  # last rendered tree. Consumed only when something is focusable; otherwise
  # they fall through to the app's handle_event/2.
  def handle_info(
        {:tuix_input, %Event.Key{key: key}},
        %{focus_order: [_ | _] = order} = state
      )
      when key in [:tab, :backtab] do
    current = App.focused(state.app)
    to = if key == :tab, do: Focus.next(order, current), else: Focus.prev(order, current)
    app = App.focus(state.app, to)

    # dispatch/2 detects the focus change and delivers the Focus event.
    dispatch(state, fn -> {:noreply, app} end)
  end

  # The wheel scrolls the scroll box under the pointer — hover-based, no
  # focus required. Consumed ticks (like keyboard scrolling) never reach
  # the app; wheel events over anything else fall through with `target`
  # set. Clamped boundary ticks leave the state unchanged, so no frame is
  # rendered.
  def handle_info({:tuix_input, %Event.Mouse{kind: kind} = event}, state)
      when kind in [:scroll_up, :scroll_down] do
    case HitTest.scroll_box_at(state.placed, {event.x, event.y}) do
      nil ->
        deliver_mouse(state, event)

      id ->
        scroll_state = ScrollBox.wheel(kind, component_state(state.app, id))
        dispatch(state, fn -> {:noreply, put_component_state(state.app, id, scroll_state)} end)
    end
  end

  # Mouse events are stamped with the hit-tested target (the innermost
  # focusable element under the pointer). A left press on a focusable
  # element focuses it — dispatch/2 detects the change and delivers the
  # Focus event — and every mouse event reaches the app's handle_event/2.
  def handle_info({:tuix_input, %Event.Mouse{} = event}, state) do
    deliver_mouse(state, event)
  end

  # Keys are offered to the focused component first (input editing, select
  # navigation); keys the component does not handle — and all keys when the
  # focused element is not a component — fall through to the app with
  # `target` set.
  def handle_info({:tuix_input, event}, state) do
    focused = App.focused(state.app)

    case route_to_component(state, event, focused) do
      :fallthrough ->
        event = stamp_target(event, focused)
        dispatch(state, fn -> state.module.handle_event(event, state.app) end)

      reply ->
        reply
    end
  end

  def handle_info(:tuix_check_resize, state) do
    if state.resize == :poll, do: schedule_resize_poll()

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

  # The SIGWINCH handler was removed (crashed or the signal server restarted);
  # fall back to polling so resizes are still detected.
  def handle_info({:gen_event_EXIT, Tuix.Runtime.SignalHandler, _reason}, state) do
    schedule_resize_poll()
    {:noreply, %{state | resize: :poll}}
  end

  def handle_info(message, state) do
    dispatch(state, fn -> state.module.handle_info(message, state.app) end)
  end

  ## Helpers

  # Prefers SIGWINCH delivery (available on Unix as of OTP 29) and falls
  # back to polling (Windows, or restricted environments). The handler is
  # supervised: if it dies, the runtime receives :gen_event_EXIT and
  # switches to polling.
  defp subscribe_resize do
    with :ok <- set_sigwinch(),
         :ok <-
           :gen_event.add_sup_handler(:erl_signal_server, Tuix.Runtime.SignalHandler, self()) do
      :signal
    else
      _ -> :poll
    end
  end

  defp set_sigwinch do
    :os.set_signal(:sigwinch, :handle)
  catch
    _, _ -> :error
  end

  defp schedule_resize_poll do
    Process.send_after(self(), :tuix_check_resize, @resize_poll_ms)
  end

  defp dispatch(state, fun) do
    case run_callback(state, fun) do
      {:noreply, %App{} = app} ->
        {:noreply, maybe_render(state, app)}

      {:stop, reason, %App{} = app} ->
        {:stop, reason, %{state | app: app}}
    end
  end

  # Runs the callback and, when it changed focus (Tab traversal or a
  # programmatic focus/2 / blur/1), delivers Focus events until focus
  # settles. The final app is rendered once by dispatch/2.
  defp run_callback(state, fun) do
    from = App.focused(state.app)

    case fun.() do
      {:noreply, %App{} = app} -> notify_focus(state.module, app, from)
      {:stop, _reason, %App{}} = stop -> stop
    end
  end

  defp notify_focus(module, app, from) do
    case App.focused(app) do
      ^from ->
        {:noreply, app}

      to ->
        case module.handle_event(%Event.Focus{id: to, from: from}, app) do
          {:noreply, %App{} = app} -> notify_focus(module, app, to)
          {:stop, _reason, %App{}} = stop -> stop
        end
    end
  end

  defp stamp_target(%Event.Key{} = event, target), do: %{event | target: target}
  defp stamp_target(event, _target), do: event

  # Stamps the hit-tested target, applies click-to-focus, and delivers the
  # mouse event to the app — followed by the synthesized :click event when
  # a release completes one (see Tuix.Runtime.Click).
  defp deliver_mouse(state, %Event.Mouse{} = event) do
    target = HitTest.focusable_at(state.placed, {event.x, event.y})
    event = %{event | target: target}
    app = click_focus(state.app, event, state.focus_order)
    {pressed, click} = Click.track(state.pressed, event)
    state = %{state | pressed: pressed}

    case dispatch(state, fn -> state.module.handle_event(event, app) end) do
      {:noreply, state} when click != nil ->
        dispatch(state, fn -> state.module.handle_event(click, state.app) end)

      reply ->
        reply
    end
  end

  # Click-to-focus: a left press on a focusable element moves focus to it.
  # Clicking empty (or non-focusable) space does not blur.
  defp click_focus(app, %Event.Mouse{kind: :press, button: :left, target: target}, order)
       when target != nil do
    if target in order and App.focused(app) != target do
      App.focus(app, target)
    else
      app
    end
  end

  defp click_focus(app, _event, _order), do: app

  ## Component routing

  defp route_to_component(state, %Event.Key{} = event, focused) do
    case focused_component(state.tree, focused) do
      nil ->
        :fallthrough

      {module, %Element{props: props}} ->
        case module.on_key(event, props, component_state(state.app, focused)) do
          {:emit, component_event, new_state} ->
            # Components are controlled: report the change and let the app
            # apply it.
            app = put_component_state(state.app, focused, new_state)
            dispatch(state, fn -> state.module.handle_event(component_event, app) end)

          {:update, new_state} ->
            dispatch(state, fn ->
              {:noreply, put_component_state(state.app, focused, new_state)}
            end)

          :ignored ->
            :fallthrough
        end
    end
  end

  defp route_to_component(_state, _event, _focused), do: :fallthrough

  defp focused_component(%Element{} = tree, focused) do
    with %Element{tag: tag} = element <- Focus.find(tree, focused),
         {:ok, module} <- Map.fetch(@components, tag) do
      {module, element}
    else
      _other -> nil
    end
  end

  defp focused_component(_tree, _focused), do: nil

  defp component_state(app, id) do
    app.private |> Map.get(:component_state, %{}) |> Map.get(id)
  end

  defp put_component_state(app, id, component_state) do
    states = app.private |> Map.get(:component_state, %{}) |> Map.put(id, component_state)
    %{app | private: Map.put(app.private, :component_state, states)}
  end

  # Drops ephemeral state for components that left the tree.
  defp prune_component_state(app, order) do
    case Map.get(app.private, :component_state) do
      nil ->
        app

      states ->
        case Map.take(states, order) do
          ^states ->
            app

          pruned when pruned == %{} ->
            %{app | private: Map.delete(app.private, :component_state)}

          pruned ->
            %{app | private: Map.put(app.private, :component_state, pruned)}
        end
    end
  end

  # render/1 is pure over assigns, so unchanged assigns (and unchanged
  # framework state such as focus) mean an unchanged frame — unless a
  # resize invalidated the previous buffer.
  defp maybe_render(
         %{app: %{assigns: assigns, private: private}, prev_buffer: prev} = state,
         %{assigns: assigns, private: private} = app
       )
       when prev != nil do
    %{state | app: app}
  end

  defp maybe_render(state, app) do
    render_frame(%{state | app: app})
  end

  defp render_frame(state) do
    {width, height} = state.size

    tree = state.module.render(state.app.assigns)
    order = Focus.order(tree)

    app =
      state.app
      |> reconcile_focus(tree, order, state)
      |> prune_component_state(order)

    focused = App.focused(app)

    placed =
      tree
      |> mark_scroll_offsets(app)
      |> Focus.mark(focused, mark_props(app, tree, focused))
      |> Layout.compute(width, height)

    app = sync_scroll_state(app, placed)

    buffer = Renderer.paint(placed, Buffer.new(width, height))
    Terminal.write(Renderer.to_iodata(buffer, state.prev_buffer))

    %{
      state
      | app: app,
        tree: tree,
        placed: placed,
        focus_order: order,
        autofocused: true,
        prev_buffer: buffer
    }
  end

  # Scroll boxes keep their scroll position while unfocused, so every
  # scroll box with stored state gets its offset injected before layout
  # (`Focus.mark/3` only decorates the focused element).
  defp mark_scroll_offsets(%Element{} = element, app) do
    element = %{element | children: Enum.map(element.children, &mark_scroll_offsets(&1, app))}

    with :scroll_box <- element.tag,
         %{id: id} <- element.props,
         state when state != nil <- component_state(app, id) do
      %{element | props: Map.merge(element.props, ScrollBox.mark_props(element.props, state))}
    else
      _ -> element
    end
  end

  # After layout, refreshes each scroll box's framework state with the
  # measured viewport height and scrollable range — and the offset those
  # imply (clamped, or pinned to the bottom for `snap: :bottom` boxes) —
  # so `on_key/3` can page and clamp without recomputing layout.
  defp sync_scroll_state(app, %Placed{} = placed) do
    placed
    |> collect_scroll_state([])
    |> Enum.reduce(app, fn {id, scroll_state}, app ->
      if component_state(app, id) == scroll_state do
        app
      else
        put_component_state(app, id, scroll_state)
      end
    end)
  end

  defp collect_scroll_state(%Placed{element: element, children: children} = placed, acc) do
    acc =
      case element do
        %Element{tag: :scroll_box, props: %{id: id} = props} ->
          {_vx, vy, _vw, vh} = ScrollBox.viewport(props, placed.rect)
          content_h = ScrollBox.content_height(children, vy)

          scroll_state = %{
            offset: ScrollBox.resolve_offset(props, content_h, vh),
            viewport: vh,
            max_offset: ScrollBox.max_offset(content_h, vh)
          }

          [{id, scroll_state} | acc]

        _other ->
          acc
      end

    Enum.reduce(children, acc, &collect_scroll_state/2)
  end

  # Extra props injected into the focused element before painting (e.g. a
  # focused input's cursor offset).
  defp mark_props(app, tree, focused) do
    case focused_component(tree, focused) do
      nil -> %{}
      {module, %Element{props: props}} -> module.mark_props(props, component_state(app, focused))
    end
  end

  # Clears focus when the focused element left the tree, and applies
  # `autofocus: true` on the first frame when nothing is focused. Both are
  # silent (no Focus event).
  defp reconcile_focus(app, tree, order, state) do
    case App.focused(app) do
      nil ->
        if state.autofocused, do: app, else: App.focus(app, Focus.autofocus(tree))

      focused ->
        if focused in order, do: app, else: App.blur(app)
    end
  end

  defp call_mount(module, opts) do
    app = %App{module: module}

    if function_exported?(module, :mount, 2) do
      module.mount(Keyword.drop(opts, [:module, :exit_on_ctrl_c, :mouse]), app)
    else
      {:ok, app}
    end
  end
end
