# Tuix

[![CI](https://github.com/ryanwinchester/tuix/actions/workflows/ci.yml/badge.svg)](https://github.com/ryanwinchester/tuix/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tuix.svg)](https://hex.pm/packages/tuix)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/tuix)

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
  def handle_event(%Tuix.Event.Key{key: :up}, app) do
    {:noreply, update(app, :count, &(&1 + 1))}
  end

  def handle_event(%Tuix.Event.Key{key: :down}, app) do
    {:noreply, update(app, :count, &(&1 - 1))}
  end

  def handle_event(%Tuix.Event.Key{key: "q"}, app) do
    {:stop, :normal, app}
  end

  def handle_event(_event, app), do: {:noreply, app}

  @impl true
  def render(assigns) do
    box border: :rounded, title: "Counter", padding: 1, gap: 1 do
      text "Count: #{assigns.count}", fg: "#00FF00", attrs: [:bold]
      text "Press ↑/↓ to change, q to quit", fg: :bright_black
    end
  end
end

Tuix.run(Counter)
```

Try it: `mix run examples/counter.exs`

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Core concepts](#core-concepts)
  - [Apps](#apps)
  - [Components](#components)
  - [Events](#events)
  - [Focus](#focus)
  - [Mouse](#mouse)
  - [Inputs](#inputs)
  - [Selects](#selects)
  - [Scroll boxes](#scroll-boxes)
  - [Testing](#testing)
- [Packaging](#packaging)
- [Design notes and known trade-offs](#design-notes-and-known-trade-offs)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Demo video](#demo-video)
- [License](#license)

## Features

- **LiveView-style apps** - `mount/2`, `handle_event/2`, `handle_info/2`, and
  a pure `render/1` over assigns. Any Elixir message (timers, `Task` results,
  PubSub broadcasts) can drive the UI through `handle_info/2`.
- **Declarative components** - `box` and `text` are plain data constructors;
  conditionals and comprehensions compose naturally inside `do` blocks.
- **Keyboard focus** - mark boxes `focusable` and Tab / Shift+Tab traversal,
  focus styling, and per-element event targeting come for free.
- **Mouse support** - clicks focus focusable elements, the wheel scrolls
  scroll boxes, releases synthesize GUI-style `:click` events, and every
  event reaches the app with the element under the pointer as `target`.
- **Text input** - a controlled, grapheme-aware single-line input with
  cursor, placeholder, masking, and horizontal scrolling; edits arrive as
  events and the app owns the value.
- **Select** - a controlled list picker: arrow keys move the selection,
  changes arrive as events, and long lists scroll to keep the selection
  visible.
- **Scroll box** - a focusable scrolling container with a proportional
  scrollbar; arrows and PgUp/PgDn/Home/End scroll, and `snap: :bottom`
  keeps logs pinned to the newest entry.
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
- Erlang/OTP 29+

OTP 29 provides raw terminal mode (`:shell.start_interactive/1`), the
terminfo-aware `:io_ansi` module used for terminal setup and capability
detection, and `SIGWINCH` delivery for resize events.

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
  text "left", fg: :cyan

  box flex_grow: 1 do
    text "stretches to fill the remaining space"
  end

  text "right", attrs: [:bold, :underline]
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
`shift` modifier flags. Mouse input arrives as `%Tuix.Event.Mouse{}` (see
[Mouse](#mouse)). Terminal resizes arrive as `%Tuix.Event.Resize{}` and
automatically reflow the layout.

### Focus

Boxes with `focusable: true` and a stable `:id` join the focus ring. The
runtime cycles focus with Tab / Shift+Tab (in document order, wrapping) and
moves it on mouse click, applies `focus_border_color` / `focus_bg` to the
focused element, and stamps every key event with the focused id as `target`:

```elixir
def render(assigns) do
  box flex_direction: :row, gap: 1 do
    box id: :left, focusable: true, autofocus: true,
        border: :single, focus_border_color: :cyan do
      text "left pane"
    end

    box id: :right, focusable: true, border: :single, focus_border_color: :cyan do
      text "right pane"
    end
  end
end

def handle_event(%Tuix.Event.Key{key: :up, target: :left}, app), do: ...
```

Focus can also be controlled programmatically with `focus/2` and `blur/1`
(and read with `focused/1`). Every focus change — traversal or programmatic —
is delivered to the app as a `%Tuix.Event.Focus{id: new, from: old}` event.
If the focused element disappears from the tree, focus is cleared.

Focus styles also apply to ancestors of the focused element (CSS
`:focus-within`), so a bordered box wrapping a focused input highlights
automatically; use `focus_within_border_color` / `focus_within_bg` to style
ancestors differently from the focused element itself.

Try it: `mix run examples/focus.exs`

### Mouse

Mouse reporting is on by default. Clicking a focusable element focuses it
(delivering the usual `%Tuix.Event.Focus{}` event), and the wheel scrolls
the scroll box under the pointer - those ticks are consumed by the
framework, like keyboard scrolling. Everything else (and wheel events away
from any scroll box) reaches `handle_event/2` as a `%Tuix.Event.Mouse{}`
with:

- `kind` - `:press`, `:release`, `:click`, `:drag` (pointer moved with a
  button held), `:scroll_up`, or `:scroll_down`
- `button` - `:left`, `:middle`, `:right`, or `nil` (wheel events)
- `x` / `y` - 0-based cell coordinates
- `ctrl` / `alt` / `shift` modifier flags
- `target` - the id of the innermost focusable element under the pointer
  (`nil` when none), so apps can pattern match per element:

```elixir
def handle_event(%Tuix.Event.Mouse{kind: :click, target: :sidebar}, app), do: ...
```

A `:click` is synthesized after a `:release` that lands on the same target
its `:press` hit - releasing over a different element cancels it, so apps
get GUI-style click semantics without tracking press/release pairs
themselves. The raw `:press` and `:release` events are still delivered.

While mouse reporting is active the terminal's native text selection is
unavailable; pass `mouse: false` to `Tuix.run/2` to keep it:

```elixir
Tuix.run(MyApp, mouse: false)
```

### Inputs

`input/1` builds a single-line text input. Inputs are focusable by default
and controlled: the app owns the value, and edits arrive as
`%Tuix.Event.Input{}` events that the app assigns back (LiveView form
style) — or transforms, e.g. to enforce a format:

```elixir
def render(assigns) do
  # The box border highlights while the input is focused (focus-within).
  box border: :single, title: "Email", focus_border_color: :cyan do
    input id: :email, value: assigns.email, placeholder: "you@example.com"
  end
end

def handle_event(%Tuix.Event.Input{id: :email, value: value}, app),
  do: {:noreply, assign(app, email: value)}

def handle_event(%Tuix.Event.Key{key: :enter, target: :email}, app),
  do: submit(app)
```

While an input is focused it consumes printable keys, `:backspace`,
`:delete`, and `:left` / `:right` / `:home` / `:end` (grapheme-aware, with
the cursor managed by the runtime). Everything else — `:enter`, `:escape`,
ctrl combos, Tab traversal — falls through to the app with `target` set.
`mask: "•"` renders password fields; long values scroll horizontally to
keep the cursor visible.

Try it: `mix run examples/login.exs`

### Selects

`select/1` builds a vertical list picker. Like inputs, selects are
focusable by default and controlled — the selection follows the highlight,
so `:up` / `:down` / `:home` / `:end` emit `%Tuix.Event.Select{}` with the
new value immediately:

```elixir
def render(assigns) do
  box border: :single, title: "Plan", focus_border_color: :cyan do
    select id: :plan, options: [{"Basic", :basic}, {"Pro", :pro}], value: assigns.plan
  end
end

def handle_event(%Tuix.Event.Select{id: :plan, value: value}, app),
  do: {:noreply, assign(app, plan: value)}
```

Options are `{label, value}` tuples or bare strings. Navigation clamps at
the boundaries, `:enter` falls through with `target` set (keep a draft
value in assigns for commit-on-Enter flows), and lists taller than the
select scroll to keep the selection visible.

Try it: `mix run examples/select.exs`

### Scroll boxes

`scroll_box/2` builds a focusable container whose children are laid out at
their full height and scrolled vertically within the box. It is built on
the focus model: Tab into it (or `autofocus` it) and `:up` / `:down`
scroll by a row, `:page_up` / `:page_down` by a viewport, and `:home` /
`:end` jump to the boundaries. The mouse wheel scrolls the box under the
pointer (three rows per tick) without focusing it. The offset is
framework-managed - like an input's cursor, no event reaches the app and
there is nothing to assign back. When the content overflows, a
proportional scrollbar is drawn in the rightmost column (over the border,
when the box has one):

```elixir
def render(assigns) do
  scroll_box id: :log, border: :single, title: "Log",
             height: 10, focus_border_color: :cyan do
    for line <- assigns.lines, do: text(line)
  end
end
```

With `snap: :bottom` the box starts scrolled to the bottom and stays
pinned there as content grows - chat histories, log tails. Scrolling up
detaches; scrolling back to the bottom (or pressing `:end`) re-attaches.

Try it: `mix run examples/scroll_box.exs` (and the chat history pane in
`mix run examples/chat.exs`)

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

## Packaging

Tuix apps ship as plain OTP releases (`mix release`) or as single self-contained
executables built with [Burrito](https://github.com/burrito-elixir/burrito).
Tuix is pure Elixir, so there are no NIFs to cross-compile. See the
[packaging guide](guides/packaging.md) for the application entry-point
pattern and current Burrito caveats, and [`examples/burrito`](https://github.com/ryanwinchester/tuix/tree/main/examples/burrito)
for a complete working project.

## Design notes and known trade-offs

- **Full-tree re-render per state change** is the LiveView-style trade-off:
  simple mental model, no manual invalidation. The frame diff keeps terminal
  writes minimal regardless.
- **Resize detection** uses `SIGWINCH` where the OTP/platform supports it
  (`:os.set_signal/2`), falling back to 250ms polling elsewhere.
- **Wide-character edge case:** a continuation cell changing without its
  head cell is not repainted. This only occurs when new content partially
  overlaps a wide grapheme.
- **Mouse capture vs. text selection:** enabling mouse reporting (the
  default) disables the terminal's native text selection; opt out with
  `mouse: false`.

## Roadmap

If there's a roadmap item you'd like to see, upvote its issue with a 👍
reaction. Items with more upvotes will receive more attention.

- `justify_content` / `align_items` / wrapping in the layout engine
  ([#2](https://github.com/ryanwinchester/tuix/issues/2))
- Select enhancements: multi-select, typeahead/filtering, wrap-around
  navigation, `PageUp` / `PageDown`, click-to-select an option
  ([#3](https://github.com/ryanwinchester/tuix/issues/3))
- ScrollBox enhancements: scroll-into-view for focused descendants,
  horizontal scrolling, scrollbar dragging
  ([#4](https://github.com/ryanwinchester/tuix/issues/4))
- Drag-and-drop: captured drags with `:drag_end` / `:drop` events
  ([#5](https://github.com/ryanwinchester/tuix/issues/5))
- Event bubbling: deliver events through the ancestor chain of the hit
  target with a way to stop propagation
  ([#6](https://github.com/ryanwinchester/tuix/issues/6))
- Text selection: mouse-driven selection of rendered text with
  copy-to-clipboard (OSC 52)
  ([#7](https://github.com/ryanwinchester/tuix/issues/7))
- Dropdown/overlay presentation for selects (needs z-order/overlay
  machinery) ([#8](https://github.com/ryanwinchester/tuix/issues/8))
- Input enhancements: readline-style ctrl bindings, `max_length`, real
  terminal cursor (blinking)
  ([#9](https://github.com/ryanwinchester/tuix/issues/9))
- Kitty keyboard protocol
  ([#10](https://github.com/ryanwinchester/tuix/issues/10))
- Animation / frame-loop rendering mode
  ([#11](https://github.com/ryanwinchester/tuix/issues/11))

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```sh
mix docs
```

Once published, the docs can be found at <https://hexdocs.pm/tuix>.

## Demo video

`mix run examples/chat.exs`

https://github.com/user-attachments/assets/080ae9b3-78fd-4cd9-afeb-1ea8e047054b

## License

Copyright 2026 Ryan Winchester

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
