# Boon-Pony Real TUI Implementation Plan

Place this file at the root of the future `boon-pony` repository as:

```text
AGENTS.md
```

or:

```text
BOON_PONY_TUI_PLAN.md
```

This is a clean-slate Pony-only plan.

No Zig, Rust, Raybox, Sokol, SDL, browser runtime, WebAssembly runtime, DOM renderer, or migration work is part of this plan.

---

## 0. Mission

`boon-pony` is a native Pony implementation and codegen backend for Boon.

The first real product is a **full-screen interactive terminal playground** where Boon examples can be played and tested manually, including terminal game examples such as **Pong** and **Arkanoid**.

The target experience is:

```text
boonpony tui
```

which opens a full-screen terminal application with:

```text
example picker
source/file panel
live terminal preview
semantic tree/debug panel
frame/performance stats
build/diagnostic log
interactive keyboard controls
```

and:

```text
boonpony play examples/terminal/pong
boonpony play examples/terminal/arkanoid
```

which compile the selected Boon project to Pony, build a native executable, and run it directly as a playable terminal app.

The core pipeline is:

```text
Boon source project
  -> Pony lexer/parser/resolver/lowerer
  -> Boon Flow IR
  -> Pony source code generator
  -> generated Pony app + shared Pony runtime
  -> ponyc
  -> native executable
  -> full-screen terminal runtime
```

The TUI must be real and interactive, not a line-based REPL.

---

## 1. Non-goals

Do not implement these in this repository:

```text
browser support
WebAssembly support
Raybox support
GUI/window rendering
Sokol/SDL/raylib integration
Zig tooling
Rust tooling
Slang/WGSL/WebGPU
3D rendering
physical visual rendering
3D printing/export
DOM playground
```

`boon-pony` is native-only and terminal-first.

---

## 2. Main deliverables

There are two related deliverables.

### 2.1 `boonpony tui`

A full-screen terminal playground for browsing, compiling, running, inspecting, and manually testing Boon examples.

Layout:

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Boon-Pony TUI  Example: pong  Status: running  FPS: 60  Frame: 182         │
├───────────────────┬────────────────────────────────────┬───────────────────┤
│ Examples          │ Preview                            │ Inspector         │
│                   │                                    │                   │
│ > counter         │  ┌──────────────────────────────┐  │ Focus: canvas     │
│   cells           │  │ 0 : 0                        │  │ Nodes: 8          │
│   pong            │  │                              │  │ Events: 182       │
│   arkanoid        │  │ █                            │  │ State: Running    │
│                   │  │                ●             │  │                   │
│ Files             │  │                            █ │  │ Selected node:    │
│   pong.bn         │  │                              │  │ ball              │
│   pong.expected   │  └──────────────────────────────┘  │                   │
├───────────────────┴────────────────────────────────────┴───────────────────┤
│ Log: build ok | keys: W/S, ↑/↓, Space reset | F1 help | Esc pause          │
└────────────────────────────────────────────────────────────────────────────┘
```

Required TUI features:

```text
alternate screen
raw keyboard input
non-blocking input
real-time frame loop
terminal resize handling
double-buffered grid rendering
ANSI diff renderer
example picker
source preview
live canvas preview
semantic tree inspector
build and diagnostics panel
frame/performance panel
pause/resume
single-frame step
record/replay input
manual expected-step runner
```

### 2.2 `boonpony play <project>`

A direct play mode for generated Boon terminal apps.

Example:

```bash
boonpony play examples/terminal/pong
boonpony play examples/terminal/arkanoid
```

Behavior:

```text
1. compile Boon project
2. generate Pony source
3. build native app with ponyc
4. exec generated app in full-screen terminal mode
5. let the generated app own the terminal until exit
```

This mode is used for manual play and performance testing without the playground UI around it.

---

## 3. Fixed technology stack

Implementation language:

```text
Pony
```

Compiler:

```text
ponyc
```

TUI:

```text
custom Pony terminal backend
ANSI escape sequences
alternate screen
raw/cbreak input mode
double-buffered Cell grid
```

Pony standard packages to use where appropriate:

```text
term
time
process
files
collections
json
```

Raw terminal mode:

```text
POSIX:
  implement termios wrapper in Pony FFI declarations

Windows:
  implement console-mode wrapper later, or fail with a clear diagnostic until supported
