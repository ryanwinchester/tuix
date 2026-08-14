defmodule Tuix do
  @moduledoc """
  Tuix is a terminal UI framework for Elixir, inspired by
  [OpenTUI](https://opentui.com).

  Build declarative, component-based TUIs with a LiveView-style programming
  model: state lives in assigns, events arrive in callbacks, and `render/1`
  describes the UI as a tree of boxes and text. Tuix lays the tree out with
  a flexbox-subset engine and writes only the terminal cells that changed.

  See `Tuix.App` for the application behaviour and `Tuix.Components` for the
  element builders.

  ## Quick start

      defmodule Hello do
        use Tuix.App

        @impl true
        def render(_assigns) do
          box border: :rounded, padding: 1 do
            text("Hello, Tuix!", fg: "#00FF00")
          end
        end
      end

      Tuix.run(Hello)

  """

  @doc """
  Runs a `Tuix.App`, blocking the calling process until the app stops.

  Takes over the terminal (raw mode + alternate screen) and restores it on
  exit — including crashes.

  ## Options

    * `:exit_on_ctrl_c` - stop the app when Ctrl+C is pressed (default `true`)

  All other options are passed through to the app's `c:Tuix.App.mount/2`.
  """
  @spec run(module(), keyword()) :: :ok
  def run(module, opts \\ []) when is_atom(module) do
    ensure_supported_terminal!()

    children = [
      Tuix.Terminal,
      {Tuix.Runtime, Keyword.put(opts, :module, module)}
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_all)

    runtime = Process.whereis(Tuix.Runtime)
    ref = Process.monitor(runtime)

    receive do
      {:DOWN, ^ref, :process, ^runtime, _reason} ->
        Supervisor.stop(supervisor)
        :ok
    end
  end

  defp ensure_supported_terminal! do
    otp_release = String.to_integer(System.otp_release())

    if otp_release < 29 do
      raise RuntimeError,
            "Tuix requires Erlang/OTP 29 or later (found OTP #{otp_release}). " <>
              "OTP 29 provides :io_ansi and SIGWINCH handling."
    end

    case ansi_enabled?() do
      false ->
        raise RuntimeError,
              "the terminal does not support ANSI escape sequences " <>
                "(TERM=#{System.get_env("TERM") || "unset"})"

      _true_or_unknown ->
        :ok
    end
  end

  # :io_ansi.enabled/0 raises when stdio is not a tty; in that case raw mode
  # setup will surface its own failure, so treat it as unknown and proceed.
  defp ansi_enabled? do
    :io_ansi.enabled()
  catch
    _, _ -> :unknown
  end
end
