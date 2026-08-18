defmodule Tuix.Event do
  @moduledoc """
  Events delivered to a `Tuix.App`'s `c:Tuix.App.handle_event/2` callback.
  """

  defmodule Key do
    @moduledoc """
    A keyboard event.

    `key` is either a single printable grapheme (`"a"`, `"+"`, `"é"`) or a
    named key atom:

    `:enter`, `:tab`, `:backtab`, `:backspace`, `:escape`, `:up`, `:down`,
    `:left`, `:right`, `:home`, `:end`, `:insert`, `:delete`, `:page_up`,
    `:page_down`, `:space`

    `target` is the id of the focused element at the time of the event
    (`nil` when nothing is focused), stamped by the runtime so apps can
    pattern match on it:

        def handle_event(%Key{key: :enter, target: :email}, app), do: ...
    """

    defstruct key: nil, ctrl: false, alt: false, shift: false, target: nil

    @type t :: %__MODULE__{
            key: String.t() | atom(),
            ctrl: boolean(),
            alt: boolean(),
            shift: boolean(),
            target: term() | nil
          }
  end

  defmodule Mouse do
    @moduledoc """
    A mouse event.

    `kind` is one of:

      * `:press` / `:release` - a button went down / up
      * `:drag` - the pointer moved while a button was held
      * `:scroll_up` / `:scroll_down` - the wheel turned

    `button` is `:left`, `:middle`, or `:right` (`nil` for wheel events and
    releases that do not report a button). `x` and `y` are 0-based cell
    coordinates.

    `target` is the id of the innermost focusable element under the pointer
    (`nil` when none), stamped by the runtime so apps can pattern match on
    it:

        def handle_event(%Mouse{kind: :press, target: :sidebar}, app), do: ...
    """

    defstruct kind: nil,
              button: nil,
              x: 0,
              y: 0,
              ctrl: false,
              alt: false,
              shift: false,
              target: nil

    @type kind :: :press | :release | :drag | :scroll_up | :scroll_down
    @type button :: :left | :middle | :right | nil

    @type t :: %__MODULE__{
            kind: kind(),
            button: button(),
            x: non_neg_integer(),
            y: non_neg_integer(),
            ctrl: boolean(),
            alt: boolean(),
            shift: boolean(),
            target: term() | nil
          }
  end

  defmodule Resize do
    @moduledoc "A terminal resize event."

    defstruct [:width, :height]

    @type t :: %__MODULE__{width: pos_integer(), height: pos_integer()}
  end

  defmodule Input do
    @moduledoc """
    Delivered when a focused input's value changes.

    Inputs are controlled: the app owns the value, so it should assign
    `value` back into state (or a transformation of it — e.g. to enforce
    a format) for the change to appear:

        def handle_event(%Tuix.Event.Input{id: :email, value: value}, app),
          do: {:noreply, assign(app, email: value)}
    """

    defstruct [:id, :value]

    @type t :: %__MODULE__{id: term(), value: String.t()}
  end

  defmodule Select do
    @moduledoc """
    Delivered when a focused select's selection moves (selects are
    controlled and the selection follows the highlight, so `:up` / `:down`
    emit this immediately).

    The app owns the value: assign it back into state for the selection
    to appear.

        def handle_event(%Tuix.Event.Select{id: :plan, value: value}, app),
          do: {:noreply, assign(app, plan: value)}
    """

    defstruct [:id, :value]

    @type t :: %__MODULE__{id: term(), value: term()}
  end

  defmodule Focus do
    @moduledoc """
    Delivered when focus moves — via Tab traversal or programmatically with
    `Tuix.App.focus/2` / `Tuix.App.blur/1`.

    `id` is the newly focused element id (`nil` after a blur) and `from` is
    the previously focused id (`nil` when nothing was focused).
    """

    defstruct [:id, :from]

    @type t :: %__MODULE__{id: term() | nil, from: term() | nil}
  end

  @type t :: Key.t() | Mouse.t() | Resize.t() | Input.t() | Select.t() | Focus.t()
end
