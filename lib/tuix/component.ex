defmodule Tuix.Component do
  @moduledoc """
  The behaviour for focusable, stateful element kinds (`input`, `select`,
  `scroll_box`).

  When a key reaches a focused component element, the runtime looks up the
  module for its tag and calls `c:on_key/3` with the element's props (from
  the last rendered tree) and the component's ephemeral state (from
  `Tuix.App` `private`, e.g. an input's cursor offset). The component
  either:

    * emits an event to the app (`{:emit, event, state}`) — components are
      controlled, so value changes are reported rather than applied
    * updates only its ephemeral state (`{:update, state}`) — also used for
      consumed no-ops (e.g. backspace at the start of an input)
    * ignores the key (`:ignored`) — it falls through to the app's
      `c:Tuix.App.handle_event/2` with `target` set

  Before painting, `c:mark_props/2` computes props to merge into the
  focused element (e.g. the input's cursor) via `Tuix.Focus.mark/3`.
  """

  alias Tuix.Event.Key

  @typedoc "Ephemeral, framework-managed component state (`nil` when unset)."
  @type state :: term()

  @callback on_key(Key.t(), props :: map(), state()) ::
              {:emit, event :: struct(), state()} | {:update, state()} | :ignored

  @callback mark_props(props :: map(), state()) :: map()
end
