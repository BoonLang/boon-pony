# Boon-Pony TUI Implementation Contract

This file is the authoritative implementation contract for `boon-pony`.
Do not move this plan into `AGENTS.md`. If an `AGENTS.md` file is added later, it must point to this file rather than duplicating or weakening it.

`boon-pony` is a native Pony implementation and code generation backend for Boon. Its first product is a real full-screen terminal playground plus direct-play terminal apps generated from Boon source.

No Zig, Rust, Raybox, Sokol, SDL, browser runtime, WebAssembly runtime, DOM renderer, GPU renderer, 3D renderer, or migration from another implementation is part of this repository's runtime. External repos are references only.

## 1. Reference Inputs

The plan has two reference inputs:

1. Upstream Boon language and example corpus:
   - Repo: `https://github.com/BoonLang/boon`
   - Initial pin: `c924d9f7d7e1c156604c9377e0487db48c278353`
   - Corpus root: `playground/frontend/src/examples`
   - Observed corpus at this pin: 61 `.bn` files and 38 `.expected` files.

2. Local `boon-zig` terminal/source reference:
   - Local path: `/home/martinkavik/repos/boon-zig`
   - Observed commit: `01b70116b4c81dd34cab10767dcb3a680a835fc5`
   - Observed branch: `source-physical-ir`
   - The worktree was dirty when this plan was hardened. Before implementation, capture a fresh reference snapshot with:

```bash
git -C /home/martinkavik/repos/boon-zig rev-parse HEAD
git -C /home/martinkavik/repos/boon-zig status --short --branch
```

Use `boon-zig` for product behavior and verification style, not for copied code. In particular:

- Canonical Boon event/source spelling is `SOURCE`.
- Legacy `LINK` is not canonical.
- Runnable examples must not use `: LINK` or `|> LINK`.
- A real host terminal playground must be verified in a PTY, not only by scripted snapshots.

## 2. Product Goals

`boonpony tui` opens a full-screen interactive terminal playground with:

- example picker
- source/file panel
- live terminal preview
- semantic tree/debug inspector
- diagnostics/build log
- frame/performance panel
- raw keyboard and mouse input
- pause, resume, single-frame step
- record/replay

`boonpony play <project>` compiles a Boon project to Pony, builds a native executable, and runs it directly as a playable terminal app.

The required compilation pipeline is:

```text
Boon source project
  -> Pony lexer/parser/resolver/lowerer
  -> Boon HIR
  -> Boon Flow IR
  -> source-shape/source-slot analysis
  -> Pony source code generator
  -> generated Pony app + shared Pony runtime
  -> ponyc
  -> native executable
  -> terminal runtime
```

The TUI must be real and interactive. A line REPL, static preview, hardcoded Pony game, or fake playground is not acceptable.

## 3. Canonical Language Contract

### SOURCE

`SOURCE` marks a runtime-provided event/input field. It replaces legacy `LINK`.

Canonical examples:

```text
button: [event: [press: SOURCE]]
input: [event: [change: SOURCE key_down: SOURCE blur: SOURCE]]
sources: [
  keyboard: [event: [key_down: SOURCE]]
  frame: [event: [tick: SOURCE]]
]
```

If pipe-based source binding is needed, it must be spelled:

```text
Element/button(element: [event: [press: SOURCE]], style: [], label: TEXT { Add })
  |> SOURCE { store.elements.add_button }
```

`SOURCE` constraints:

- `SOURCE` is only valid as a source leaf or source binding.
- `SOURCE` cannot be used as a normal value expression.
- Source paths must be static and discoverable before runtime.
- Duplicate source paths fail.
- Incompatible bindings such as `button: [event: SOURCE]` fail.
- Dynamic source shapes fail.
- Source slots must preserve source spans for diagnostics.

Required negative diagnostics:

```text
button: [event: [press: LINK]]
  -> `LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode

bad: SOURCE + 1
  -> SOURCE marks a runtime source field and cannot be used as a normal value

button: [event: SOURCE]
  -> incompatible source binding

button: SOURCE
button: SOURCE
  -> duplicate source path or multiple active binders
