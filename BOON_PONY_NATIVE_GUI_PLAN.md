# Boon-Pony Native GUI Playground Addendum

`BOON_PONY_TUI_PLAN.md` remains the authoritative implementation contract.
This addendum starts only after the terminal TUI/runtime gates are still green.

## 1. Renderer Decision

Use a Pony-owned, renderer-neutral graphical scene model and an SDL3 native
backend through a small C bridge.

Do not make `boon-pony` depend on Rust, Zig, Raybox, Sokol, raylib, Dawn, or
wgpu-native runtime code. `boon-rust`, `boon-zig`, and `raybox-zig` are design
references only.

Reference comparison:

- `boon-rust`: `app_window` + `wgpu` + `glyphon` + WESL/`wgsl_bindgen`.
  Good reference for renderer-neutral verification and future WebGPU work.
- `boon-zig`: browser/DOM playground and local compile fallback.
  Good reference for SOURCE semantics and browser host boundaries.
- `raybox-zig`: SDL3 native window/input/timing, SDL3 renderer API,
  CPU-generated 2D geometry, font atlas text, and Emscripten browser canvas.
  This is the closest native GUI shape for Pony.

## 2. CLI Contract

Add:

```bash
build/bin/boonpony gui
build/bin/boonpony gui --doctor
build/bin/boonpony gui --example todo_mvc
build/bin/boonpony gui --script tests/examples/gui_playground_sequence.json
build/bin/boonpony gui --backend headless --report build/reports/gui-playground.json
build/bin/boonpony verify-gui --all --backend headless --report build/reports/verify-gui-headless.json
build/bin/boonpony verify-gui --all --backend sdl3 --report build/reports/verify-gui-sdl3.json
```

`gui` without `--backend` targets the native SDL3 backend for interactive use.
`gui --script` defaults to the headless backend so verification can run on
machines without a display.

SDL3 verification must prefer repo-local project dependencies under
`.boon-local/gui`. System SDL3/SDL_ttf may only be used when
`BOON_PONY_USE_SYSTEM_SDL3=1` is set explicitly for local experiments.

## 2A. Repo-Local GUI Dependencies

Pinned dependency metadata lives in:

```bash
fixtures/gui_dependency_pins.json
```

Bootstrap command:

```bash
tools/bootstrap_gui_deps.sh
tools/bootstrap_gui_deps.sh --check
```

The bootstrap installs project-specific artifacts under `.boon-local/gui/`:

- SDL3
- SDL_ttf
- GUI fonts
- pinned vendored FreeType needed by SDL_ttf
- C smoke bridge used by `verify-gui --backend sdl3`

`.boon-local/` is generated output and must stay ignored. Global tools such as
`ponyc`, `ponyup`, `cmake`, `ninja`, `pkg-config`, `cc`, `git`, and shell
utilities remain normal developer prerequisites.

`verify-gui --backend sdl3` proves the renderer-neutral scene plus local SDL3,
SDL_ttf, fonts, and C smoke bridge. It must report dependency mode
(`repo-local`, `system-explicit`, or missing) and must not claim the full native
SDL window path is complete until a real Pony-to-SDL window bridge is built and
verified.

## 3. Scene Contract

The Pony runtime owns the GUI scene:

- viewport width, height, and scale
- draw commands for rects, borders, text, clips, carets, and scrollbars
- hit regions with stable semantic IDs and action names
- normalized input events
- semantic tree IDs matching generated protocol/source slots
- source file path and source scroll metadata

The SDL bridge must only consume this scene and return input events. It must
not contain Boon example business logic.

## 4. Playground Behavior

The GUI host reuses generated Pony protocol children from the terminal TUI
repair work. The GUI layer may translate pointer/key/text input into generated
protocol actions, but TodoMVC, Counter, Interval, Cells, Pong, and Arkanoid
state must remain generated-runtime behavior.

Native layout:

- left example list
- center preview
- right Boon source viewer with independent scroll
- top Run/Rerun and Clear State + Rerun commands
- bottom collapsible diagnostics/semantic/perf panel

## 5. Verification Gates

Existing terminal gates must continue to pass:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony verify-pty --all --report build/reports/verify-pty.json
build/bin/boonpony tui --script tests/examples/terminal_playground_sequence.json
build/bin/boonpony verify-terminal --all --report build/reports/verify-terminal.json
```

New GUI gates:

```bash
build/bin/boonpony gui --script tests/examples/gui_playground_sequence.json --report build/reports/gui-playground.json
build/bin/boonpony verify-gui --all --backend headless --report build/reports/verify-gui-headless.json
build/bin/boonpony verify-gui --all --backend sdl3 --report build/reports/verify-gui-sdl3.json
```

The headless GUI gate must fail on empty scenes, missing hit regions, missing
semantic IDs, missing source paths, or missing generated-protocol linkage.

The SDL3 gate must fail explicitly when SDL3 or the C bridge is unavailable.
It must not report success from a terminal transcript or a headless-only frame.

## 6. Browser Future

When Pony wasm is viable, compile the same runtime/scene producer to wasm and
let a browser host consume the same scene and input protocol. The first browser
renderer may use Canvas2D or WebGPU, but it must preserve the same scene and
semantic verification artifacts.
