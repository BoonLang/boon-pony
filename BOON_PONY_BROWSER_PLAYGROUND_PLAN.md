# Boon-Pony Browser Playground Addendum

`BOON_PONY_TUI_PLAN.md` remains the authoritative implementation contract.
This addendum adds a Firefox browser playground target without weakening the
terminal TUI, generated runtime, SOURCE, or no-fake-pass requirements.

## 1. Goal

Deliver a working graphical Boon playground in Firefox.

The preferred browser runtime is generated Pony code compiled to WebAssembly.
The first renderer is Canvas2D because it can consume the existing
renderer-neutral `GuiScene` draw-command and hit-region model with minimal
JavaScript glue.

If Pony WebAssembly is blocked, browser verification must fail with a concrete
runtime-port diagnostic. Do not replace generated Pony behavior with JavaScript
or a native/server runtime and call the browser gate complete.

## 2. References

- Existing scene and SDL3 addendum: `BOON_PONY_NATIVE_GUI_PLAN.md`
- MoonZoon worker and shared-memory patterns:
  - `/home/martinkavik/repos/MoonZoon/crates/moon/src/lib.rs`
  - `/home/martinkavik/repos/MoonZoon/crates/zoon/src/task.rs`
  - `/home/martinkavik/repos/MoonZoon/crates/zoon/src/task/worker_script.js`
  - `/home/martinkavik/repos/MoonZoon/crates/mzoon/src/build_frontend.rs`
- Boon Rust Firefox harness and WebGPU/WESL references:
  - `/home/martinkavik/repos/boon-rust/crates/boon_backend_browser/src/lib.rs`
  - `/home/martinkavik/repos/boon-rust/shaders/`

## 3. Browser CLI Contract

Add:

```bash
build/bin/boonpony browser --bootstrap
build/bin/boonpony browser --doctor
build/bin/boonpony browser-build --all --renderer canvas2d --out build/browser
build/bin/boonpony browser --serve --renderer canvas2d --example todo_mvc
build/bin/boonpony verify-browser --all --browser firefox --renderer canvas2d --report build/reports/verify-browser-firefox.json
```

Browser dependency bootstrap is owned by the Pony CLI. Do not add shell scripts
as the primary implementation path. Small JS files are allowed only as browser
loader/rendering glue.

`browser --doctor` reports local browser dependency state and the current Pony
WebAssembly blocker if one remains.

`browser-build` writes a static playground bundle under `build/browser`. A build
is not a browser pass unless the bundle includes a Pony-origin WebAssembly module
and the verification report proves it was loaded in Firefox.

`verify-browser` is the hard gate. It must fail if:

- the Pony WebAssembly runtime is missing,
- shared memory or cross-origin isolation is unavailable,
- Firefox cannot load the playground,
- Canvas2D is blank,
- semantic IDs or hit regions are missing,
- app behavior is handled by JavaScript or a native/server fallback.

## 4. Runtime And Renderer Contract

The browser host uses a single Pony-owned scene model:

- viewport
- draw commands
- hit regions with source paths and action names
- semantic IDs
- source panel metadata
- diagnostics
- metrics

The JavaScript host may:

- load the WebAssembly module,
- create a worker,
- forward browser input as serialized events,
- draw `GuiScene` commands to Canvas2D,
- collect verification proof.

The JavaScript host must not:

- own TodoMVC, Counter, Cells, Pong, Arkanoid, or 7GUI state,
- synthesize example-specific rendered frames,
- parse Boon source,
- claim browser readiness from native process output.

## 5. WebAssembly Port Shape

Use an Emscripten/pthreads browser target first. The implementation must mirror
the MoonZoon shared-memory pattern where useful:

- build with atomics, bulk memory, and mutable globals enabled,
- serve with `Cross-Origin-Opener-Policy: same-origin`,
- serve with `Cross-Origin-Embedder-Policy: require-corp`,
- run runtime work inside a browser worker,
- pass a shared module and memory to workers when the toolchain requires it.

Minimum exported ABI:

```text
boon_browser_init(width, height, scale_milli) -> status
boon_browser_select_example(ptr, len) -> status
boon_browser_input(ptr, len) -> status
boon_browser_tick(delta_ms) -> status
boon_browser_scene_ptr() -> ptr
boon_browser_scene_len() -> len
```

Unsupported Pony stdlib surfaces such as files, process spawning, sockets, and
signals must produce explicit diagnostics in browser reports.

## 6. Verification Gates

Existing gates must remain green:

```bash
ponyc src/boonpony -o build/bin
build/bin/boonpony verify-gui --all --backend headless --report build/reports/verify-gui-headless.json
```

New browser gates:

```bash
build/bin/boonpony browser --doctor
build/bin/boonpony browser --bootstrap
build/bin/boonpony browser-build --all --renderer canvas2d --out build/browser
build/bin/boonpony verify-browser --all --browser firefox --renderer canvas2d --report build/reports/verify-browser-firefox.json
```

The verification report must include:

```json
{
  "command": "verify-browser",
  "status": "pass|fail",
  "browser": "firefox",
  "renderer": "canvas2d",
  "runtime_location": "firefox-wasm-worker",
  "pony_wasm_loaded": true,
  "cross_origin_isolated": true,
  "shared_array_buffer": true,
  "native_runtime_used": false,
  "javascript_runtime_used": false,
  "canvas_nonblank": true,
  "semantic_ids_present": true,
  "hit_regions_present": true,
  "failures": []
}
```

No browser report may pass with `pony_wasm_loaded:false`,
`native_runtime_used:true`, or `javascript_runtime_used:true`.