```

No C source files are allowed. FFI declarations in Pony are allowed.

Verification:

```text
headless terminal grid backend
deterministic virtual time
deterministic key-event scripts
snapshot tests
semantic tree tests
```

---

## 4. Toolchain pins

Create:

```text
TOOLCHAIN.md
```

It must pin:

```text
ponyc version
ponyup version or installation instruction
supported operating systems
known terminal requirements
```

Initial support target:

```text
Linux/macOS terminals first
UTF-8 terminal required
ANSI escape support required
Windows support allowed only when raw input and ANSI output are implemented or clearly diagnosed
```

Required terminal capabilities:

```text
alternate screen
cursor hide/show
cursor positioning
256-color output preferred
Unicode glyph display preferred
raw or cbreak key input
```

---

## 5. Repository layout

Use this layout:

```text
boon-pony/
  AGENTS.md
  BOON_PONY_TUI_PLAN.md
  README.md
  TOOLCHAIN.md

  examples/
    upstream/
      minimal/
      hello_world/
      counter/
      cells/
      todo_mvc/
      ...
    terminal/
      pong/
        pong.bn
        pong.expected
      arkanoid/
        arkanoid.bn
        arkanoid.expected

  fixtures/
    corpus_manifest.json
    syntax_inventory.json
    feature_matrix.md
    terminal_key_sequences.json

  src/
    boonpony/
      main.pony

      cli/
        args.pony
        command.pony
        command_tui.pony
        command_play.pony
        command_compile.pony
        command_verify.pony
        command_bench.pony

      frontend/
        source_file.pony
        span.pony
        diagnostic.pony
        token.pony
        lexer.pony
        parser.pony
        ast.pony

      project/
        project.pony
        project_loader.pony
        module_resolver.pony
        virtual_file_system.pony
        manifest.pony
        upstream_importer.pony

      lowering/
        resolver.pony
        hir.pony
        flow_ir.pony
        type_facts.pony
        dependency_graph.pony

      codegen/
        pony_writer.pony
        name_mangle.pony
        codegen_context.pony
        generate_project.pony
        generate_app_state.pony
        generate_dispatch.pony
        generate_document.pony
        generate_terminal_main.pony
        generate_protocol_main.pony

      tui/
        tui_app.pony
        tui_state.pony
        tui_layout.pony
        tui_panels.pony
        tui_theme.pony
        tui_commands.pony
        example_picker.pony
        source_panel.pony
        preview_panel.pony
        inspector_panel.pony
        diagnostics_panel.pony
        perf_panel.pony

      terminal/
        terminal.pony
        terminal_raw_posix.pony
        terminal_raw_windows.pony
        ansi.pony
        key_decoder.pony
        key_event.pony
        mouse_event.pony
        terminal_size.pony
        cell.pony
        cell_grid.pony
        grid_diff.pony
        frame_pacer.pony
        headless_terminal.pony
        interactive_terminal.pony

      runtime_host/
        live_project.pony
        generated_app_process.pony
        protocol_client.pony
        protocol_encoder.pony
        protocol_decoder.pony
        quiescence.pony
        input_recorder.pony
        input_replay.pony

      verify/
        expected_parser.pony
        expected_runner.pony
        semantic_query.pony
        snapshot_runner.pony
        verification_report.pony

      bench/
        benchmark_runner.pony
        benchmark_report.pony

      support/
        json_writer.pony
        path_utils.pony
        process_runner.pony
        stable_hash.pony
        string_builder.pony
        timer.pony

    runtime/
      boon_runtime/
        value.pony
        document.pony
        element.pony
        style.pony
        event.pony
        app_state_base.pony
        semantic_tree.pony
        terminal_canvas.pony
        terminal_renderer.pony
        terminal_protocol.pony
        persist.pony
        route_store.pony
        virtual_clock.pony
        metrics.pony
        benchmark.pony

  build/
    generated/
    bin/
    reports/
    cache/
    work/
```

---

## 6. CLI commands

Build the main tool:

```bash
ponyc src/boonpony -o build/bin
```

Required commands:

```bash
build/bin/boonpony tui
build/bin/boonpony tui --example pong
build/bin/boonpony tui --example arkanoid

build/bin/boonpony play examples/terminal/pong
build/bin/boonpony play examples/terminal/arkanoid

