defmodule Tuix.Element do
  @moduledoc """
  A node in the declarative UI tree.

  Elements are plain data — the Elixir analog of OpenTUI's construct VNodes.
  Build them with the functions in `Tuix.Components` rather than directly.
  """

  defstruct tag: :box, props: %{}, children: []

  @type t :: %__MODULE__{tag: atom(), props: map(), children: [t()]}

  @doc """
  Creates an element. `props` may be a keyword list or map. Children are
  flattened and `nil`s removed, so conditional children (`if ... `) and
  comprehensions compose naturally.
  """
  @spec new(atom(), keyword() | map(), list()) :: t()
  def new(tag, props \\ [], children \\ []) do
    %__MODULE__{
      tag: tag,
      props: Map.new(props),
      children: children |> List.flatten() |> Enum.reject(&is_nil/1)
    }
  end
end
