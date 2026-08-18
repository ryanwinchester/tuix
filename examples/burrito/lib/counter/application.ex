defmodule Counter.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Run the TUI synchronously inside start/2 and halt when it exits.
    #
    # This is deliberate: Burrito's launcher boots the VM with
    # `elixir start_cli` and no `--no-halt`, so the Elixir CLI halts the
    # VM as soon as argv processing finishes. Setting System.no_halt/1
    # here does not help -- Kernel.CLI overwrites it from its own argv.
    # Blocking in start/2 keeps the boot phase open until the TUI exits,
    # so start_cli never gets a chance to halt a running app.
    #
    # (This also works under a plain `bin/counter start`, which passes
    # `--no-halt` -- the halt below is what shuts the VM down.)
    Tuix.run(Counter)
    System.halt(0)
  end
end