build/bin/boonpony compile examples/terminal/pong
build/bin/boonpony build examples/terminal/pong
build/bin/boonpony verify examples/terminal/pong
build/bin/boonpony verify-terminal examples/terminal/pong
build/bin/boonpony bench examples/terminal/pong
```

Optional but useful:

```bash
build/bin/boonpony import-upstream --source ../boon --out examples/upstream
build/bin/boonpony manifest
build/bin/boonpony snapshot examples/terminal/pong --frames 120
```

---

## 7. TUI architecture

### 7.1 Two execution modes

The TUI supports two ways to run examples.

#### Embedded preview mode

Used by:

```bash
boonpony tui
```

The TUI starts generated apps in protocol mode:

```bash
build/bin/generated/pong --protocol
```

The generated app sends terminal frames, semantic tree snapshots, metrics, and diagnostics to the playground over a line-delimited protocol. The playground draws those frames into the preview panel.

This mode supports:

```text
example switching
debug panels
source viewing
semantic tree inspection
record/replay
expected stepping
performance overlays
```

#### Direct play mode

Used by:

```bash
boonpony play examples/terminal/pong
```

The generated app runs directly in full-screen TUI mode and owns the terminal.

This mode supports:

```text
lowest overhead
manual game play
raw keyboard input
full terminal canvas
frame timing
in-app benchmarks
```

### 7.2 Why both modes exist

Embedded preview is best for debugging.

Direct play is best for feeling whether the generated app is fast and playable.

Both modes must use the same generated Boon runtime and same terminal renderer primitives. Only the outer host differs.

---

## 8. Terminal backend

### 8.1 Cell grid

Represent terminal output as a grid of cells:

```pony
class val Cell
  let glyph: String
  let fg: Color
  let bg: Color
  let bold: Bool
  let italic: Bool
  let underline: Bool
  let inverse: Bool
```

```pony
class ref CellGrid
  let width: USize
  let height: USize
  fun ref put(x: I64, y: I64, cell: Cell val)
  fun ref text(x: I64, y: I64, text: String, style: Style val)
  fun ref rect(x: I64, y: I64, width: I64, height: I64, glyph: String, style: Style val)
  fun ref clear(cell: Cell val)
