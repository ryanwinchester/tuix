# Tuix

A terminal UI framework for Elixir, inspired by [OpenTUI](https://opentui.com).

Build declarative, component-based TUIs with a LiveView-style programming
model: state lives in assigns, events arrive in callbacks, and `render/1`
describes the UI as a tree of boxes and text. Tuix resolves the tree with a
flexbox-subset layout engine and writes only the terminal cells that changed.

```elixir
defmodule Counter do
  use Tuix.App

  @impl true
  def mount(_opts, app) do
    {:ok, assign(app, count: 0)}
  end

  @impl true
  def handle_event(%Tuix.Event.Key{key: "+"}, app) do
    {:noreply, update(app, :count, &(&1 + 1))}
  end

  def handle_event(%Tuix.Event.Key{key: "q"}, app) do
    {:stop, :normal, app}
  end

  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box border: :rounded, title: "Counter", padding: 1, gap: 1 do
      text("Count: #{assigns.count}", fg: "#00FF00", attrs: [:bold])
      text("Press + to increment, q to quit", fg: :bright_black)
    end
  end
end

Tuix.run(Counter)
```

Try it: `mix run examples/counter.exs`

## Features

- **LiveView-style apps** - `mount/2`, `handle_event/2`, `handle_info/2`, and
  a pure `render/1` over assigns. Any Elixir message (timers, `Task` results,
  PubSub broadcasts) can drive the UI through `handle_info/2`.
- **Declarative components** - `box` and `text` are plain data constructors;
  conditionals and comprehensions compose naturally inside `do` blocks.
- **Flexbox-subset layout** - `flex_direction`, `flex_grow`, `gap`,
  `padding`, borders, fixed and percentage sizes.
- **Diffed rendering** - frames are cell buffers; unchanged rows are skipped
  with a single term comparison and only changed cells are written, as
  position-addressed ANSI runs.
- **Unicode-aware** - grapheme-based cells with correct handling of
  wide characters (CJK, emoji), with an ASCII fast path.
- **Pure Elixir** - no NIFs, no ports, no external binaries. Raw terminal
  mode comes from OTP itself.
- **Testable without a terminal** - `Tuix.TestRenderer` renders any app or
  element tree to a text snapshot or inspectable cell buffer.

## Requirements

- Elixir 1.15+
- Erlang/OTP 26+ (for raw terminal mode via `:shell.start_interactive/1`)

## Installation

Add `tuix` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tuix, "~> 0.1.0"}
  ]
end
```

## Core concepts

### Apps

A Tuix app is a module using the `Tuix.App` behaviour. State lives in
`assigns`, updated with `assign/2,3` and `update/3`. Callbacks return
`{:noreply, app}` to continue or `{:stop, reason, app}` to quit.
`Tuix.run/2` takes over the terminal (raw mode + alternate screen), blocks
until the app stops, and restores the terminal on exit - including crashes.

Rendering is event-driven: nothing is written unless state changes, and
`render/1` is treated as a pure function of assigns, so no-op messages cost
nothing.

### Components

```elixir
box border: :single, flex_direction: :row, gap: 2, padding: 1 do
  text("left", fg: :cyan)
  box flex_grow: 1 do
    text("stretches to fill the remaining space")
  end
  text("right", attrs: [:bold, :underline])
end
```

**Box props:** `width` / `height` (cells, `{:percent, n}`, or `"50%"`),
`flex_direction` (`:column` default, `:row`), `flex_grow`, `gap`, `padding`,
`border` (`:single`, `:rounded`, `:double`), `border_color`, `title`, `bg`.

**Text props:** `fg`, `bg`, `attrs` (`:bold`, `:dim`, `:italic`,
`:underline`, `:blink`, `:reverse`, `:strikethrough`). Multi-line strings
render one line per row.

**Colors:** hex strings (`"#FF8800"`), RGB tuples (`{255, 136, 0}`), or
named atoms (`:red`, `:bright_cyan`, ...).

### Events

Keyboard input arrives as `%Tuix.Event.Key{}` with a `key` (a grapheme like
`"a"` or a named atom like `:up`, `:enter`, `:escape`) and `ctrl` / `alt` /
`shift` modifier flags. Terminal resizes arrive as `%Tuix.Event.Resize{}`
and automatically reflow the layout.

### Testing

```elixir
test "renders the counter" do
  assert Tuix.TestRenderer.render_to_text(Counter, 14, 3, count: 42) ==
           """
           ┌────────────┐
           │Count: 42   │
           └────────────┘
           """
           |> String.trim_trailing()
end
```

`render/4` returns the underlying `Tuix.Buffer` for structured assertions on
individual cells and their styles.

## Design notes and known trade-offs

- **Full-tree re-render per state change** is the LiveView-style trade-off:
  simple mental model, no manual invalidation. The frame diff keeps terminal
  writes minimal regardless.
- **Resize detection polls** every 250ms; the BEAM has no portable
  `SIGWINCH` delivery.
- **Wide-character edge case:** a continuation cell changing without its
  head cell is not repainted. This only occurs when new content partially
  overlaps a wide grapheme.
- **No mouse, focus, or input components yet** - see the roadmap.

## Roadmap

- Input, Select, and ScrollBox components with focus management
- Mouse support
- `justify_content` / `align_items` / wrapping in the layout engine
- Kitty keyboard protocol
- Animation / frame-loop rendering mode

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```sh
mix docs
```

Once published, the docs can be found at <https://hexdocs.pm/tuix>.

## License

MIT
