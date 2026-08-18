defmodule Tuix.TestRenderer do
  @moduledoc """
  Renders element trees (or whole apps) to buffers and text snapshots without
  touching the terminal. The Tuix analog of OpenTUI's `createTestRenderer`.

  ## Example

      element =
        box border: :single, width: 12, height: 3 do
          text("hi")
        end

      assert Tuix.TestRenderer.render_to_text(element, 20, 5) == \"\"\"
             ┌──────────┐
             │hi        │
             └──────────┘
             \"\"\" |> String.trim_trailing()

  """

  alias Tuix.App
  alias Tuix.Buffer
  alias Tuix.Element
  alias Tuix.Focus
  alias Tuix.Renderer

  @doc """
  Renders an element tree or app module at the given size, returning the
  `Tuix.Buffer` for structured assertions (cell styles, etc).

  The `:focus` option marks the element with that id as focused (applying
  focus styles), like the runtime does for the focused element; `:cursor`
  places a focused input's cursor at that grapheme offset (default: end of
  value); `:scroll_offset` scrolls a focused scroll box to that row (or
  `:bottom`). All other options are passed to the app's `mount/2` (module
  apps only).
  """
  @spec render(Element.t() | module(), pos_integer(), pos_integer(), keyword()) :: Buffer.t()
  def render(element_or_module, width, height, opts \\ [])

  def render(%Element{} = element, width, height, opts) do
    element
    |> mark(opts)
    |> Renderer.render(width, height)
  end

  def render(module, width, height, opts) when is_atom(module) do
    {mark_opts, opts} = Keyword.split(opts, [:focus, :cursor, :scroll_offset])
    app = %App{module: module}

    app =
      if function_exported?(module, :mount, 2) do
        {:ok, app} = module.mount(opts, app)
        app
      else
        app
      end

    app.assigns
    |> module.render()
    |> mark(mark_opts)
    |> Renderer.render(width, height)
  end

  defp mark(element, opts) do
    case Keyword.get(opts, :focus) do
      nil -> element
      id -> Focus.mark(element, id, opts |> Keyword.take([:cursor, :scroll_offset]) |> Map.new())
    end
  end

  @doc """
  Renders to a plain-text snapshot: one string per row joined with newlines,
  trailing whitespace trimmed.
  """
  @spec render_to_text(Element.t() | module(), pos_integer(), pos_integer(), keyword()) ::
          String.t()
  def render_to_text(element_or_module, width, height, opts \\ []) do
    element_or_module
    |> render(width, height, opts)
    |> Buffer.to_text()
  end
end