```

### 8.2 Diff renderer

Use double buffering:

```text
previous grid
current grid
diff changed cells
emit minimal cursor moves and style changes
flush once per frame
```

Do not clear and redraw the whole screen every frame unless terminal resize or full invalidation occurs.

### 8.3 ANSI support

Implement:

```text
alternate screen enter/leave
cursor hide/show
cursor move
clear screen
set foreground/background color
reset attributes
bold/underline/inverse
```

### 8.4 Raw input

Interactive TUI must receive keys immediately.

Implement POSIX raw/cbreak mode using Pony FFI to termios.

Required behavior:

```text
disable canonical line buffering
disable echo
restore terminal mode on exit
restore terminal mode on crash/signaled exit where possible
```

If raw mode cannot be enabled, fail with:

```text
error: interactive TUI requires raw terminal mode; platform not yet supported
```

### 8.5 Key decoder

Decode:

```text
Escape
Enter
Backspace
Tab
Space
ArrowLeft
ArrowRight
ArrowUp
ArrowDown
Home
End
PageUp
PageDown
F1-F12
Ctrl+C
W
A
S
D
letters
digits
punctuation
UTF-8 text input where meaningful
```

Support common ANSI escape sequences and record unknown sequences in diagnostics.

### 8.6 Terminal resize

Handle resize by:

```text
querying terminal size
recreating grids
recomputing layout
sending resize event to current app
rerendering full frame
```

---

## 9. TUI layout and panels

### 9.1 Top bar

Shows:

```text
project name
current file
run status
FPS
frame number
mode: paused/running/stepping
current backend: embedded/direct/headless
```

### 9.2 Example picker panel

Shows:

```text
upstream examples
terminal examples
status badges
build/cache status
```

Keyboard:

```text
Up/Down selects
Enter loads
/ searches
b builds
r runs
p direct-plays
```

### 9.3 Source panel

Shows current `.bn` file.

Required features:

```text
syntax-colored text
line numbers
current diagnostic highlight
file switcher
read-only mode first
editable mode later
```

Editing can be added after interactive play works.

### 9.4 Preview panel

Draws the current app frame.

For Pong and Arkanoid, this is the game canvas.

The preview panel must preserve aspect enough that 80x24/80x28 games are readable.

### 9.5 Inspector panel

Shows:

```text
semantic tree
selected node
focused node
hovered node
event ports
runtime state summary
Flow IR node summary
```

### 9.6 Diagnostics/log panel

Shows:

```text
parse errors
lowering errors
ponyc errors
runtime errors
protocol errors
raw key decoder warnings
```

### 9.7 Perf panel

Shows:

```text
frame time
render time
input decode time
event dispatch time
tree build time
terminal diff cells
bytes written
events processed
generated app metrics
```

---

## 10. Boon terminal APIs

Implement these Boon host APIs first.

### 10.1 Terminal

```text
Terminal/canvas(width, height, items)
Terminal/key_down()
Terminal/size()
Terminal/focused()
```

`Terminal/key_down()` produces semantic key events:

```text
NoKey
W
A
S
D
ArrowLeft
ArrowRight
ArrowUp
ArrowDown
Space
Enter
Escape
```

### 10.2 Timer

```text
Duration[milliseconds: N]
Duration[seconds: N]
Timer/interval(duration)
```

Interactive TUI uses real time.

Tests and snapshots use virtual time.

### 10.3 Canvas

```text
Canvas/text(x, y, text)
Canvas/rect(x, y, width, height, glyph)
Canvas/group(items)
```

Optional after Pong/Arkanoid pass:

```text
Canvas/line(x1, y1, x2, y2, glyph)
Canvas/border(x, y, width, height)
Canvas/sprite(x, y, lines)
```

### 10.4 Keyboard

Use either:

```text
Keyboard/key_down()
```

or:

```text
Terminal/key_down()
```

Pick one as canonical in the repo. The examples may alias the other name for compatibility.

---

## 11. Generated app runtime

Generated apps have two runtime modes.

### 11.1 Direct TUI mode

The generated executable owns the terminal.

```bash
build/bin/generated/pong
```

Generated main shape:

```pony
actor Main
  new create(env: Env) =>
    let app = GeneratedApp(env)
    let terminal = InteractiveTerminal(env, app)
    terminal.run()
```

The generated app receives:

```text
key events
resize events
frame tick events
quit event
```

and returns:

```text
CellGrid frame
SemanticTree
RuntimeMetrics
```

### 11.2 Protocol mode

The generated executable does not own the terminal.

```bash
build/bin/generated/pong --protocol
```

It reads commands from stdin and writes JSONL frames/trees/metrics to stdout.

Used by `boonpony tui` embedded preview and automated verification.

### 11.3 Runtime actor

Use one deterministic runtime actor per generated app.

Do not generate one actor per reactive node.

Generated runtime state:

```pony
actor GeneratedApp
  var _state: AppState
  let _persist: PersistStore
  let _route: RouteStore
  let _clock: VirtualClock
  var _revision: U64
  var _last_canvas: TerminalCanvas val
  var _last_tree: SemanticNode val
  var _metrics: RuntimeMetrics
```

Event flow:

```text
host input event
  -> generated event value
  -> deterministic dispatch
  -> update AppState
  -> build document/canvas
  -> render terminal grid
  -> update semantic tree
  -> update metrics