```

### Parser Coverage

Full parser compatibility is required before Pong can be accepted.

The Pony parser must support the pinned upstream Boon corpus plus canonical `SOURCE` migration/overrides. Required syntax includes:

- variables and nested objects
- lists, maps, tagged objects, spreads
- function definitions and function calls
- `PASS` and `PASSED`
- `SOURCE`
- `LATEST`, `HOLD`, `THEN`, `WHEN`, `WHILE`, `BLOCK`, `SKIP`, `FLUSH`
- pipes, field access, comparisons, arithmetic
- text literals and interpolation
- `BITS`, `MEMORY`, and `BYTES` as parseable language constructs

Parser acceptance is not only "can parse Pong". It must parse every imported runnable `.bn` file in the corpus manifest after canonical migration rules are applied.

### Source Shape

Add a source-shape analysis pass after parsing/resolution and before Flow IR lowering.

Output shape:

```text
source_slot:
  id: stable integer in source traversal order
  semantic_id: dotted source path such as button.event.press
  payload_type: inferred event payload type
  source_span: byte range in the Boon source
```

Minimum payload types:

- `Pulse`
- `Bool`
- `Text`
- `Number`
- `KeyEvent`
- `MouseEvent`
- `ResizeEvent`
- `TickEvent`

`PASS`/`PASSED` must be normalized before runtime execution. The runtime and generated apps must never receive raw unresolved `PASS` or `PASSED` markers.

## 4. Repository Layout

Use this layout:

```text
boon-pony/
  BOON_PONY_TUI_PLAN.md
  AGENTS.md
  README.md
  TOOLCHAIN.md

  examples/
    upstream/
    upstream_overrides/
    source_physical/
      counter/
      interval/
      cells/
      todo_mvc/
      pong/
      arkanoid/
    terminal/
      pong/
      arkanoid/
      counter/
      interval/
      cells/
      cells_dynamic/
      todo_mvc/

  fixtures/
    upstream_pin.json
    corpus_manifest.json
    syntax_inventory.json
    feature_matrix.md
    spec_gaps.md

  src/
    boonpony/
      main.pony
      cli/
      frontend/
      project/
      lowering/
      source_shape/
      codegen/
      terminal/
      tui/
      runtime_host/
      verify/
      bench/
      support/
    runtime/
      boon_runtime/

  tests/
    examples/
    parser/
    source_shape/
    terminal_grid/
    protocol/

  build/
    generated/
    bin/
    reports/
    cache/
    work/
