# Boon-Pony Playground Rework Plan

`BOON_PONY_TUI_PLAN.md` remains the authoritative implementation contract. This plan is a focused repair plan for the playground quality and runtime separation issues found after the first completion pass.

## Goal

Make `build/bin/boonpony tui` useful for checking the new Pony Boon runtime:

- the active tab shows a generated runtime preview, not host-written example logic
- the active tab shows the corresponding Boon source in a compact side panel
- the HUD is short and action-oriented
- TodoMVC, Pong, and the 7GUIs examples are driven through generated Pony protocol children
- host Pony playground code only multiplexes tabs, input, source editing, reports, and terminal safety

## Non-Negotiable Rules

- `BOON_PONY_TUI_PLAN.md` is still the source of truth.
- Do not add host-side business state for individual examples in `native_playground.pony`.
- Do not reimplement TodoMVC, Pong, Cells, Counter, Interval, or 7GUIs behavior in playground host code.
- The playground may translate terminal input into generated protocol actions, but the generated child app must own behavior and render frames.
- Keep `SOURCE` canonical and reject legacy `LINK` where the main plan requires it.
- Do not run git-mutating commands unless the user explicitly asks.

## Phase 1 - Playground Shell

- Replace handwritten preview state in `PlaygroundNotify` with host-only state:
  - active tab
  - source-edit status
  - source scroll/edit diagnostics
  - child protocol histories
  - terminal/session summary counters
- Render a compact screen:
  - one-line title
  - tabs
  - active control hint
  - generated child preview
  - active Boon source panel
  - concise status line
- Keep source visible whenever an example tab is selected.

Acceptance:

```sh
ponyc src/boonpony -o build/bin
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
```

## Phase 2 - Generated Child Interaction

- Use generated protocol children for every preview frame.
- Keep cumulative per-tab event history so repeated events replay deterministically.
- Translate host terminal inputs into expected protocol actions only.
- Add a guard that fails if playground host code regains example-specific business state.

Acceptance:

```sh
build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json
rg "_todo_|_pong_|_counter:|_interval:|render_pong_tick|render_interval_tick|advance_pong|Pong - playable preview" src/boonpony/native_playground.pony
```

The `rg` command must return no host-business matches.

## Phase 3 - TodoMVC Runtime Behavior

- TodoMVC must be a Boon source shown in the source panel.
- Generated Pony runtime must handle:
  - adding more than five todos
  - preserving input focus after Enter
  - toggling items without mouse-up undo
  - editing and deleting without moving edit mode to another item
  - filter controls
  - toggle-all and clear-completed controls
  - scrolling or bounded rendering for long lists
- Any shortcut used by the playground should map to protocol actions, not local host state.

Acceptance:

```sh
build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
```

## Phase 4 - Pong Runtime Behavior

- Pong must be generated from `examples/terminal/pong/pong.bn`.
- The generated runtime owns:
  - ball position
  - wall and paddle bouncing
  - player paddle input
  - AI paddle movement
  - score/hit updates
  - animation frames
- Holding movement keys must not wedge terminal input.

Acceptance:

```sh
build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json
```

## Phase 5 - Final Gate

Run the relevant final contract gates from `BOON_PONY_TUI_PLAN.md`:

```sh
ponyc src/boonpony -o build/bin
build/bin/boonpony manifest --check
build/bin/boonpony verify-parser --corpus fixtures/corpus_manifest.json
build/bin/boonpony verify-source-shape --all
build/bin/boonpony verify --all --report build/reports/verify.json
build/bin/boonpony verify-terminal --all --report build/reports/verify-terminal.json
build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
build/bin/boonpony bench --all --report build/reports/bench.json
```

The project is not done unless the final gate passes and the playground can be honestly used as an interactive generated-runtime checker.