```

---

## 12. Frame loop

### 12.1 Interactive frame loop

Target:

```text
60 FPS for TUI shell
20 FPS or 50 ms tick for Pong/Arkanoid game logic unless example requests otherwise
```

The host frame loop:

```text
poll/decode input
deliver input events
deliver due timer/frame events
run runtime update
build canvas/grid
diff render
sleep/pacer until next frame
```

### 12.2 Deterministic test frame loop

Headless tests do not sleep.

They use:

```text
virtual time
scripted keys
fixed terminal size
fixed frame count
deterministic snapshots
```

Example:

```bash
boonpony snapshot examples/terminal/pong --size 80x24 --frames 120 --keys "10:W,11:W,40:ArrowUp"
```

---

## 13. Pong example

Create:

```text
examples/terminal/pong/pong.bn
examples/terminal/pong/pong.expected
```

Pong must be written in Boon, not Pony.

Pony provides only host APIs:

```text
Terminal/canvas
Canvas/rect
Canvas/text
Terminal/key_down or Keyboard/key_down
Timer/interval
Duration[milliseconds: 50]
```

Controls:

```text
W/S moves left paddle
ArrowUp/ArrowDown moves right paddle
Space resets after game over
Esc pauses in TUI host
Q quits in TUI host
```

Game requirements:

```text
80x24 board by default
two paddles
one ball
score text
status text
ball bounces off top/bottom
ball bounces off paddles
missed ball scores for opponent
first to 9 wins
space resets after win
```

Manual smoke:

```bash
boonpony play examples/terminal/pong
```

Manual checklist:

```text
game opens full-screen
paddles visible
ball moves at playable speed
W/S move left paddle immediately
ArrowUp/ArrowDown move right paddle immediately
score updates after miss
Space resets after win
Q or Ctrl+C exits and restores terminal
```

Headless tests:

```text
initial snapshot has two paddles, one ball, "0 : 0"
W/S move left paddle within bounds
ArrowUp/ArrowDown move right paddle within bounds
ball bounces off walls
ball bounces off paddles
miss gives point and resets ball
first score to 9 changes status
Space resets after game over
```

---

## 14. Arkanoid example

Create:

```text
examples/terminal/arkanoid/arkanoid.bn
examples/terminal/arkanoid/arkanoid.expected
```

Arkanoid must be written in Boon, not Pony.

Controls:

```text
A/D or ArrowLeft/ArrowRight move paddle
Space restarts after win/loss
Esc pauses in TUI host
Q quits in TUI host
```

Game requirements:

```text
80x28 board by default
brick rows
paddle
ball
score
ball bounces off side/top walls
ball bounces off paddle
ball hitting brick removes exactly that brick
score increments per brick
all bricks removed -> Won
ball passes bottom -> Lost
Space restarts after win/loss
```

Manual smoke:

```bash
boonpony play examples/terminal/arkanoid
```

Manual checklist:

```text
game opens full-screen
bricks visible
paddle visible
ball moves at playable speed
A/D and arrows move paddle immediately
brick disappears when hit
score increments
loss state appears when ball passes bottom
Space restarts
Q or Ctrl+C exits and restores terminal
```

Headless tests:

```text
initial snapshot has bricks, paddle, ball, "Score 0"
left/right keys move paddle within bounds
ball bounces off side/top walls
ball bounces off paddle
brick collision removes one brick
score increments by one
removing all bricks sets Won
bottom miss sets Lost
Space restarts after win/loss
```

---

## 15. Other required terminal projections

### 15.1 Counter

Must render as a terminal UI:

```text
[ - ] 0 [ + ]
```

or equivalent.

Required:

```text
keyboard focus
click simulation
Enter/Space activates focused button
persistence test
```

### 15.2 Cells

Must render a spreadsheet viewport:

```text
     A    B    C    D ...
 1   5    15   30
 2   10
 3   15
```

Required:

```text
keyboard navigation
edit mode
Enter commits
Escape cancels
formula recomputation
scroll viewport
```

### 15.3 TodoMVC

Must render a semantic terminal projection:

```text
todos
> [new todo input]
[ ] Buy milk
[x] Walk dog
All  Active  Completed
```

Required:

```text
add todo
toggle todo
filter
edit
delete
clear completed
state persistence
```

---

## 16. Source corpus

Import upstream Boon examples from:

```text
https://github.com/BoonLang/boon
```

Also include repo-authored terminal examples:

```text
examples/terminal/pong
examples/terminal/arkanoid
```

Generate:

```text
fixtures/corpus_manifest.json
fixtures/feature_matrix.md
fixtures/syntax_inventory.json
```

The manifest must record:

```text
name
kind
entry file
files
expected file
terminal support status
playable status
parser status
runtime status
blockers
```

No example may be silently skipped.

---

## 17. Compiler pipeline

The compiler pipeline is:

```text
ProjectLoader
  -> Lexer
  -> Parser
  -> AST
  -> ModuleResolver
  -> NameResolver
  -> HIR
  -> FlowIR
  -> PonyCodegen
  -> Generated Pony project