```

Generated and cache directories under `build/` are not source truth. Every checked-in expected fixture must live under `fixtures/`, `examples/`, or `tests/`.

## 5. Toolchain

Create `TOOLCHAIN.md` in Phase 0.

It must pin:

- `ponyc` version
- `ponyup` version or exact installation command
- supported OS list
- terminal capability requirements

Initial support:

- Linux first
- macOS allowed if raw input works
- Windows must fail with a clear diagnostic until raw input and ANSI output are implemented

This machine currently may not have `ponyc` or `ponyup` installed. Phase 0 must verify and document the actual install path before any later acceptance can pass.

Required terminal capabilities:

- alternate screen
- cursor hide/show
- cursor positioning
- ANSI SGR attributes
- UTF-8
- raw or cbreak input
- resize reporting or polling

## 6. CLI Contract

Build command:

```bash
ponyc src/boonpony -o build/bin
```

Required commands:

```bash
build/bin/boonpony --help
build/bin/boonpony manifest --check
build/bin/boonpony import-upstream --source <path-or-git-url> --commit <sha>
build/bin/boonpony verify-parser --corpus fixtures/corpus_manifest.json
build/bin/boonpony verify-source-shape --all
build/bin/boonpony compile <project>
build/bin/boonpony build <project>
build/bin/boonpony verify <project-or---all>
build/bin/boonpony verify-terminal <project-or---all>
build/bin/boonpony snapshot <project> --size 80x24 --frames 120
build/bin/boonpony bench <project-or---all>
build/bin/boonpony play <project>
build/bin/boonpony tui
build/bin/boonpony tui --example pong
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
```

Exit-code rules:

- `0`: requested operation succeeded and all required checks passed.
- `1`: user source, expected fixture, parser, verification, or benchmark failure.
- `2`: invalid CLI usage.
- `3`: unsupported platform or missing toolchain.
- `4`: internal compiler/runtime error.

Every verification command must write a report under `build/reports/` unless a report path is explicitly provided.

Required report fields:

```json
{
  "command": "verify-terminal",
  "status": "pass|fail",
  "started_at": "...",
  "finished_at": "...",
  "toolchain": {"ponyc": "...", "os": "..."},
  "cases": [],
  "failures": []
}
```

## 7. Upstream Import And Corpus Manifest

`import-upstream` must:

- fetch or read the pinned upstream Boon repo
- copy examples into `examples/upstream`
- copy expected files
- apply checked-in canonical overrides from `examples/upstream_overrides`
- generate `fixtures/upstream_pin.json`
- generate `fixtures/corpus_manifest.json`
- generate `fixtures/syntax_inventory.json`
- generate `fixtures/feature_matrix.md`

`fixtures/upstream_pin.json` must contain:

```json
{
  "repo": "https://github.com/BoonLang/boon",
  "commit": "c924d9f7d7e1c156604c9377e0487db48c278353",
  "source_root": "playground/frontend/src/examples",
  "imported_root": "examples/upstream",
  "override_root": "examples/upstream_overrides",
  "tree_hash": "...",
  "tree_hash_command": "git ls-files -s examples/upstream examples/upstream_overrides | sha256sum"
}
```

`fixtures/corpus_manifest.json` must record for every example:

- name
- category
- source path
- imported path
- entry file
- all `.bn` files
- expected file path if present
- parser status
- source-shape status
- runtime status
- terminal status
- browser status if imported metadata mentions browser behavior
- hard-gate status
- blockers
- exact commands proving current status

No example may be silently skipped. Unsupported examples must appear in the manifest with explicit blockers.

Runnable `.bn` examples under `examples/` must not contain canonical-forbidden `LINK` text. Historical docs may contain `LINK`, but must be marked as docs and must not be run as canonical examples.

## 8. Frontend, HIR, And Flow IR

The frontend must produce:

- tokens
- AST with spans
- static AST where needed
- diagnostics with source locations
- resolved names
- persistence facts
- source-shape facts

HIR and Flow IR must represent:

- `SOURCE` source slots
- `HOLD`
- `LATEST`
- `THEN`
- `WHEN`
- `WHILE`
- `BLOCK`
- `SKIP`
- `FLUSH`
- timers
- keyboard events
- mouse events
- resize events
- terminal canvas
- semantic document tree
- event handlers
- list transformations
- state persistence

Generated Pony apps must not parse or understand Boon syntax at runtime. They receive generated data structures and runtime calls only.

## 9. Terminal Host APIs

Canonical Boon host APIs:

```text
Terminal/canvas(width, height, items)
Terminal/size()
Terminal/focused()
Terminal/key_down()
Terminal/mouse()
Terminal/tick()
Duration[milliseconds: N]
Duration[seconds: N]
Timer/interval(duration)
Canvas/text(x, y, text)
Canvas/rect(x, y, width, height, glyph)
Canvas/group(items)
```

`Terminal/key_down()` is the canonical keyboard API. `Keyboard/key_down()` is allowed only as a compatibility alias that lowers to the same Flow IR.

Minimum key events:

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
Backspace
Tab
ShiftLeft
ShiftRight
CtrlC
Text
```

Terminal examples should use source bags:

```text
sources: [
  keyboard: [event: [key_down: SOURCE]]
  frame: [event: [tick: SOURCE]]
]
```

## 10. Terminal Backend

Implement a custom Pony terminal backend:

- POSIX raw/cbreak mode through Pony FFI declarations
- alternate screen enter/leave
- cursor hide/show
- terminal size query
- ANSI SGR renderer
- double-buffered cell grid
- diff renderer
- headless terminal backend
- interactive terminal backend

Cell contract:

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

Grid contract:

```pony
class ref CellGrid
  let width: USize
  let height: USize
  fun ref put(x: I64, y: I64, cell: Cell val)
  fun ref text(x: I64, y: I64, text: String, style: Style val)
  fun ref rect(x: I64, y: I64, width: I64, height: I64, glyph: String, style: Style val)
  fun ref clear(cell: Cell val)
```

Diff renderer rules:

- Do not redraw the full screen every steady-state frame.
- Full redraw is allowed only after resize, alternate-screen entry, or explicit invalidation.
- Flush once per frame.
- Record changed cells and bytes written.

Raw terminal safety:

- restore terminal on normal exit
- restore terminal on `Q`
- restore terminal on `Ctrl+C`
- restore terminal after generated child exit
- restore terminal after handled panic where possible
- print a visible fallback diagnostic if restoration fails

Unsupported raw mode diagnostic:

