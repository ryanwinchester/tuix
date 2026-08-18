defmodule Tuix.Components do
  @moduledoc """
  Functions and macros for building the element tree returned by
  `c:Tuix.App.render/1`.

  ## Box props

    * `:width` / `:height` - integer cells, `{:percent, n}`, or a `"50%"` string
    * `:flex_direction` - `:column` (default) or `:row`
    * `:flex_grow` - share of leftover space along the parent's main axis
    * `:gap` - cells between children
    * `:padding` - cells inside the border on all sides
    * `:border` - `:none` (default), `:single`, `:rounded`, `:double`, or `true`
      (alias for `:single`)
    * `:border_color` - color of the border (see `Tuix.Color`)
    * `:title` - text drawn into the top border
    * `:bg` - background fill color

  ## Focus props (boxes)

    * `:id` - stable identity for the element (any term, unique per tree)
    * `:focusable` - includes the box in the Tab / Shift+Tab focus order;
      requires `:id`
    * `:autofocus` - focuses this box on the first frame when nothing is
      focused
    * `:focus_border_color` - border color while focused (overrides
      `:border_color`)
    * `:focus_bg` - background fill while focused (overrides `:bg`)

  The runtime sets `focused: true` on the focused element's props before
  painting; see `Tuix.Focus`.

  ## Input props

    * `:id` - required; also makes the input focusable by default
    * `:value` - the current value (owned by the app; default `""`)
    * `:placeholder` - text shown while empty and unfocused
    * `:placeholder_color` - color of the placeholder (default `:bright_black`)
    * `:mask` - replaces each grapheme on display, e.g. `"•"` for passwords
    * `:width` / `:fg` / `:bg` / `:attrs` and the focus props above

  ## Text props

    * `:fg` / `:bg` - colors (see `Tuix.Color`)
    * `:attrs` - list of `:bold`, `:dim`, `:italic`, `:underline`, `:blink`,
      `:reverse`, `:strikethrough`

  ## Examples

      box border: :rounded, padding: 1, gap: 1 do
        text("Welcome", fg: :yellow)
        text("Press q to quit")
      end

  """

  alias Tuix.Element

  @doc """
  Builds a box element.

  Accepts props and children either as a `do` block or as a list:

      box(border: :single) # empty box
      box [border: :single] do
        text("hi")
      end
      box([border: :single], [text("hi")])

  """
  defmacro box(props \\ [], block_or_children \\ [])

  defmacro box(props, do: block) do
    children = unwrap_block(block)

    quote do
      Tuix.Element.new(:box, unquote(props), [unquote_splicing(children)])
    end
  end

  defmacro box([do: block], _ignored) do
    children = unwrap_block(block)

    quote do
      Tuix.Element.new(:box, [], [unquote_splicing(children)])
    end
  end

  defmacro box(props, children) do
    quote do
      Tuix.Element.new(:box, unquote(props), List.wrap(unquote(children)))
    end
  end

  @doc """
  Builds a single-line text input element.

  Inputs join the Tab focus order automatically (`focusable: true`) and
  require an `:id`. The value is controlled by the app: handle
  `%Tuix.Event.Input{}` and assign the new value back into state, LiveView
  form style — otherwise the input appears frozen.

      input(id: :email, value: assigns.email, placeholder: "you@example.com")

      def handle_event(%Tuix.Event.Input{id: :email, value: value}, app),
        do: {:noreply, assign(app, email: value)}

  While focused, printable keys and `:space`, `:backspace`, `:delete`,
  `:left` / `:right` / `:home` / `:end` edit the value; everything else
  (`:enter`, `:escape`, ctrl combos, Tab traversal) falls through to the
  app with `target` set. See `Tuix.Components.Input` for the editing core
  and the module docs above for the accepted props.
  """
  @spec input(keyword()) :: Element.t()
  def input(props) when is_list(props) do
    unless Keyword.has_key?(props, :id) do
      raise ArgumentError, "input/1 requires an :id prop"
    end

    Element.new(:input, Keyword.put_new(props, :focusable, true))
  end

  @doc """
  Builds a text element.

      text("Hello")
      text("Hello", fg: "#00FF00", attrs: [:bold])

  Multi-line content (embedded newlines) renders one line per row.
  """
  @spec text(String.t(), keyword()) :: Element.t()
  def text(content, props \\ []) when is_binary(content) do
    Element.new(:text, Keyword.put(props, :content, content))
  end

  defp unwrap_block({:__block__, _meta, exprs}), do: exprs
  defp unwrap_block(nil), do: []
  defp unwrap_block(expr), do: [expr]
end
