defmodule Tuix.Input.Parser do
  @moduledoc """
  Incremental parser turning raw terminal input bytes into `Tuix.Event.Key`
  and `Tuix.Event.Mouse` structs.

  `parse/1` returns `{events, rest}` where `rest` is an incomplete trailing
  escape sequence to be prepended to the next chunk of input.

  Mouse reports are decoded from SGR encoding (`ESC [ < Cb ; Cx ; Cy M|m`,
  mode 1006) with an X10 fallback (`ESC [ M` followed by three raw bytes)
  for terminals that support button tracking but not SGR encoding.
  """

  import Bitwise

  alias Tuix.Event.Key
  alias Tuix.Event.Mouse

  @csi_final_range 0x40..0x7E

  @doc """
  Parses a binary of input bytes into key events.

  ## Examples

      iex> Tuix.Input.Parser.parse("a")
      {[%Tuix.Event.Key{key: "a"}], ""}

      iex> Tuix.Input.Parser.parse("\\e[A")
      {[%Tuix.Event.Key{key: :up}], ""}

  """
  @spec parse(binary()) :: {[Key.t()], binary()}
  def parse(data) when is_binary(data) do
    do_parse(data, [])
  end

  defp do_parse(<<>>, events), do: {Enum.reverse(events), ""}

  # X10 mouse reports: ESC [ M cb cx cy (all offset by 32). Terminals fall
  # back to this encoding when they support button tracking (1002) but not
  # SGR encoding (1006). Must precede the generic CSI clause: M is a CSI
  # final byte, and the three payload bytes would otherwise be misparsed
  # as keys.
  defp do_parse(<<"\e[M", cb, cx, cy, rest::binary>>, events) do
    do_parse(rest, prepend_event(x10_mouse_event(cb - 32, cx - 33, cy - 33), events))
  end

  defp do_parse(<<"\e[M", rest::binary>> = all, events) when byte_size(rest) < 3 do
    {Enum.reverse(events), all}
  end

  # CSI sequences: ESC [ params final
  defp do_parse(<<"\e[", rest::binary>> = all, events) do
    case take_csi(rest, <<>>) do
      {:ok, params, final, rest} ->
        do_parse(rest, prepend_event(csi_event(params, final), events))

      :incomplete ->
        {Enum.reverse(events), all}
    end
  end

  # SS3 sequences: ESC O final (arrows/home/end in application mode)
  defp do_parse(<<"\eO", final, rest::binary>>, events) do
    do_parse(rest, prepend_event(ss3_event(final), events))
  end

  defp do_parse(<<"\eO">> = all, events), do: {Enum.reverse(events), all}

  # Bare escape at end of chunk: treat as the escape key. Terminals deliver
  # full escape sequences in a single read in practice.
  defp do_parse(<<"\e">>, events) do
    {Enum.reverse([%Key{key: :escape} | events]), ""}
  end

  # Alt+key: ESC followed by a regular byte
  defp do_parse(<<"\e", rest::binary>>, events) do
    {inner_events, remaining} = do_parse_one(rest)

    case inner_events do
      [%Key{} = key] -> do_parse(remaining, [%{key | alt: true} | events])
      [] -> do_parse(remaining, events)
    end
  end

  defp do_parse(data, events) do
    {new_events, rest} = do_parse_one(data)
    do_parse(rest, Enum.reverse(new_events) ++ events)
  end

  # Parses exactly one non-escape token from the front of the binary.
  defp do_parse_one(<<"\r", rest::binary>>), do: {[%Key{key: :enter}], rest}
  defp do_parse_one(<<"\n", rest::binary>>), do: {[%Key{key: :enter}], rest}
  defp do_parse_one(<<"\t", rest::binary>>), do: {[%Key{key: :tab}], rest}
  defp do_parse_one(<<0x7F, rest::binary>>), do: {[%Key{key: :backspace}], rest}
  defp do_parse_one(<<" ", rest::binary>>), do: {[%Key{key: :space}], rest}
  defp do_parse_one(<<0, rest::binary>>), do: {[%Key{key: :space, ctrl: true}], rest}

  defp do_parse_one(<<c, rest::binary>>) when c in 1..26 do
    {[%Key{key: <<c + ?a - 1>>, ctrl: true}], rest}
  end

  # Other C0 control bytes we don't map: skip.
  defp do_parse_one(<<c, rest::binary>>) when c < 0x20 do
    {[], rest}
  end

  defp do_parse_one(data) do
    case String.next_grapheme(data) do
      {grapheme, rest} -> {[%Key{key: grapheme}], rest}
      nil -> {[], ""}
    end
  end

  ## CSI handling

  defp take_csi(<<>>, _acc), do: :incomplete

  defp take_csi(<<c, rest::binary>>, acc) when c in @csi_final_range do
    {:ok, acc, c, rest}
  end

  defp take_csi(<<c, rest::binary>>, acc), do: take_csi(rest, <<acc::binary, c>>)

  # SGR mouse reports: ESC [ < Cb ; Cx ; Cy M|m (press/drag/wheel vs release)
  defp csi_event("<" <> params, final) when final in [?M, ?m] do
    sgr_mouse_event(params, final)
  end

  defp csi_event(params, final) do
    {key, modifier} = decode_csi(params, final)
    apply_modifier(key, modifier)
  end

  defp decode_csi(params, final) when final in ~c"ABCDHF" do
    key =
      case final do
        ?A -> :up
        ?B -> :down
        ?C -> :right
        ?D -> :left
        ?H -> :home
        ?F -> :end
      end

    {key, modifier_from_params(params)}
  end

  defp decode_csi(_params, ?Z), do: {:backtab, 0}

  defp decode_csi(params, ?~) do
    [code | mods] = String.split(params, ";")

    key =
      case code do
        "1" -> :home
        "2" -> :insert
        "3" -> :delete
        "4" -> :end
        "5" -> :page_up
        "6" -> :page_down
        "7" -> :home
        "8" -> :end
        _ -> nil
      end

    {key, decode_modifier(mods)}
  end

  defp decode_csi(_params, _final), do: {nil, 0}

  defp modifier_from_params(params) do
    decode_modifier(tl_or_empty(String.split(params, ";")))
  end

  defp tl_or_empty([_ | tail]), do: tail
  defp tl_or_empty([]), do: []

  defp decode_modifier([mod | _]) do
    case Integer.parse(mod) do
      {n, ""} when n >= 1 -> n - 1
      _ -> 0
    end
  end

  defp decode_modifier(_), do: 0

  defp apply_modifier(nil, _modifier), do: nil

  defp apply_modifier(key, modifier) do
    %Key{
      key: key,
      shift: (modifier &&& 1) == 1,
      alt: (modifier &&& 2) == 2,
      ctrl: (modifier &&& 4) == 4
    }
  end

  ## Mouse handling

  # Cb encodes the button in the low 2 bits (3 = none), modifiers in bits
  # 4/8/16 (shift/alt/ctrl), motion in bit 32, and wheel in bit 64. SGR
  # coordinates are 1-based; X10 payload bytes are offset by 32.

  defp sgr_mouse_event(params, final) do
    with [cb, cx, cy] <- String.split(params, ";"),
         {cb, ""} when cb >= 0 <- Integer.parse(cb),
         {cx, ""} when cx >= 1 <- Integer.parse(cx),
         {cy, ""} when cy >= 1 <- Integer.parse(cy) do
      mouse_event(cb, cx - 1, cy - 1, final == ?m)
    else
      _ -> nil
    end
  end

  # X10 has no distinct release final: low bits 3 signal the release
  # (without reporting which button went up).
  defp x10_mouse_event(cb, x, y) when cb >= 0 and x >= 0 and y >= 0 do
    mouse_event(cb, x, y, (cb &&& 3) == 3)
  end

  defp x10_mouse_event(_cb, _x, _y), do: nil

  defp mouse_event(cb, x, y, release?) do
    {kind, button} = decode_mouse_button(cb, release?)

    %Mouse{
      kind: kind,
      button: button,
      x: x,
      y: y,
      shift: (cb &&& 4) == 4,
      alt: (cb &&& 8) == 8,
      ctrl: (cb &&& 16) == 16
    }
  end

  defp decode_mouse_button(cb, release?) do
    button =
      case cb &&& 3 do
        0 -> :left
        1 -> :middle
        2 -> :right
        3 -> nil
      end

    cond do
      (cb &&& 64) == 64 -> {if((cb &&& 1) == 1, do: :scroll_down, else: :scroll_up), nil}
      release? -> {:release, button}
      (cb &&& 32) == 32 -> {:drag, button}
      true -> {:press, button}
    end
  end

  defp ss3_event(final) do
    case final do
      ?A -> %Key{key: :up}
      ?B -> %Key{key: :down}
      ?C -> %Key{key: :right}
      ?D -> %Key{key: :left}
      ?H -> %Key{key: :home}
      ?F -> %Key{key: :end}
      _ -> nil
    end
  end

  defp prepend_event(nil, events), do: events
  defp prepend_event(event, events), do: [event | events]
end
