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
