defmodule Tuix.Focus do
  @moduledoc """
  Keyboard focus: which element receives targeted input.

  Elements opt into the focus ring with `focusable: true` and a stable `:id`
  prop. The runtime collects the focus order from each rendered tree
  (depth-first document order), moves focus on Tab / Shift+Tab, and marks the
  focused element with `focused: true` — and its ancestors with
  `focus_within: true` — before painting so focus styles
  (`:focus_border_color`, `:focus_bg`, and the `focus_within_*` variants)
  apply.

  These are pure functions over element trees; the runtime owns the state
  (in `Tuix.App` `private`, exposed through `Tuix.App.focused/1`,
  `Tuix.App.focus/2`, and `Tuix.App.blur/1`).
  """

  alias Tuix.Element

  @doc """
  Collects the focus order: ids of focusable elements in depth-first
  document order.

  Raises `ArgumentError` if a focusable element has no `:id` prop.
  """
  @spec order(Element.t()) :: [term()]
  def order(%Element{} = tree) do
    tree |> collect([]) |> Enum.reverse()
  end

  defp collect(%Element{props: props} = element, acc) do
    acc =
      cond do
        not Map.get(props, :focusable, false) ->
          acc

        not Map.has_key?(props, :id) ->
          raise ArgumentError,
                "focusable element requires an :id prop, got: #{inspect(element.tag)} " <>
                  "with props #{inspect(props)}"

        true ->
          [props.id | acc]
      end

    Enum.reduce(element.children, acc, &collect/2)
  end

  @doc """
  The id after `current` in the focus order, wrapping around.

  With `current` as `nil` (or an id no longer in the order), returns the
  first id. Returns `nil` for an empty order.
  """
  @spec next([term()], term() | nil) :: term() | nil
  def next([], _current), do: nil

  def next(order, current) do
    case index_of(order, current) do
      nil -> List.first(order)
      index -> Enum.at(order, rem(index + 1, length(order)))
    end
  end

  @doc """
  The id before `current` in the focus order, wrapping around.

  With `current` as `nil` (or an id no longer in the order), returns the
  last id. Returns `nil` for an empty order.
  """
  @spec prev([term()], term() | nil) :: term() | nil
  def prev([], _current), do: nil

  def prev(order, current) do
    case index_of(order, current) do
      nil -> List.last(order)
      index -> Enum.at(order, rem(index - 1 + length(order), length(order)))
    end
  end

  defp index_of(order, current), do: Enum.find_index(order, &(&1 == current))

  @doc """
  The id of the first focusable element with `autofocus: true` in document
  order, or `nil`. Applied by the runtime on the first frame when nothing
  is focused.
  """
  @spec autofocus(Element.t()) :: term() | nil
  def autofocus(%Element{props: props} = element) do
    if Map.get(props, :focusable, false) and Map.get(props, :autofocus, false) do
      Map.get(props, :id)
    else
      Enum.find_value(element.children, &autofocus/1)
    end
  end

  @doc """
  Marks the focusable element with the given id by setting `focused: true`
  in its props, merging in any `extra_props` (e.g. the runtime injects the
  cursor offset for focused inputs). Every ancestor on the path to the
  focused element gets `focus_within: true` (CSS `:focus-within`), so
  wrapper boxes can style themselves while a descendant is focused. With
  `id` as `nil`, returns the tree unchanged.
  """
  @spec mark(Element.t(), term() | nil, map()) :: Element.t()
  def mark(tree, id, extra_props \\ %{})
  def mark(%Element{} = tree, nil, _extra_props), do: tree

  def mark(%Element{} = tree, id, extra_props) do
    {marked, _found} = do_mark(tree, id, extra_props)
    marked
  end

  defp do_mark(%Element{props: props} = element, id, extra_props) do
    if Map.get(props, :focusable, false) and Map.get(props, :id) == id do
      {%{element | props: props |> Map.put(:focused, true) |> Map.merge(extra_props)}, true}
    else
      {children, found} =
        Enum.map_reduce(element.children, false, fn child, found ->
          {child, child_found} = do_mark(child, id, extra_props)
          {child, found or child_found}
        end)

      element = %{element | children: children}

      if found do
        {%{element | props: Map.put(element.props, :focus_within, true)}, true}
      else
        {element, false}
      end
    end
  end

  @doc """
  Finds the focusable element with the given id, or `nil`.
  """
  @spec find(Element.t(), term() | nil) :: Element.t() | nil
  def find(%Element{}, nil), do: nil

  def find(%Element{props: props} = element, id) do
    if Map.get(props, :focusable, false) and Map.get(props, :id) == id do
      element
    else
      Enum.find_value(element.children, &find(&1, id))
    end
  end
end
