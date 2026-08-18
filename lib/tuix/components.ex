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
    * `:focus_within_border_color` / `:focus_within_bg` - styles applied
      while a descendant is focused; fall back to the `focus_*` props

  Focus styles also apply while a descendant has focus (e.g. a bordered box
  wrapping a focused input): the runtime sets `focused: true` on the focused
  element's props and `focus_within: true` on its ancestors before painting;
  see `Tuix.Focus`.

  ## Input props

    * `:id` - required; also makes the input focusable by default
    * `:value` - the current value (owned by the app; default `""`)
    * `:placeholder` - text shown while empty and unfocused
    * `:placeholder_color` - color of the placeholder (default `:bright_black`)
    * `:mask` - replaces each grapheme on display, e.g. `"•"` for passwords
    * `:width` / `:fg` / `:bg` / `:attrs` and the focus props above

  ## Select props

    * `:id` - required; also makes the select focusable by default
    * `:options` - list of `{label, value}` tuples, or bare strings (which
      are their own value)
    * `:value` - the currently selected value (owned by the app)
    * `:marker` - prefix drawn on the selected row (default `"❯ "`); other
      rows are padded to match
    * `:selected_fg` - foreground of the selected row (default: inherits `:fg`)
    * `:selected_attrs` - attrs of the selected row (default `[:bold]`)
    * `:fg` / `:bg` / `:attrs` and the focus props above

  ## ScrollBox props

    * `:id` - required; also makes the scroll box focusable by default
    * `:snap` - `:bottom` starts the box scrolled to the bottom and keeps it
      pinned there while content grows (until the user scrolls up)
    * all box props above (`:border`, `:padding`, `:title`, sizing, ...),
      except `:flex_direction` - content always flows in a column
    * the focus props above

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
  Builds a scroll box: a focusable container whose children are laid out at
  their full height and scrolled vertically within the box.

  Scroll boxes require an `:id` and join the Tab focus order automatically
  (`focusable: true`). While focused, `:up` / `:down` scroll by a row,
  `:page_up` / `:page_down` by a viewport, and `:home` / `:end` jump to the
  boundaries — clamped, with boundary presses consumed. The offset is
  framework-managed (like an input's cursor): no event reaches the app and
  there is nothing to assign back.

      scroll_box id: :log, border: :single, height: 10 do
        for line <- assigns.lines, do: text(line)
      end

  When the content overflows, a proportional scrollbar is drawn in the
  rightmost column — over the border when the box has one, otherwise in a
  reserved column. With `snap: :bottom` the box starts scrolled to the
  bottom and stays pinned there as content grows (chat logs, tails);
  scrolling up detaches, and returning to the bottom re-attaches.

  Content always flows in a column, and `:flex_grow` on children has no
  effect (the content area is as tall as the content). Accepts props and
  children as a `do` block or a list, like `box/2`. See the module docs
  above for the accepted props.
  """
  defmacro scroll_box(props, block_or_children \\ [])

  defmacro scroll_box(props, do: block) do
    children = unwrap_block(block)

    quote do
      Tuix.Components.build_scroll_box(unquote(props), [unquote_splicing(children)])
    end
  end

  defmacro scroll_box(props, children) do
    quote do
      Tuix.Components.build_scroll_box(unquote(props), List.wrap(unquote(children)))
    end
  end

  @doc false
  @spec build_scroll_box(keyword(), list()) :: Element.t()
  def build_scroll_box(props, children) when is_list(props) do
    unless Keyword.has_key?(props, :id) do
      raise ArgumentError, "scroll_box/2 requires an :id prop"
    end

    Element.new(:scroll_box, Keyword.put_new(props, :focusable, true), children)
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
  Builds a vertical list-picker element.

  Selects join the Tab focus order automatically (`focusable: true`) and
  require an `:id`. They are controlled: the selection follows the
  highlight, so `:up` / `:down` / `:home` / `:end` emit
  `%Tuix.Event.Select{}` with the new value immediately, and the app
  assigns it back into state:

      select(id: :plan, options: [{"Basic", :basic}, {"Pro", :pro}], value: assigns.plan)

      def handle_event(%Tuix.Event.Select{id: :plan, value: value}, app),
        do: {:noreply, assign(app, plan: value)}

  Navigation is clamped (no wrap-around). `:enter`, `:space`, and
  everything else fall through to the app with `target` set — so
  commit-on-Enter flows keep a draft value in assigns and match
  `%Tuix.Event.Key{key: :enter, target: :plan}`. When the select is
  shorter than its option list, it scrolls to keep the selection visible.
  See the module docs above for the accepted props.
  """
  @spec select(keyword()) :: Element.t()
  def select(props) when is_list(props) do
    unless Keyword.has_key?(props, :id) do
      raise ArgumentError, "select/1 requires an :id prop"
    end

    Element.new(:select, Keyword.put_new(props, :focusable, true))
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
