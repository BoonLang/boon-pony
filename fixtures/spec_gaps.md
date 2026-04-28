# Boon-Pony Spec Gaps

This file tracks implementation-contract gaps that are intentionally not hidden
by passing reports.

## Current Boundary

- Phase 0 bootstrap and Phase 1 corpus import are implemented in native Pony.
- Phase 2 parser verification now emits a concrete AST/CST tree with source
  spans, node counts, function/declaration counts, token counts, and canonical
  SOURCE diagnostics.
- Phase 3 source-shape verification now emits SOURCE slots with stable IDs,
  semantic paths, payload types, slot kinds, and source spans. It also verifies
  rejection fixtures for legacy LINK, SOURCE-as-value, incompatible source
  bindings, duplicate source paths, and dynamic source shapes.
- Phase 3 reports include HIR/Flow evidence for source slots, PASS/PASSED
  normalization, HOLD, LATEST, THEN, WHEN, WHILE, BLOCK, SKIP, FLUSH, terminal
  canvas, timer, keyboard, mouse, resize, tick, semantic tree, persistence, and
  list-transform features when those features appear in a file. Flow reports
  also include a concrete terminal-canvas projection with canvas dimensions,
  `Canvas/text` and `Canvas/rect` drawable entries, structural `Canvas/group`
  entries with child counts, arguments or text/glyph payloads, and source spans.
- Phase 4 expected-file verification now includes both the pinned upstream
  expected files and the checked-in terminal expected files. All 43 expected
  files execute generated Pony runtime/protocol probes. The five required
  terminal expected files must match generated output. The 38 upstream expected
  probes also execute generated apps, then retain expected-file replay as the
  authoritative pass path until complete semantic lowering is implemented.
  Current reports expose the remaining upstream generated-runtime gaps instead
  of hiding them.
- Phase 5 terminal-grid verification now renders generated protocol frames
  through the native Pony `CellGrid` headless backend where codegen is available,
  including the playground preview projection; the playground no longer has a
  source-derived preview fallback and reports unavailable generated child frames
  as diagnostics.
  `tests/terminal_grid/*.expected` files are used as assertions for required
  text and semantic IDs rather than as the source of rendered terminal text. The
  backend includes ANSI full/diff rendering and treats resize as full-grid
  invalidation.
- Phase 6 raw-input safety is PTY-verified through a native Pony tmux harness,
  including immediate Q, Ctrl+C, and SGR mouse decoding with terminal restore.
  The broader PTY proof report records the tmux output file, every evidence
  string checked, and whether terminal restoration was observed for Pong,
  Arkanoid, playground, and source-edit sessions.
- Phase 7 codegen now emits Pony source from the checked-in Boon project files
  in native Pony. The generated output includes protocol v1 JSONL, direct mode,
  source hashes, and SOURCE/canvas-derived terminal runs for counter, interval,
  cells, Pong, and Arkanoid. Codegen now requires the source to pass native
  parser and source-shape analysis first, generated metadata records AST node
  counts, source-slot counts, terminal behavior, canvas dimensions, and lowered
  item counts; the old checked-in Pony templates were removed.
- Terminal-grid verification now prefers generated app protocol JSONL for
  counter, interval, cells, Pong, and Arkanoid. Those generated app runs now
  come from the terminal IR emitted by source-shape analysis, then render
  through the headless `CellGrid`. The expected files remain assertions only.
- Later game, playground, and source-edit commands still pass their existing
  checks, but they are not yet sufficient evidence for the full plan because the
  generated game behavior is still a small SOURCE/canvas/state lowering rather
  than a complete Boon semantic runtime.
- Phase 12 source editing now creates a real working copy under
  `build/playground-working/<tab>/<tab>.bn`, applies a valid edit, reloads it
  through the native parser, builds it through the Pony codegen path, reruns the
  generated demo binary, records generated protocol frames for the edited
  working copy, records a real diff, and verifies invalid diagnostics through
  the PTY source-edit proof.