```text
error: interactive TUI requires raw terminal mode; platform not yet supported
```

Allowed non-ASCII glyphs for v0:

```text
█
▉
▔
●
↑
↓
←
→
```

If glyph width is ambiguous, `--ascii` must force ASCII-only output.

## 11. Generated Runtime

Generated apps have two runtime modes.

Direct mode:

```bash
build/bin/generated/pong
```

Protocol mode:

```bash
build/bin/generated/pong --protocol
```

Runtime state shape:

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

One generated app uses one deterministic runtime actor. Do not generate one actor per reactive node.

Event flow:

```text
host event
  -> source slot payload
  -> deterministic dispatch
  -> update AppState
  -> build document/canvas
  -> render terminal grid
  -> update semantic tree
  -> update metrics
```

Tests use virtual time. Interactive sessions use real time.

## 12. Protocol Mode

Generated apps in embedded preview mode use JSONL.

Every message includes `protocol_version: 1`.

Input messages:

```json
{"protocol_version":1,"type":"resize","width":80,"height":24}
{"protocol_version":1,"type":"key","key":"W"}
{"protocol_version":1,"type":"mouse","x":10,"y":4,"button":"left","action":"press"}
{"protocol_version":1,"type":"tick","ms":50}
{"protocol_version":1,"type":"frame"}
{"protocol_version":1,"type":"pause"}
{"protocol_version":1,"type":"resume"}
{"protocol_version":1,"type":"tree"}
{"protocol_version":1,"type":"metrics"}
{"protocol_version":1,"type":"bench","scenario":"frame","count":10000}
{"protocol_version":1,"type":"quit"}
```

Output messages:

```json
{"protocol_version":1,"type":"ready","app":"pong"}
{"protocol_version":1,"type":"frame","revision":12,"width":80,"height":24,"runs":[]}
{"protocol_version":1,"type":"tree","revision":12,"tree":{}}
{"protocol_version":1,"type":"metrics","revision":12,"metrics":{}}
{"protocol_version":1,"type":"diagnostic","diagnostic":{}}
{"protocol_version":1,"type":"bench_result","result":{}}
{"protocol_version":1,"type":"error","message":"...","fatal":false}
{"protocol_version":1,"type":"bye"}
```

Frame encoding uses `runs` in v0. A `cells` array is not part of v0.

Run shape:

```json
{"x":0,"y":0,"text":"0 : 0","fg":"white","bg":"black","bold":false,"underline":false,"inverse":false}
```

Unknown message types must return a structured error. Fatal protocol errors exit nonzero.

## 13. Semantic Tree

Every rendered app frame exposes a semantic tree:

```pony
class val SemanticNode
  let id: String
  let role: Role
  let text: String
  let value: String
  let visible: Bool
  let focused: Bool
  let selected: Bool
  let checked: (Bool | None)
  let bounds: Bounds
  let children: Array[SemanticNode val] val
```

Required roles:

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

Required game semantic IDs:

```text
pong.ball
pong.left_paddle
pong.right_paddle
pong.score
pong.status
arkanoid.ball
arkanoid.paddle
arkanoid.brick.<row>.<col>
arkanoid.score
arkanoid.status
```

Verification must query the semantic tree. OCR-style checks are forbidden.

## 14. TUI Playground

The playground is a Pony host multiplexer inspired by the `boon-zig` terminal playground.

Required behavior:

- own one real child session per loaded example
- preserve inactive tab state
- do not tick inactive tabs unless a future config explicitly enables it
- render the selected child in the preview panel
- route keyboard and mouse input only into the active child
- reserve host keys for tab switching and TUI commands
- show source, diagnostics, semantic tree, metrics, and logs for the active example

Minimum playground tabs:

```text
Counter
Interval
Cells
Cells Dynamic
TodoMVC
Pong
Arkanoid
Temperature Converter
Flight Booker
Timer
CRUD
Circle Drawer
```

Minimum host controls:

```text
Shift+Right: next tab
Shift+Left: previous tab
[: previous tab
]: next tab
h: previous tab when focus is on tab bar
l: next tab when focus is on tab bar
F5: start/stop recording
F6: replay recording
F7: save recording
F8: load recording
Esc: pause/resume active app
Q: quit playground
```

Scripted playground sequence must prove:

