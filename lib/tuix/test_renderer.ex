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
  alias Tuix.Renderer

  @doc """
  Renders an element tree or app module at the given size, returning the
  `Tuix.Buffer` for structured assertions (cell styles, etc).
  """
  @spec render(Element.t() | module(), pos_integer(), pos_integer(), keyword()) :: Buffer.t()
  def render(element_or_module, width, height, opts \\ [])

  def render(%Element{} = element, width, height, _opts) do
    Renderer.render(element, width, height)
  end

  def render(module, width, height, opts) when is_atom(module) do
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
    |> Renderer.render(width, height)
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
