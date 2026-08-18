# Standalone binaries with Burrito

The counter from `examples/counter.exs`, packaged as a single
self-contained executable with [Burrito](https://github.com/burrito-elixir/burrito).
Tuix is pure Elixir — no NIFs, no ports — so cross-compiling with Burrito
requires no native-code toolchain beyond Burrito's own.

## Requirements

- Erlang/OTP 29+ and Elixir 1.20+ (Tuix's usual requirements)
- [Zig](https://ziglang.org/download/) — the exact version Burrito
  requires (Burrito 1.6 requires Zig `0.16.0`; the build fails with a
  clear message if yours doesn't match)
- `xz` (and `7z` only if you target Windows)

## Build

```sh
mix deps.get
MIX_ENV=prod mix release
```

This builds every target listed in `mix.exs` into `burrito_out/`. To
build a single target:

```sh
BURRITO_TARGET=macos_silicon MIX_ENV=prod mix release
```

## Run

```sh
./burrito_out/counter_macos_silicon
```

The first run extracts the payload to a cache directory, so it starts
slightly slower than subsequent runs. To clean up an installed binary's
cache: `./burrito_out/counter_macos_silicon maintenance uninstall`.

## How it works

Two things adapt the counter for a release (see
`lib/counter/application.ex`):

1. Releases boot an OTP application, so the project defines an
   application callback module (`mod: {Counter.Application, []}`) instead
   of a top-level script calling `Tuix.run/2`.
2. `Tuix.run/2` blocks until the app stops, but `Application.start/2`
   must return — so the TUI runs in a `Task`, followed by
   `System.halt(0)` to shut the VM down when the user quits (releases
   boot with `--no-halt`, so the VM would otherwise stay alive after the
   TUI exits).

Notes:

- OTP 29 is required by Tuix at runtime. Burrito downloads a matching
  precompiled ERTS for each target, so your *host* OTP must also be 29+
  (Burrito packages the OTP version you build with).
- Windows targets are untested with Tuix.

## Known upstream issues (Burrito 1.6.0)

As of Burrito 1.6.0 this example does **not** work with the stock Hex
package. Three upstream bugs affect TUI apps; all are reported:

1. [burrito#215](https://github.com/burrito-elixir/burrito/issues/215) -
   Burrito's precompiled ERTS builds lack tty support (raw mode returns
   `{:error, :enotsup}`). Workaround: point `BURRITO_CUSTOM_ERTS` at a
   local OTP root (e.g. your version manager's install directory); this
   example's `mix.exs` picks it up automatically:

   ```sh
   BURRITO_CUSTOM_ERTS="$HOME/.local/share/mise/installs/erlang/29.0.5" \
     MIX_ENV=prod mix release
   ```

2. [burrito#234](https://github.com/burrito-elixir/burrito/issues/234) -
   the wrapper pipes the BEAM's stdout, so the VM never sees a TTY: no
   ANSI detection, no raw mode, and keyboard input is never delivered.
   No workaround short of patching `deps/burrito/src/erlang_launcher.zig`
   to inherit stdout.

3. [burrito#233](https://github.com/burrito-elixir/burrito/issues/233) -
   `-mode embedded` is passed as a single argv string, so the VM boots
   in interactive mode. Harmless for this example (Tuix loads the app
   module explicitly), but worth knowing.

Relatedly, [burrito#229](https://github.com/burrito-elixir/burrito/issues/229)
(the VM halting after boot) is why this example runs the TUI
synchronously inside `Application.start/2` - see
`lib/counter/application.ex`. That pattern works on all Burrito
versions, with or without the upstream fix.