- tab switch to Interval
- Interval advances while active
- tab switch to Cells
- Cells opens edit mode and commits A0 to `7`
- mouse click selects TodoMVC tab
- `Shift+Left` lands on Cells Dynamic

Live PTY verification must additionally exercise every tab listed above before the playground is claimed ready for manual use.

## 15. Examples

### Pong

Files:

```text
examples/terminal/pong/pong.bn
examples/terminal/pong/pong.expected
examples/source_physical/pong/pong.bn
tests/examples/pong_sequence.json
tests/terminal_grid/pong.expected
```

Pong must be written in Boon and generated to Pony. A handwritten Pony Pong is invalid.

Game requirements:

- 80x24 default board
- two paddles
- one ball
- score text
- status text
- `W`/`S` move left paddle
- `ArrowUp`/`ArrowDown` move right paddle
- top/bottom wall bounce
- paddle bounce
- missed ball scores for opponent
- first to 9 wins
- Space resets after win

Acceptance:

```bash
build/bin/boonpony play examples/terminal/pong
build/bin/boonpony verify-terminal examples/terminal/pong
build/bin/boonpony bench examples/terminal/pong --scenario frame --frames 10000
```

### Arkanoid

Files:

```text
examples/terminal/arkanoid/arkanoid.bn
examples/terminal/arkanoid/arkanoid.expected
examples/source_physical/arkanoid/arkanoid.bn
tests/examples/arkanoid_sequence.json
tests/terminal_grid/arkanoid.expected
```

Arkanoid must be written in Boon and generated to Pony.

Game requirements:

- 80x28 default board
- brick rows
- paddle
- ball
- score
- side/top wall bounce
- paddle bounce
- brick hit removes exactly one brick
- score increments per brick
- all bricks removed sets `Won`
- bottom miss sets `Lost`
- Space restarts after win/loss

Acceptance:

```bash
build/bin/boonpony play examples/terminal/arkanoid
build/bin/boonpony verify-terminal examples/terminal/arkanoid
build/bin/boonpony bench examples/terminal/arkanoid --scenario frame --frames 10000
```

### Upstream And 7GUI-Style Terminal Projections

Required terminal projections:

- counter
- interval
- cells
- cells_dynamic
- todo_mvc
- temperature_converter
- flight_booker
- timer
- crud
- circle_drawer

Each projection needs:

- imported or repo-authored `.bn`
- canonical `SOURCE` source slots
- terminal expected fixture
- semantic tree assertions
- headless script
- manifest evidence

## 16. Expected Files And Scripts

Preserve the upstream expected-file model instead of inventing an unrelated DSL.

Expected files are TOML-like and support:

```text
[test]
[output]
[timing]
[[sequence]]
[[persistence]]
actions = [...]
expect = "..."
```

Supported action families:

- `assert_contains`
- `assert_not_contains`
- `assert_focused`
- `assert_input_empty`
- `assert_input_typeable`
- `assert_input_placeholder`
- `assert_button_has_outline`
- `assert_checkbox_count`
- `assert_checkbox_checked`
- `assert_checkbox_unchecked`
- `assert_cells_cell_text`
- `click_button`
- `click_checkbox`
- `click_text`
- `dblclick_cells_cell`
- `set_input_value`
- `set_focused_input_value`
- `type`
- `key`
- `wait`
- `clear_states`
- `run`

Terminal extensions:

- `assert_canvas_contains`
- `assert_node_exists`
- `assert_node_field`
- `assert_score`
- `assert_status`
- `tick`
- `frame`
- `wait_frames`
- `snapshot`
- `pause`
- `resume`
- `mouse_click`
- `press_key`

Every action result must include pass/fail, action source location, current frame, and diagnostic context.

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

## 17. Benchmarks And Metrics

Interactive targets:

- key-to-frame latency under 16 ms when terminal and host allow it
- 60 FPS TUI shell
- 20 FPS game logic for Pong and Arkanoid unless a game explicitly configures another tick
- no full-screen redraw every steady-state frame

Required benchmarks:

```bash
build/bin/boonpony bench examples/terminal/pong --scenario frame --frames 10000
build/bin/boonpony bench examples/terminal/arkanoid --scenario frame --frames 10000
build/bin/boonpony bench examples/terminal/pong --scenario input --events 100000
build/bin/boonpony bench --protocol examples/terminal/pong --scenario roundtrip --frames 1000
```

Bench report fields:

