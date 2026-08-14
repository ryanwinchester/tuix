defmodule Tuix.Input do
  @moduledoc """
  Reads raw bytes from stdin in a blocking loop and sends parsed key events
  to the runtime as `{:tuix_input, %Tuix.Event.Key{}}` messages.
  """

  alias Tuix.Input.Parser

  @doc """
  Starts a linked reader process that delivers events to `parent`.
  """
  def start_link(parent) do
    Task.start_link(fn -> loop(parent, "") end)
  end

  defp loop(parent, pending) do
    case :io.get_chars(:standard_io, "", 1024) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      data when is_binary(data) ->
        {events, rest} = Parser.parse(pending <> data)
        Enum.each(events, &send(parent, {:tuix_input, &1}))
        loop(parent, rest)

      data when is_list(data) ->
        {events, rest} = Parser.parse(pending <> IO.chardata_to_string(data))
        Enum.each(events, &send(parent, {:tuix_input, &1}))
        loop(parent, rest)
    end
  end
end
