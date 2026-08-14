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
    """

    defstruct key: nil, ctrl: false, alt: false, shift: false

    @type t :: %__MODULE__{
            key: String.t() | atom(),
            ctrl: boolean(),
            alt: boolean(),
            shift: boolean()
          }
  end

  defmodule Resize do
    @moduledoc "A terminal resize event."

    defstruct [:width, :height]

    @type t :: %__MODULE__{width: pos_integer(), height: pos_integer()}
  end

  @type t :: Key.t() | Resize.t()
end