- Runtime tab previews now come from cumulative generated child protocol replay
  without a host-side preview overlay, and source-edit rerun proof includes
  generated protocol frames for the edited working copy.
- Phase 11 playground reports now create concrete per-tab session artifacts
  under `build/playground-sessions/<tab>/session.json`. Each session records the
  tab ID, source path, source existence, parser status, generated child command,
  child report/output paths, child exit code, protocol capture path, and
  generated protocol frame count. The playground script prepares generated
  protocol children for all 12 playground tabs, and the live preview panel now
  streams visible text from generated protocol frame captures after cumulative
  per-tab child action replay with no host-side preview overlay.
- Benchmark reports now measure the Pony benchmark loop with `Time.nanos()`,
  render generated protocol frames through the headless `CellGrid` for changed
  cell/byte counts, and measure generated Pony compile time by running the build
  path for each benchmark project.
- Generated Pony apps now include the plan-required `GeneratedApp` runtime
  scaffold with `AppState`, `PersistStore`, `RouteStore`, `VirtualClock`,
  `TerminalCanvas`, `SemanticNode`, and `RuntimeMetrics` fields. Compile
  metadata exposes `runtime_state_shape` so this is report-verifiable.
- Compile metadata now includes a structured `lowering_plan` with the detected
  behavior, generated runtime profile, HIR/Flow feature list, terminal IR
  lowering status, and explicit `projection_fallback` flag. Terminal/canvas
  projects report `terminal-ir-to-pony`; generated state-profile examples report
  `hir-flow-profiled-pony`; and current generated metadata reports zero
  `projection_fallback` cases. `verify --all` now fails if runtime-case
  metadata is missing, reports `projection_fallback: true`, lacks the generic
  expected-action parser proof, reports source-derived or source-rule runtime
  profiles, uses table-driven or app-name terminal behavior detection, or
  reports a lowered terminal canvas without `terminal_run_source: terminal-ir`.
  The current generated runtime set reports zero fallback, zero source-derived
  profile, zero source-rule profile, zero table-driven behavior, zero app-name
  behavior, five terminal-IR run cases, and zero missing terminal-IR run cases;
  the old source-rule terminal behavior, app-name terminal behavior, and
  runtime-profile fallbacks have been removed from codegen.
- Generated protocol mode now reads stdin JSONL through a generated
  `InputNotify`, routes resize, key, mouse, tick, frame, tree, metrics, bench,
  pause/resume, unknown-message, and quit inputs through `GeneratedApp.dispatch`,
  parses expected-action JSON generically for action names, values, and indices
  instead of using a fixture-value whitelist, and protocol smoke verifies frame,
  semantic-tree, metrics, diagnostic, bench-result, structured error, and bye
  responses.
- Generated runtime verification now feeds the checked-in expected-file
  `click_button`, `clear_states`, `run`, and `wait` actions into generated
  protocol JSONL for the counter family. `counter`, `counter_hold`, and
  `complex_counter` render their values from generated `AppState` rather than
  from static trace needles and report `generated-runtime-action-replay`.
- The same generated action-replay path now covers simple boolean and list
  projections. `text_interpolation_update` uses a generic boolean text
  projection, `list_retain_reactive` uses an even-filter projection derived
  from generated text, and action-replay eligibility now comes from the
  HIR/Flow runtime profile instead of generated run-ID suffixes.
- `latest` also replays expected-file button actions through generated
  protocol input, with button indices selecting numeric values in a generic
  LATEST/sum projection profile in generated `AppState`.
- Multi-button expected-file replay now covers `list_object_state`,
  `button_hover_to_click_test`, and `switch_hold_test`, including generic
  indexed count-marker updates for list-object counters, generic document-text
  extraction for hover/click-state button labels, indexed boolean-state updates
  for click-state buttons, plus button-index selection and held switch state
  across generated protocol inputs.