- OS
- terminal name
- terminal size
- CPU model if available
- `ponyc` version
- optimization mode
- warmup count
- measured count
- events/sec
- frames/sec
- runtime update ns
- tree build ns
- terminal render ns
- changed cells per frame
- bytes written per frame
- generated binary size
- `ponyc` compile time

Runtime benchmarks and protocol roundtrip benchmarks must be separate report entries.

## 18. No Fake Pass Rule

A pass is invalid if achieved by:

- skipping examples
- hiding examples
- ignoring expected files
- replacing Boon terminal games with handwritten Pony games
- hardcoding expected output for a named example
- returning empty frames
- returning empty semantic trees
- ignoring keyboard, mouse, resize, or tick events
- ignoring `Timer/interval`
- silently dropping canvas items
- silently dropping modules
- treating unsupported syntax as successful
- accepting legacy `LINK` as canonical syntax
- claiming manual readiness without a real PTY pass for interactive terminal behavior

Unsupported features must produce explicit diagnostics and failing reports.

## 19. Implementation Phases

Each phase is complete only when its acceptance commands pass and its report artifacts exist.

### Phase 0: Pony CLI Bootstrap

Deliver:

- `TOOLCHAIN.md`
- `README.md`
- `AGENTS.md` pointing to this plan
- source skeleton
- `boonpony --help`
- command parser

