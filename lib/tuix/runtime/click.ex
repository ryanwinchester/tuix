defmodule Tuix.Runtime.Click do
  @moduledoc """
  Synthesizes `:click` events from raw press/release pairs.

  The runtime threads the pressed-button state through `track/2` for every
  mouse event it delivers: a `:press` records `{button, target}`, and a
  `:release` on the same target completes the click — a
  `%Tuix.Event.Mouse{kind: :click}` delivered after the release event
  itself. Releasing over a different target cancels the click; drags in
  between do not (terminal cells are coarse, and this matches the browser
  model).

  X10-encoded releases do not report which button went up (`button: nil`);
  they complete the click for whatever button is tracked, and the
  synthesized event carries the pressed button.
  """

  alias Tuix.Event.Mouse

  @typedoc "The tracked press: `{button, target}`, or `nil` when no button is down."
  @type pressed :: {Mouse.button(), term() | nil} | nil

  @doc """
  Threads a mouse event through the click tracker.

  Returns `{pressed, click}` — the updated tracking state and the
  synthesized `:click` event (or `nil`).
  """
  @spec track(pressed(), Mouse.t()) :: {pressed(), Mouse.t() | nil}
  def track(_pressed, %Mouse{kind: :press, button: button, target: target}) do
    {{button, target}, nil}
  end

  def track({button, target}, %Mouse{kind: :release, button: released, target: target} = event)
      when released == button or is_nil(released) do
    {nil, %{event | kind: :click, button: button}}
  end

  # The tracked button went up somewhere else: the click is cancelled.
  def track({button, _target}, %Mouse{kind: :release, button: released})
      when released == button or is_nil(released) do
    {nil, nil}
  end

  def track(pressed, %Mouse{}), do: {pressed, nil}
end