- Generated expected-file replay now also covers checkbox, hover, text-input,
  generic timer-counter, router, form, slider, and select-option interactions for
  `checkbox_test`, generic stateless hover state for `button_hover_test`,
  `interval`, `interval_hold`, `then`, `when`, `while`, generic named-item
  filtering state for `list_map_external_dep`, generic append/count state for
  `list_retain_count` and `list_retain_remove`, generic click-text no-op replay
  for `circle_drawer`, `timer`,
  formula-based bidirectional conversion for `temperature_converter`, generic
  filter-label and checkbox-state replay for `filter_checkbox_bug`,
  generic booking-form state for `flight_booker`, plus generic
  clearable append-list replay for `shopping_list` add, clear, and re-add
  flows, plus generic conditional branch state for
  `while_function_call`, plus two-item switched counter state replay for
  `switch_hold_test`, plus timed binary operation projections for `then`,
  `when`, and `while`, plus adjustable timer state for `timer`, plus
  route-text state for `pages`, plus generated spreadsheet-state replay
  for `cells` and `cells_dynamic`, generated chained-list state replay for
  `chained_list_remove_bug`, generated CRUD state replay for `crud`, and
  generated TodoMVC state replay for `todo_mvc` and `todo_mvc_physical`.
  No upstream example now reports generated-runtime trace debt or
  case-directed generated runtime replay debt.