Acceptance:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony --help
build/bin/boonpony tui --help
build/bin/boonpony play --help
```

### Phase 1: Corpus Import And Manifests

Deliver:

- upstream import command
- canonical `SOURCE` override mechanism
- `fixtures/upstream_pin.json`
- `fixtures/corpus_manifest.json`
- `fixtures/syntax_inventory.json`
- `fixtures/feature_matrix.md`

Acceptance:

```bash
build/bin/boonpony import-upstream --source https://github.com/BoonLang/boon --commit c924d9f7d7e1c156604c9377e0487db48c278353
build/bin/boonpony manifest --check
```

### Phase 2: Full Parser Compatibility

Deliver:

- lexer
- parser
- AST
- static AST where needed
- source spans
- parser diagnostics
- canonical `SOURCE` parsing
- legacy `LINK` rejection fixture

Acceptance:

```bash
build/bin/boonpony verify-parser --corpus fixtures/corpus_manifest.json
build/bin/boonpony parse examples/source_physical/pong/pong.bn
build/bin/boonpony parse tests/parser/legacy_link_rejected.bn
```

The legacy rejection command must fail with the targeted diagnostic.

### Phase 3: Source Shape And HIR/Flow IR

Deliver:

- resolver
- HIR
- source-shape pass
- Flow IR
- source-slot diagnostics
- PASS/PASSED normalization

Acceptance:

```bash
build/bin/boonpony verify-source-shape --all
build/bin/boonpony flow examples/source_physical/counter/counter.bn
build/bin/boonpony flow examples/source_physical/pong/pong.bn
```

### Phase 4: Expected Runner And Reports

Deliver:

- expected parser
- action runner
- persistence sections
- terminal extensions
- JSON reports
- no-fake-pass checks

Acceptance:

```bash
build/bin/boonpony verify --all --report build/reports/verify.json
```

### Phase 5: Terminal Backend And Headless Grid

Deliver:

- `Cell`
- `CellGrid`
- ANSI renderer
- headless backend
- snapshots
- resize full invalidation

Acceptance:

```bash
build/bin/boonpony snapshot examples/terminal/counter --size 80x24 --frames 3
build/bin/boonpony verify-terminal examples/terminal/counter
```

### Phase 6: Raw Input And Terminal Safety

Deliver:

- POSIX raw mode
- key decoder
- mouse decoder including SGR mouse
- terminal restore logic
- PTY smoke tool

Acceptance:

```bash
build/bin/boonpony tui --keyboard-test
build/bin/boonpony verify-terminal-safety --pty
```

Manual PTY evidence must include immediate key decode and terminal restoration after `Q` and `Ctrl+C`.

### Phase 7: Codegen, Runtime, And Protocol

Deliver:

- Pony code generator
- shared runtime
- generated direct mode
- generated protocol mode
- generated metadata with source hash

Acceptance:

```bash
build/bin/boonpony compile examples/terminal/counter
build/bin/boonpony build examples/terminal/counter
build/bin/boonpony protocol-smoke examples/terminal/counter
```

### Phase 8: Terminal Canvas Smoke

Deliver:

- `Terminal/canvas`
- `Canvas/text`
- `Canvas/rect`
- `Timer/interval`
- `Terminal/key_down`
- deterministic snapshots

Acceptance:

```bash
build/bin/boonpony verify-terminal examples/terminal/interval
build/bin/boonpony verify-terminal examples/terminal/cells
```

### Phase 9: Pong

Deliver:

- canonical `SOURCE` Pong source bags
- generated Pony Pong
- direct play
- embedded preview
- headless expected tests
- benchmark
- record/replay

Acceptance:

```bash
build/bin/boonpony play examples/terminal/pong
build/bin/boonpony verify-terminal examples/terminal/pong
build/bin/boonpony bench examples/terminal/pong --scenario frame --frames 10000
```

Required manual PTY session:

```text
open Pong
start game
play until at least one point
verify score updates
quit
terminal restored
```

### Phase 10: Arkanoid

Deliver:

- canonical `SOURCE` Arkanoid source bags
- generated Pony Arkanoid
- direct play
- embedded preview
- headless expected tests
- benchmark
- record/replay

Acceptance:

```bash
build/bin/boonpony play examples/terminal/arkanoid
build/bin/boonpony verify-terminal examples/terminal/arkanoid
build/bin/boonpony bench examples/terminal/arkanoid --scenario frame --frames 10000
```

Required manual PTY session:

```text
open Arkanoid
play until one brick is removed
verify score increments
verify loss/restart
quit
terminal restored
```

### Phase 11: Real TUI Playground

Deliver:

- host multiplexer
- one child session per tab
- tab switching
- mouse tab selection
- source panel
- preview panel
- inspector
- log panel
- perf panel
- recording/replay

Acceptance:

```bash
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
build/bin/boonpony verify-terminal --filter playground
```

Required live PTY session:

```text
Counter increments
Interval ticks while active
Cells commits A0 to 7
Cells Dynamic renders
mouse selects TodoMVC
TodoMVC adds Write tests
Pong starts and renders rally
Arkanoid renders bricks and paddle
Temperature Converter updates both directions
Flight Booker books a return flight
Timer updates elapsed/duration UI
CRUD creates an Ada Lovelace record
Circle Drawer leaves Circles:1 after two clicks and Undo
tab wrap works both directions
no error, panic, corrupt value, or stale expected-record failure appears in the log
```

### Phase 12: Source Inspection And Editing

Deliver:

- source panel
- diagnostic highlights
- file switcher
- open external editor
- reload
- rebuild
- rerun
- working-copy diff

Acceptance:

```bash
build/bin/boonpony tui --example pong
```

Manual session:

```text
edit pong.bn
reload
rebuild
play updated game
verify diagnostics if the edit is invalid
```

## 20. Definitions Of Done

### TUI v0

TUI v0 is complete when:

- full parser compatibility gate passes
- canonical `SOURCE` source-shape gate passes
- `boonpony tui` opens a real full-screen terminal UI
- alternate screen and raw mode restore correctly
- immediate keyboard input works
- headless CellGrid snapshots work
- generated Pony app renders a terminal canvas
- `boonpony play examples/terminal/pong` opens playable Pong
- Pong is Boon source, not handwritten Pony
- Pong has deterministic headless tests
- Pong has at least one in-app benchmark
- all implementation code is Pony

### TUI v1

TUI v1 is complete when:

- Arkanoid is playable and verified
- record/replay works
- embedded preview mode works
- direct play mode works
- all required terminal projections pass
- playground script passes
- live PTY full-tab pass is recorded
- source inspection/reload/rebuild/rerun works
- performance reports are written

## 21. Required Final Gate

Before claiming the implementation complete, run:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony manifest --check
build/bin/boonpony verify-parser --corpus fixtures/corpus_manifest.json
build/bin/boonpony verify-source-shape --all
build/bin/boonpony verify --all --report build/reports/verify.json
build/bin/boonpony verify-terminal --all --report build/reports/verify-terminal.json
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
build/bin/boonpony bench --all --report build/reports/bench.json
```

Then run a real PTY session for `boonpony tui` and exercise every playground tab listed in this plan.

The first successful public demo is:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony play examples/terminal/pong
```

It opens a real full-screen terminal Pong game generated from Boon source, responds immediately to keys, exits cleanly, restores the terminal, verifies headlessly, and benchmarks honestly.
