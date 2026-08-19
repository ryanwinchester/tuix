# Packaging

`mix run my_app.exs` is fine for development, but to ship a Tuix app to
users you'll want either a plain OTP release (a self-contained directory
with the VM included) or a single-file executable built with
[Burrito](https://github.com/burrito-elixir/burrito).

Tuix is pure Elixir — no NIFs, no ports, no external binaries — so there
is no native-code toolchain to worry about when packaging or
cross-compiling.

A complete working Burrito project lives in
[`examples/burrito`](https://github.com/ryanwinchester/tuix/tree/main/examples/burrito).

## The application entry point

Scripts call `Tuix.run/2` at the top level, but releases boot an OTP
application, so the app needs a Mix project with an application callback
module:

```elixir
# mix.exs
def application do
  [
    extra_applications: [:logger],
    mod: {MyApp.Application, []}
  ]
end
```

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Tuix.run(MyApp)
    System.halt(0)
  end
end
```

Two things about this shape are deliberate:

  * **`Tuix.run/2` is called synchronously inside `start/2`.** Releases
    and Burrito binaries boot the VM with Elixir's CLI
    (`-s elixir start_cli`), which halts the VM as soon as it finishes
    processing arguments. `mix release`'s `bin/my_app start` passes
    `--no-halt` to prevent that; Burrito 1.6.0 does not
    ([burrito#229](https://github.com/burrito-elixir/burrito/issues/229)),
    and setting `System.no_halt(true)` during boot doesn't survive — the
    CLI overwrites it from its own argv. Blocking inside `start/2` keeps
    the boot phase open until the TUI exits, so the CLI never gets a
    chance to halt a running app. The pattern works identically under
    plain releases.

  * **`System.halt(0)` shuts the VM down** when the user quits.
    Without it the VM would stay alive with a blank screen (releases run
    with `--no-halt`).

## Plain releases

Nothing else is needed. Build and run:

```sh
MIX_ENV=prod mix release
_build/prod/rel/my_app/bin/my_app start
```

The release directory is self-contained (ERTS included) and can be
copied to any machine with the same OS, architecture, and system
libraries. Since Tuix requires OTP 29+ at runtime, the machine you build
on must run OTP 29+ too — the release ships the ERTS you built with.

## Single binaries with Burrito

Burrito wraps a release into one self-extracting executable per target —
the "download a binary and run it" distribution model of Go and Rust
tools.

### Requirements

  * [Zig](https://ziglang.org/download/) — the exact version the Burrito
    release requires (Burrito 1.6 requires Zig `0.16.0`; the build fails
    with a clear message on mismatch)
  * `xz`, and `7z` only if you target Windows
  * A host OTP matching your app's requirements (29+ for Tuix) — Burrito
    packages an ERTS of the same version you build with

### Setup

```elixir
# mix.exs
def project do
  [
    # ...
    releases: releases()
  ]
end

defp deps do
  [
    {:tuix, "~> 0.1"},
    {:burrito, "~> 1.6", runtime: false}
  ]
end

defp releases do
  [
    my_app: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          macos_silicon: [os: :darwin, cpu: :aarch64],
          macos: [os: :darwin, cpu: :x86_64],
          linux: [os: :linux, cpu: :x86_64],
          linux_arm: [os: :linux, cpu: :aarch64]
        ]
      ]
    ]
  ]
end
```

### Build and run

```sh
MIX_ENV=prod mix release                          # all targets
BURRITO_TARGET=macos_silicon MIX_ENV=prod mix release  # one target

./burrito_out/my_app_macos_silicon
```

The first run extracts the payload to a per-user cache, so it starts
slightly slower than subsequent runs. Burrito reuses the cache as long
as the app version doesn't change — bump `version` in `mix.exs` for
every shipped build, or run
`./my_app_macos_silicon maintenance uninstall` to clear a stale install
during development.

### Known upstream issues (Burrito 1.6.0)

As of Burrito 1.6.0, TUI apps do not work out of the box in Burrito
binaries. Three upstream bugs are involved; all are reported, and
[tuix#12](https://github.com/ryanwinchester/tuix/issues/12) tracks
their status:

1. [burrito#215](https://github.com/burrito-elixir/burrito/issues/215) —
   Burrito's precompiled ERTS builds lack tty support: raw mode returns
   `{:error, :enotsup}` and `Tuix.run/2` cannot take over the terminal.
   **Workaround:** pass `custom_erts` in the target definition, pointing
   at a local OTP install root (the directory containing `erts-*` and
   `lib`), e.g.:

   ```elixir
   macos_silicon: [
     os: :darwin,
     cpu: :aarch64,
     custom_erts: "/path/to/otp/29.0.5"
   ]
   ```

2. [burrito#234](https://github.com/burrito-elixir/burrito/issues/234) —
   the launcher pipes the BEAM's stdout through the wrapper, so the VM
   never sees a TTY: ANSI detection fails, raw mode is unsupported, and
   keyboard input is never delivered. No workaround short of patching
   Burrito; wait for the upstream fix before shipping.

3. [burrito#233](https://github.com/burrito-elixir/burrito/issues/233) —
   `-mode embedded` is passed as a single argv string, so the VM boots
   in interactive mode rather than embedded mode. Not fatal for Tuix
   apps, but embedded-mode guarantees are silently lost.

The [`examples/burrito`](https://github.com/ryanwinchester/tuix/tree/main/examples/burrito)
project tracks these and documents the exact state of what works.

### What about Burrito 1.5?

Burrito 1.5 predates both 1.6 regressions: its launcher never actually
ran Elixir's CLI (so the VM was not halted, [burrito#229](https://github.com/burrito-elixir/burrito/issues/229))
and it did not pipe the BEAM's stdout ([burrito#234](https://github.com/burrito-elixir/burrito/issues/234)).
[Expert](https://github.com/expert-lsp/expert/pull/844) (the Elixir
LSP) downgraded to 1.5 over #229 for exactly this reason. With the
`custom_erts` workaround for
[burrito#215](https://github.com/burrito-elixir/burrito/issues/215)
(which affects all versions), 1.5 is plausibly the most workable
release for TUI apps today.

The catch: **Burrito 1.5 requires Zig 0.15.2, which cannot link
against the macOS 26 SDK** — builds fail with undefined-symbol errors
(`__availability_version_check`, `_sysctlbyname`, ...) for *any*
target, including cross-compiles to Linux. Verified on macOS 26/arm64.
If your build host is Linux or an older macOS, 1.5 + `custom_erts` is
worth trying; on current macOS only 1.6 builds at all.

## Windows

Untested. Tuix relies on `SIGWINCH` for resize events where available
(falling back to polling) and on OTP 29 raw-mode support; Burrito's
Windows wrapper behaves differently from the Unix one. Treat Windows
targets as experimental.