```

FlowIR must represent:

```text
HOLD cells
LINK ports
LATEST
THEN
WHEN
WHILE
BLOCK
SKIP
timers
keyboard events
terminal canvas
document root
event handlers
list transformations
state persistence
```

Generated Pony apps must not need to understand Boon syntax.

---

## 18. Code generation

Generate one Pony project per Boon project.

Generated layout:

```text
build/generated/pong/
  main.pony
  app_state.pony
  generated_document.pony
  generated_dispatch.pony
  generated_functions.pony
  generated_terminal.pony
  generated_metadata.pony

  boon_runtime/
    value.pony
    document.pony
    element.pony
    style.pony
    event.pony
    semantic_tree.pony
    terminal_canvas.pony
    terminal_renderer.pony
    persist.pony
    route_store.pony
    virtual_clock.pony
    metrics.pony
```

Generated apps must compile with:

```bash
ponyc build/generated/pong -o build/bin/generated
```

Generated source must be readable:

```text
2-space indentation
stable generated names
comments with source spans
metadata file with source hash and compiler version
```

---

## 19. Terminal semantic tree

Every rendered app frame must also expose a semantic tree.

```pony
class val SemanticNode
  let id: String
  let role: Role
  let text: String
  let value: String
  let visible: Bool
  let focused: Bool
  let hovered: Bool
  let selected: Bool
  let checked: (Bool | None)
  let children: Array[SemanticNode val] val
```

Roles include:

```text
document
terminal_canvas
canvas_rect
canvas_text
button
text_input
checkbox
grid
cell
text
container
debug_value
```

The TUI inspector and expected runner query this tree.

Game canvases must expose semantic objects:

```text
pong.ball
pong.left_paddle
pong.right_paddle
pong.score
arkanoid.ball
arkanoid.paddle
arkanoid.brick.<row>.<col>
arkanoid.score
```

This makes game tests precise without OCR.

---

## 20. Protocol mode

In embedded preview mode, generated apps use JSONL protocol.

Input messages:

```json
{"type":"resize","width":80,"height":24}
{"type":"key","key":"W"}
{"type":"tick","ms":50}
{"type":"frame"}
{"type":"pause"}
{"type":"resume"}
{"type":"state"}
{"type":"tree"}
{"type":"metrics"}
{"type":"bench","scenario":"frame","count":10000}
{"type":"quit"}
```

Output messages:

```json
{"type":"ready","app":"pong","protocol_version":1}
{"type":"frame","revision":12,"width":80,"height":24,"cells":[...]}
{"type":"tree","revision":12,"tree":{...}}
{"type":"metrics","metrics":{...}}
{"type":"diagnostic","diagnostic":{...}}
{"type":"bench_result","result":{...}}
{"type":"error","message":"..."}
{"type":"bye"}
```

Protocol rules:

```text
unknown message type fails loudly
every mutating command eventually produces frame, tree, metrics, error, or diagnostic
large frame payloads may be encoded as compact runs rather than one JSON object per cell
```

Frame encoding should support run-length compression:

```json
{
  "type": "frame",
  "width": 80,
  "height": 24,
  "runs": [
    {"x":0,"y":0,"text":"0 : 0","fg":"white","bg":"black"},
    {"x":2,"y":10,"text":"█","fg":"white","bg":"black"}
  ]
}
```

---

## 21. Performance requirements

This project is meant to feel fast.

### 21.1 Interactive responsiveness

Targets:

```text
key-to-frame latency under 16 ms when terminal and host allow it
60 FPS TUI shell
20 FPS game logic for Pong/Arkanoid unless configured otherwise
no full-screen redraw every frame during steady state
```

### 21.2 Benchmarks

Required benchmarks:

```bash
boonpony bench examples/terminal/pong --scenario frame --frames 10000
boonpony bench examples/terminal/arkanoid --scenario frame --frames 10000
boonpony bench examples/terminal/pong --scenario input --events 100000
```

Benchmarks must report:

```text
events/sec
frames/sec
runtime update ns
tree build ns
terminal render ns
cells changed per frame
bytes written per frame
generated binary size
ponyc compile time
```

### 21.3 Do not benchmark protocol overhead by accident

For runtime performance, benchmarks run inside the generated app.

Protocol roundtrip benchmarks are separate and labeled as such.

### 21.4 Render metrics

Every interactive frame records:

```text
frame number
input events processed
runtime update duration
canvas build duration
semantic tree build duration
terminal diff duration
changed cells
bytes written
sleep/pacer duration
```

---

## 22. Recording and replay

The TUI must support input recording.

Commands/keys:

```text
F5 start/stop recording
F6 replay recording
F7 save recording
F8 load recording
```

Recording format:

```json
{
  "example": "pong",
  "terminal_size": [80, 24],
  "events": [
    {"frame": 10, "type": "key", "key": "W"},
    {"frame": 11, "type": "key", "key": "W"},
    {"frame": 40, "type": "key", "key": "ArrowUp"}
  ]
}
```

Use recordings for:

```text
manual regression
snapshot tests
benchmark scenarios
bug reproduction
```

---

## 23. Expected files

Each terminal example has an expected file.

Required expected actions:

```text
assert_contains
assert_not_contains
assert_canvas_contains
assert_node_exists
assert_node_field
assert_score
assert_status
key
tick
frame
wait_frames
snapshot
pause
resume
```

Example style:

```text
assert_contains "0 : 0"
assert_node_exists "pong.ball"
key W
tick 50
assert_node_field "pong.left_paddle" "y" "9"
wait_frames 10
assert_canvas_contains "●"
```

The expected runner uses:

```text
headless terminal grid
virtual time
semantic tree
recorded snapshots
```

No OCR.

---

## 24. Phases

### Phase 0 — Pony CLI bootstrap

Deliver:

```text
boonpony --help
boonpony tui --help
boonpony play --help
directory skeleton
toolchain file
```

Acceptance:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony --help
```