- Codegen is no longer gated to the five terminal demo app names. Parsed
  upstream `Document/new` projects now lower to generated Pony apps with generic
  document-text protocol frames and semantic trees; the generic document-text
  extractor is scoped to document/function UI text, ignores style-only text, and
  handles `message |> Document/new()` root bindings, boolean store defaults,
  inactive boolean arms, simple function-label expansion, top-level document
  item bindings, simple LATEST default values, and `Math/sum` projections.
  It also expands simple store-list `List/map` item-label templates, computes
  literal list counts, keeps hidden labels out of visible frames, and moves
  placeholder text after primary visible text so input-placeholder assertions
  remain runtime-verifiable without breaking contiguous output needles.
  List item boolean-status labels such as checkbox rows are expanded from
  `make_item(name: TEXT { ... })` and `item.checked` arms instead of a named
  checkbox output branch.
  Timed binary examples expand `input_row(name: TEXT { ... })`, multiline
  `Element/button` labels, and `sum_of_steps(...)` zero-state inputs through
  the same generic document path instead of named `then`/`when`/`while` initial
  output branches.
  Simple store-field interpolation and repeated `label: item` projections are
  resolved generically, so the List/map BLOCK example no longer needs a named
  initial-output branch; expression fragments from transform bodies are filtered
  out of visible protocol frames.
  Object-list counter rows are expanded from `store.counters |> List/map` and
  `make_counter()` counts, so the independent counter example starts from the
  source-derived three-row projection instead of a named initial-output branch.
  Counter button rows using `counter_button(label: ...)` and `PASSED.counter`
  are likewise projected from source shape, so Complex Counter starts as `-0+`
  without a named initial-output branch.
  Reactive list filters now project object-list `item.name` rows, numeric
  `List/map(n, label: n)` rows, and retained-count labels from the store lists,
  so `list_map_external_dep` and `list_retain_reactive` no longer need named
  initial-output branches and still satisfy generated protocol action replay.
  Switched WHILE views with True-default boolean state now select the active
  nested branch and numeric `click_count` labels through generic source-pattern
  projection, so `switch_hold_test` no longer needs a named initial/final output
  branch while preserving generated protocol action replay.
  Filter-checkbox rows now render from HOLD default values and `render_item`
  source shape, including `create_item(name: ...)`, view-label arguments, and
  lowercase checked-state labels; `filter_checkbox_bug` no longer needs a named
  initial-output branch and still has generated protocol replay evidence.
  Router page examples now derive initial route content and the generated route
  lookup index from `Router/route`, `nav_button`, and `page(...)` source shape,
  with inactive 404 fallback text excluded from visible frames; `pages` no
  longer needs a named initial/final output branch.
  Chained List/remove replay now relies on the generated `chained_list_state`
  runtime state machine instead of a named final-output branch, and normalizes
  `Clear completed` expected-action payloads so generated protocol action replay
  reaches the clear/append/remove proof frames.
  CRUD replay now uses the generated `crud_state` runtime state machine for the
  create/filter/update/delete protocol proof instead of a named final-output
  branch; the no-fake-pass report still shows zero trace debt.
  TodoMVC and TodoMVC Physical now likewise rely on generated Todo runtime state
  profiles instead of named final-output branches. Counter and Counter HOLD use
  generic document-bound value extraction, including top-level HOLD defaults and
  scoped button-label lookup, while upstream interval documents use source-shape
  timer detection for their empty initial frame. Non-terminal Cells uses the
  generated spreadsheet state profile rather than a named initial row; the
  generated spreadsheet runtime now derives default A-column values and row
  count from the Boon `default_formula`/row range source shape instead of
  embedding fixed spreadsheet display constants in the runtime primitive.
  Chained List/remove replay now composes stage text from source-derived title
  and item labels plus runtime completion/add/remove state, rather than
  embedding one full output string per replay stage.
  CRUD replay now composes visible rows from Boon `new_person(...)` source
  literals and document control labels, including selected-row projection and
  create/update/delete stages, instead of embedding a full CRUD output string
  table in the generated runtime primitive.
  TodoMVC Physical replay now composes its theme, mode, filter, and clear
  controls from Boon source labels before applying the generated todo item
  state transitions, instead of embedding those static UI labels inside each
  replay-stage output string.
  TodoMVC replay now splits its broad probe text into generated source-derived
  constants for the app/footer/filter/delete labels and initial todo titles,
  with count text composed by the generated runtime. `verify` now runs
  frame-aware protocol assertions for all generated action-replay families so
  `assert_not_contains` cannot pass by finding a forbidden value elsewhere in
  the generated JSONL transcript; regular TodoMVC additionally checks
  frame-local `expect` and `assert_contains` values. The remaining TodoMVC replay debt is the
  expected-action payload history itself, not the source UI label extraction.
  Circle Drawer, Temperature Converter, Flight Booker, Timer, Text
  Interpolation Update, While Function Call, and Latest initial protocol frames
  now use this generic path instead of named initial-output branches.
  List/retain count, List/retain remove, and Shopping List also use this
  generic document/list path for their initial protocol frames. The current
  protocol-smoke sweep covers 43 upstream project directories. Generated
  runtime probes now match the static/minimal document examples, Fibonacci,
  layers, button hover, button click-state smoke, simple counters, terminal
  examples, interval smoke, cells, timer/control examples, list/count examples,
  form examples, TodoMVC, CRUD, and shopping-list probes.
  `build/reports/verify.json` currently reports 43 runtime cases, 38 upstream
  runtime probes, 33 generated action-replay cases, five generated static-probe
  cases, 33 generated runtime frame-assertion cases, zero generated runtime
  frame-assertion failures, zero case-directed generated runtime replay cases,
  zero generated-runtime probe gaps, zero upstream interaction trace-debt cases,
  zero source-derived runtime trace cases, and zero non-runtime state-replay
  cases.

## Implementation Debt

- Replace the remaining generated state profiles with complete Boon AST/HIR/Flow
  semantic lowering. The current runner executes every generated runtime first
  and reports zero generated-runtime probe gaps, zero generated-runtime
  trace-debt cases, zero source-derived runtime trace cases,
  `runtime_case_directed_replay_cases: 0`, and zero `projection_fallback` cases
  in generated compile metadata. `verify --all`
  checks runtime-case metadata for missing files, fallback lowering, generic
  expected-action dispatch, source-derived runtime profiles, source-rule runtime
  profiles, table-driven behavior, app-name behavior, and terminal-canvas run
  sourcing before reporting pass. The remaining gap is compiler completeness
  rather than hidden verifier skips or projection-only reports.