### Phase 1 — Terminal backend skeleton

Deliver:

```text
Cell
CellGrid
ANSI renderer
alternate screen
cursor hide/show
terminal size query
headless grid backend
simple demo frame
```

Acceptance:

```bash
build/bin/boonpony tui --demo
build/bin/boonpony snapshot --demo --frames 3
```

### Phase 2 — Raw keyboard input

Deliver:

```text
POSIX raw mode
terminal restore on exit
key decoder
resize handling
Ctrl+C/Q safe exit
```

Acceptance:

```bash
build/bin/boonpony tui --keyboard-test
```

Manual check:

```text
keys show immediately
arrows decode
W/A/S/D decode
Space decodes
terminal restored after exit
```

### Phase 3 — TUI playground shell

Deliver:

```text
full-screen layout
example picker
preview panel
log panel
perf panel
keyboard navigation
```

Acceptance:

```bash
build/bin/boonpony tui
```

### Phase 4 — Compiler and generated app stub

Deliver:

```text
minimal compiler pipeline enough for generated terminal stub
generate Pony app
build with ponyc
run in direct TUI mode
run in protocol mode
```

Acceptance:

```bash
build/bin/boonpony play examples/terminal/stub
build/bin/boonpony tui --example stub
```

### Phase 5 — Boon terminal canvas

Deliver:

```text
Terminal/canvas
Canvas/text
Canvas/rect
Timer/interval
Terminal/key_down
generated app renders canvas
headless snapshots
```

Acceptance:

```bash
build/bin/boonpony verify-terminal examples/terminal/canvas_smoke
```

### Phase 6 — Pong

Deliver:

```text
examples/terminal/pong/pong.bn
generated Pony app
direct play mode
embedded preview mode
headless expected tests
benchmarks
record/replay
```

Acceptance:

```bash
build/bin/boonpony play examples/terminal/pong
build/bin/boonpony verify-terminal examples/terminal/pong
build/bin/boonpony bench examples/terminal/pong
```

Manual check:

```text
play Pong for at least one point
paddles respond instantly
score updates
terminal restores after exit
```

### Phase 7 — Arkanoid

Deliver:

```text
examples/terminal/arkanoid/arkanoid.bn
generated Pony app
direct play mode
embedded preview mode
headless expected tests
benchmarks
record/replay
```

Acceptance:

```bash
build/bin/boonpony play examples/terminal/arkanoid
build/bin/boonpony verify-terminal examples/terminal/arkanoid
build/bin/boonpony bench examples/terminal/arkanoid
```

Manual check:

```text
play until at least one brick is removed
score increments
loss/restart works
terminal restores after exit
```

### Phase 8 — Upstream semantic examples

Deliver:

```text
counter
interval
cells terminal projection
todo_mvc terminal projection
```

Acceptance:

```bash
build/bin/boonpony verify-terminal examples/upstream/counter
build/bin/boonpony verify-terminal examples/upstream/cells
build/bin/boonpony verify-terminal examples/upstream/todo_mvc
```

### Phase 9 — Interactive source inspection and editing

Deliver:

```text
source panel
diagnostic highlights
open external editor
reload
rebuild
rerun
diff working copy
```

Acceptance:

```bash
build/bin/boonpony tui --example pong
```

Manual check:

```text
edit pong.bn
reload
rebuild
play updated game
```

---

## 25. No fake pass rule

A verification pass is invalid if achieved by:

```text
skipping examples
hiding examples
ignoring expected files
replacing Boon terminal games with handwritten Pony games
hardcoding expected output for a named example
returning empty frames
returning empty semantic trees
ignoring keyboard events
ignoring Timer/interval
silently dropping canvas items
silently dropping modules
treating unsupported syntax as successful
```

Unsupported features must produce explicit diagnostics and failing reports.

---

## 26. Definition of done for TUI v0

TUI v0 is complete when:

```text
boonpony tui opens a real full-screen terminal UI.
boonpony tui uses alternate screen and restores terminal on exit.
keyboard input is immediate, not line buffered.
arrow keys, W/A/S/D, Space, Enter, Escape, Q decode correctly.
the TUI has example picker, preview, log, and perf panels.
headless CellGrid snapshots work.
a generated Pony app can render a terminal canvas.
boonpony play examples/terminal/pong opens a playable Pong game.
Pong is written in Boon, not hardcoded in Pony.
Pong has headless deterministic tests.
Pong has at least one in-app benchmark.
all implementation code is Pony.
```

Required manual session:

```text
build/bin/boonpony tui
select pong
build
run
play for one point
open perf panel
pause
step one frame
resume
quit
terminal restored
```

---

## 27. Definition of done for TUI v1

TUI v1 is complete when:

```text
Arkanoid is playable.
Arkanoid is written in Boon, not hardcoded in Pony.
Arkanoid has headless deterministic tests.
record/replay works.
snapshot tests work.
embedded preview mode works.
direct play mode works.
counter runs in terminal projection.
cells runs in terminal projection.
todo_mvc runs in terminal projection.
TUI source inspection works.
reload/rebuild/rerun works.
performance reports are written.
```

Required manual sessions:

```text
play Pong for at least one point
play Arkanoid until one brick is removed
edit a source file and rebuild
record input and replay it
run counter and click/increment via keyboard
run cells and edit a cell
run todo_mvc and add/toggle a todo
```

---

## 28. Important implementation notes

### 28.1 Raw terminal safety

Always restore terminal state on:

```text
normal exit
Q quit
Ctrl+C
panic where catchable
child process exit
```

Add a visible fallback message if restoration fails.

### 28.2 Unicode width

Treat terminal cell width carefully.

Initial allowed glyphs:

```text
ASCII
█
▉
▔
●
↑
↓
←
→
```

If width is ambiguous, include a fallback ASCII mode:

```bash
boonpony play examples/terminal/pong --ascii
```

### 28.3 Determinism

Interactive mode uses real time.

Tests use virtual time.

Game logic must produce the same state for the same initial state, terminal size, time ticks, and key-event sequence.

### 28.4 Actors

Use actors for:

```text
Main
TuiApp
GeneratedAppProcess
GeneratedApp inside generated binary
```

Do not generate one actor per reactive node.

### 28.5 Performance honesty

Measure separately:

```text
Boon runtime update
terminal canvas build
semantic tree build
terminal diff rendering
protocol overhead
ponyc compile time
```

Do not mix them into one misleading number.

---

## 29. Reference behavior from boon-zig

The Zig plan treats terminal rendering as a primary development tool and names `pong` and `arkanoid` as P0 terminal examples. This Pony repo mirrors that idea, but implements it in Pony only.

Required host concepts:

```text
Terminal/key_down
Timer/interval
Terminal/canvas
Canvas/rect
Canvas/text
headless grid backend
interactive TUI backend
deterministic frame/key tests
```

`boon-pony` must not copy Zig implementation code. It should copy only the product expectation: Boon terminal examples are playable and testable in a native terminal.

---

## 30. Final summary

The first successful demo should be:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony play examples/terminal/pong
```

A real full-screen terminal Pong game opens.

It is generated from Boon source.

It responds immediately to keys.

It exits cleanly and restores the terminal.

It can be verified headlessly.

It can be benchmarked.

That is the v0 north star.
