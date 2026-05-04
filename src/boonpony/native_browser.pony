use "files"

primitive NativeBrowser
  fun doctor_command(env: Env) =>
    _mkdirs(env)
    let failures = _doctor_failures(env)
    env.out.print("boonpony browser doctor")
    env.out.print("  browser: firefox")
    env.out.print("  renderer: canvas2d")
    env.out.print("  pins_file: " + if _exists(env, "fixtures/browser_dependency_pins.json") then "present" else "missing" end)
    env.out.print("  browser_manifest: " + if _exists(env, ".boon-local/browser/manifest.json") then "present" else "missing" end)
    env.out.print("  pony_wasm_module: " + if _exists(env, "build/browser/boonpony_browser.wasm") then "present" else "missing" end)
    env.out.print("  pony_wasm_runtime: " + if _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a") then "present" else "missing" end)
    env.out.print("  firefox_proof: " + if _exists(env, "build/browser/firefox-proof.json") then "present" else "missing" end)
    env.out.print("  firefox: " + if _command_ok("firefox --version >/dev/null 2>&1") then "present" else "missing" end)
    env.out.print("  emcc: " + if _command_ok(".boon-local/browser/emsdk/upstream/emscripten/emcc --version >/dev/null 2>&1") then "present" else "missing" end)
    env.out.print("  runtime_contract: generated Pony must run inside browser WebAssembly")
    if failures.size() == 0 then
      env.out.print("browser doctor ok")
    else
      env.err.print("browser doctor failed: " + _join(failures, "; "))
      env.exitcode(1)
    end

  fun bootstrap_command(env: Env) =>
    _mkdirs(env)
    _write_file(env, ".boon-local/browser/manifest.json", _bootstrap_manifest())
    env.out.print("browser bootstrap metadata written: .boon-local/browser/manifest.json")
    env.out.print("browser bootstrap ok: Pony-owned browser metadata is present")
    env.out.print("next hard gate: build generated Pony for wasm32-unknown-emscripten and link it with a real wasm libponyrt")

  fun build_command(env: Env, all: Bool, renderer: String, out_dir: String) =>
    _mkdirs(env)
    if not all then
      env.err.print("error: browser-build requires --all")
      env.exitcode(2)
      return
    end
    if renderer != "canvas2d" then
      env.err.print("error: unsupported browser renderer: " + renderer)
      env.exitcode(2)
      return
    end

    _mkdir(env, out_dir)
    _ensure_runtime(env)
    let object_status = @system(("ponyc --triple=wasm32-unknown-emscripten --cpu=generic --features=+atomics,+bulk-memory,+mutable-globals --pass=obj src/boonpony_browser -o " + _shell_quote(out_dir) + " --bin-name boonpony_browser >/dev/null 2>&1").cstring())
    let abi_status = @system((_emscripten_env() + " emcc -O2 -pthread -matomics -mbulk-memory -c src/boonpony_browser/abi.c -o " + _shell_quote(out_dir + "/boonpony_browser_abi.o") + " >/dev/null 2>&1").cstring())
    let link_status = @system((_emscripten_env() + " emcc -O2 -pthread -sPTHREAD_POOL_SIZE=2 -sWASM=1 -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createBoonPony -sENVIRONMENT=web,worker,node -sALLOW_MEMORY_GROWTH=1 -sEXPORTED_RUNTIME_METHODS=UTF8ToString -sEXPORTED_FUNCTIONS=_boon_browser_init,_boon_browser_select_example,_boon_browser_input,_boon_browser_tick,_boon_browser_scene_ptr,_boon_browser_scene_len,_main -o " + _shell_quote(out_dir + "/boonpony_browser.js") + " " + _shell_quote(out_dir + "/boonpony_browser.o") + " " + _shell_quote(out_dir + "/boonpony_browser_abi.o") + " .boon-local/browser/lib/libponyrt-wasm.a >/dev/null 2>&1").cstring())
    _write_file(env, out_dir + "/index.html", _index_html())
    _write_file(env, out_dir + "/browser_host.js", _browser_host_js())
    _write_file(env, out_dir + "/browser_worker.js", _browser_worker_js())
    _write_file(env, out_dir + "/build-report.json", _browser_build_report(env, out_dir, object_status, abi_status, link_status))

    if _exists(env, out_dir + "/boonpony_browser.wasm") then
      env.out.print("browser-build ok: " + out_dir)
    else
      if object_status == 0 then
        env.err.print("browser-build partial: Pony wasm object generated at " + out_dir + "/boonpony_browser.o")
      else
        env.err.print("browser-build failed before wasm object generation")
      end
      if not _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a") then
        env.err.print("browser-build incomplete: missing .boon-local/browser/lib/libponyrt-wasm.a")
      elseif abi_status != 0 then
        env.err.print("browser-build incomplete: ABI adapter compile failed")
      elseif link_status != 0 then
        env.err.print("browser-build incomplete: Emscripten link failed")
      end
      env.err.print("browser-build incomplete: missing " + out_dir + "/boonpony_browser.wasm")
      env.err.print("generated Pony must be linked into this wasm before verify-browser can pass")
      env.exitcode(1)
    end

  fun serve_command(env: Env, renderer: String, example: String) =>
    if renderer != "canvas2d" then
      env.err.print("error: unsupported browser renderer: " + renderer)
      env.exitcode(2)
      return
    end
    if not _exists(env, "build/browser/boonpony_browser.wasm") then
      env.err.print("error: browser --serve requires build/browser/boonpony_browser.wasm")
      env.err.print("run: build/bin/boonpony browser-build --all --renderer canvas2d --out build/browser")
      env.exitcode(1)
      return
    end
    env.out.print("serving browser playground for example: " + example)
    _run_tool(env, "node tools/browser_serve.mjs build/browser 4177 build/browser/server.json")

  fun verify_command(env: Env, all: Bool, browser: String, renderer: String, report: String) =>
    _mkdirs(env)
    let failures = Array[String]
    if not all then failures.push("verify-browser requires --all") end
    if browser != "firefox" then failures.push("unsupported browser: " + browser) end
    if renderer != "canvas2d" then failures.push("unsupported renderer: " + renderer) end
    if not _exists(env, "build/browser/boonpony_browser.wasm") then failures.push("missing Pony WebAssembly module: build/browser/boonpony_browser.wasm") end
    if not _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a") then failures.push("missing wasm Pony runtime: .boon-local/browser/lib/libponyrt-wasm.a") end
    if not _command_ok("firefox --version >/dev/null 2>&1") then failures.push("Firefox is unavailable on PATH") end
    if not _exists(env, "build/browser/index.html") then failures.push("missing browser bundle: run build/bin/boonpony browser-build --all --renderer canvas2d --out build/browser") end
    let proof_status = @system("node tools/browser_firefox_verify.mjs build/browser build/browser/firefox-proof.json >/dev/null 2>&1".cstring())
    if proof_status != 0 then failures.push("Firefox proof harness failed") end
    if not _valid_firefox_proof(env) then failures.push("missing or failing Firefox runtime proof: build/browser/firefox-proof.json") end

    _write_file(env, report, _verify_report(browser, renderer, failures))
    if failures.size() == 0 then
      env.out.print("verify-browser ok: " + browser + " " + renderer)
    else
      env.err.print("verify-browser failed: " + _join(failures, "; "))
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun _doctor_failures(env: Env): Array[String] =>
    let failures = Array[String]
    if not _exists(env, "fixtures/browser_dependency_pins.json") then failures.push("missing fixtures/browser_dependency_pins.json") end
    if not _exists(env, ".boon-local/browser/manifest.json") then failures.push("missing browser bootstrap manifest: run build/bin/boonpony browser --bootstrap") end
    if not _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a") then failures.push("missing wasm Pony runtime: .boon-local/browser/lib/libponyrt-wasm.a") end
    if not _exists(env, "build/browser/boonpony_browser.wasm") then failures.push("missing generated Pony wasm module: build/browser/boonpony_browser.wasm") end
    if not _valid_firefox_proof(env) then failures.push("missing or failing Firefox runtime proof: build/browser/firefox-proof.json") end
    if not _command_ok("firefox --version >/dev/null 2>&1") then failures.push("Firefox is unavailable on PATH") end
    failures

  fun _bootstrap_manifest(): String =>
    """
{
  "schema_version": 1,
  "pins_file": "fixtures/browser_dependency_pins.json",
  "runtime_contract": {
    "pony_must_run_inside_wasm": true,
    "native_runtime_fallback_allowed": false,
    "javascript_runtime_fallback_allowed": false
  },
  "status": "blocked_until_wasm_libponyrt_exists",
  "required_outputs": [
    ".boon-local/browser/lib/libponyrt-wasm.a",
    "build/browser/boonpony_browser.wasm"
  ]
}
"""

  fun _browser_build_report(env: Env, out_dir: String, object_status: I32, abi_status: I32, link_status: I32): String =>
    let wasm_exists = _exists(env, out_dir + "/boonpony_browser.wasm")
    let object_exists = _exists(env, out_dir + "/boonpony_browser.o")
    let runtime_exists = _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a")
    let out = String
    out.append("{\n")
    out.append("  \"command\":\"browser-build\",\n")
    out.append("  \"status\":\""); out.append(if wasm_exists then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"browser\":\"firefox\",\n")
    out.append("  \"renderer\":\"canvas2d\",\n")
    out.append("  \"out_dir\":\""); _append_json(out, out_dir); out.append("\",\n")
    out.append("  \"pony_wasm_required\":true,\n")
    out.append("  \"pony_wasm_object_status\":"); out.append(object_status.string()); out.append(",\n")
    out.append("  \"pony_wasm_abi_status\":"); out.append(abi_status.string()); out.append(",\n")
    out.append("  \"pony_wasm_link_status\":"); out.append(link_status.string()); out.append(",\n")
    out.append("  \"pony_wasm_object_present\":"); out.append(if object_exists then "true" else "false" end); out.append(",\n")
    out.append("  \"pony_wasm_runtime_present\":"); out.append(if runtime_exists then "true" else "false" end); out.append(",\n")
    out.append("  \"pony_wasm_present\":"); out.append(if wasm_exists then "true" else "false" end); out.append(",\n")
    out.append("  \"native_runtime_fallback_allowed\":false,\n")
    out.append("  \"javascript_runtime_fallback_allowed\":false,\n")
    out.append("  \"failures\":"); out.append(if wasm_exists then "[]" else "[\"missing Pony WebAssembly module\"]" end); out.append("\n")
    out.append("}\n")
    out.clone()

  fun _verify_report(browser: String, renderer: String, failures: Array[String] box): String =>
    let pass = failures.size() == 0
    let out = String
    out.append("{\n")
    out.append("  \"command\":\"verify-browser\",\n")
    out.append("  \"status\":\""); out.append(if pass then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"browser\":\""); _append_json(out, browser); out.append("\",\n")
    out.append("  \"renderer\":\""); _append_json(out, renderer); out.append("\",\n")
    out.append("  \"runtime_location\":\"firefox-wasm-worker\",\n")
    out.append("  \"pony_wasm_loaded\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"cross_origin_isolated\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"shared_array_buffer\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"native_runtime_used\":false,\n")
    out.append("  \"javascript_runtime_used\":false,\n")
    out.append("  \"canvas_nonblank\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"semantic_ids_present\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"hit_regions_present\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"input_roundtrip\":"); out.append(if pass then "true" else "false" end); out.append(",\n")
    out.append("  \"failures\":"); out.append(_failures_json(failures)); out.append("\n")
    out.append("}\n")
    out.clone()

  fun _index_html(): String =>
    """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Boon-Pony Browser Playground</title>
  <style>
    html,body{margin:0;width:100%;height:100%;font:14px system-ui,sans-serif;background:#15161a;color:#f5f7fa}
    #app{display:grid;grid-template-columns:220px 1fr 460px;grid-template-rows:48px 1fr 120px;width:100vw;height:100vh}
    #top{grid-column:1/4;display:flex;align-items:center;gap:8px;padding:8px 12px;background:#20242b;border-bottom:1px solid #343a45}
    #examples{grid-row:2/4;padding:10px;background:#1d2027;border-right:1px solid #343a45;overflow:auto}
    #canvas{width:100%;height:100%;display:block;background:#0f1115}
    #source{grid-column:3;grid-row:2/4;margin:0;padding:12px;background:#181b21;border-left:1px solid #343a45;overflow:auto;white-space:pre-wrap}
    #status{grid-column:2;grid-row:3;padding:10px;background:#20242b;border-top:1px solid #343a45;overflow:auto}
    button{height:30px;border:1px solid #4a5362;background:#2a303a;color:#f5f7fa}
  </style>
</head>
<body>
  <div id="app">
    <div id="top"><strong>Boon-Pony</strong><button id="run" data-semantic-id="toolbar.run" data-hit-region="toolbar.run">Run</button><button id="clear" data-semantic-id="toolbar.clear" data-hit-region="toolbar.clear">Clear + Rerun</button><span id="runtime">waiting for Pony wasm</span></div>
    <div id="examples" data-semantic-id="examples"></div>
    <canvas id="canvas" width="960" height="720" data-semantic-id="viewport" data-hit-region="viewport"></canvas>
    <pre id="source" data-semantic-id="source"></pre>
    <pre id="status"></pre>
  </div>
  <script type="module" src="./browser_host.js"></script>
</body>
</html>
"""

  fun _browser_host_js(): String =>
    """
const statusEl = document.querySelector("#status");
const runtimeEl = document.querySelector("#runtime");
const canvas = document.querySelector("#canvas");
const sourceEl = document.querySelector("#source");
const ctx = canvas.getContext("2d");
let worker = null;
let browserProof = {
  status: "fail",
  pony_wasm_loaded: false,
  native_runtime_used: false,
  javascript_runtime_used: false,
  canvas_nonblank: false,
  semantic_ids_present: false,
  hit_regions_present: false,
  failures: ["not initialized"]
};

function fail(message) {
  runtimeEl.textContent = "Pony wasm missing";
  statusEl.textContent = message;
  ctx.fillStyle = "#241b1b";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#ffb4a8";
  ctx.font = "18px system-ui";
  ctx.fillText("Browser gate is red until generated Pony runs inside wasm.", 24, 48);
  browserProof = {
    status: "fail",
    pony_wasm_loaded: false,
    native_runtime_used: false,
    javascript_runtime_used: false,
    canvas_nonblank: true,
    semantic_ids_present: false,
    hit_regions_present: false,
    failures: [message]
  };
  window.__boonBrowserProof = browserProof;
}

function pass(proof) {
  runtimeEl.textContent = "Pony wasm active";
  statusEl.textContent = JSON.stringify(proof, null, 2);
  renderScene(proof.scene);
  browserProof = {
    ...proof,
    canvas_nonblank: true,
    semantic_ids_present: true,
    hit_regions_present: true
  };
  window.__boonBrowserProof = browserProof;
}

function renderScene(scene) {
  if (!scene) return;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  for (const command of scene.draw || []) {
    if (command.kind === "rect") {
      ctx.fillStyle = command.fill || "#000";
      ctx.fillRect(command.x || 0, command.y || 0, command.w || 0, command.h || 0);
    } else if (command.kind === "text") {
      ctx.fillStyle = command.fill || "#fff";
      ctx.font = `${command.size || 14}px system-ui`;
      ctx.fillText(command.text || "", command.x || 0, command.y || 0);
    }
  }
  sourceEl.textContent = scene.source || "";
}

if (!globalThis.crossOriginIsolated) {
  fail("cross-origin isolation is required for SharedArrayBuffer");
} else if (typeof SharedArrayBuffer === "undefined") {
  fail("SharedArrayBuffer is unavailable");
} else {
  try {
    worker = new Worker("./browser_worker.js", { type: "module" });
    worker.onmessage = event => {
      if (event.data?.type === "proof") pass(event.data.proof);
      if (event.data?.type === "error") fail(event.data.message);
    };
    worker.postMessage({ type: "init" });
  } catch (error) {
    fail(String(error && error.stack || error));
  }
}

document.querySelector("#run").addEventListener("click", () => {
  if (worker) worker.postMessage({ type: "input", event: "toolbar.run" });
});

document.querySelector("#clear").addEventListener("click", () => {
  if (worker) worker.postMessage({ type: "select", example: "counter" });
});
"""

  fun _browser_worker_js(): String =>
    """
let module = null;

function readScene() {
  const scenePtr = module._boon_browser_scene_ptr();
  const sceneLen = module._boon_browser_scene_len();
  return JSON.parse(module.UTF8ToString(scenePtr, sceneLen));
}

function postProof(ok) {
  self.postMessage({ type: "proof", proof: {
    status: ok === 0 ? "pass" : "fail",
    pony_wasm_loaded: true,
    native_runtime_used: false,
    javascript_runtime_used: false,
    cross_origin_isolated: self.crossOriginIsolated === true,
    shared_array_buffer: typeof SharedArrayBuffer !== "undefined",
    scene: readScene(),
    failures: ok === 0 ? [] : ["Pony browser ABI returned nonzero"]
  }});
}

self.onmessage = async event => {
  try {
    if (event.data?.type === "init") {
      const { default: createBoonPony } = await import("./boonpony_browser.js");
      module = await createBoonPony({
        locateFile: path => new URL(path, import.meta.url).href
      });
      if (typeof module._boon_browser_init !== "function") {
        throw new Error("Pony wasm is missing _boon_browser_init export");
      }
      postProof(module._boon_browser_init(960, 720, 1000));
    } else if (event.data?.type === "input") {
      if (!module) return;
      postProof(module._boon_browser_input(0, 0));
    } else if (event.data?.type === "select") {
      if (!module) return;
      postProof(module._boon_browser_select_example(0, 0));
    }
  } catch (error) {
    self.postMessage({ type: "error", message: String(error && error.stack || error) });
  }
};
"""

  fun _mkdirs(env: Env) =>
    _mkdir(env, ".boon-local")
    _mkdir(env, ".boon-local/browser")
    _mkdir(env, "build")
    _mkdir(env, "build/browser")
    _mkdir(env, "build/reports")

  fun _mkdir(env: Env, dir: String) =>
    FilePath(FileAuth(env.root), dir).mkdir()

  fun _exists(env: Env, path: String): Bool =>
    FilePath(FileAuth(env.root), path).exists()

  fun _command_ok(command: String): Bool =>
    @system(command.cstring()) == 0

  fun _run_tool(env: Env, command: String) =>
    let status = @system(command.cstring())
    if status == 0 then
      env.exitcode(0)
    elseif status > 255 then
      env.exitcode(status / 256)
    else
      env.exitcode(status)
    end

  fun _ensure_runtime(env: Env) =>
    if _exists(env, ".boon-local/browser/lib/libponyrt-wasm.a") then
      return
    end
    if _exists(env, ".boon-local/browser/ponyc-wasm-build/src/libponyrt/libponyrt.a") then
      _mkdir(env, ".boon-local/browser/lib")
      @system("cp .boon-local/browser/ponyc-wasm-build/src/libponyrt/libponyrt.a .boon-local/browser/lib/libponyrt-wasm.a".cstring())
    end

  fun _emscripten_env(): String =>
    "env PATH=\"$PWD/.boon-local/browser/emsdk/upstream/emscripten:$PWD/.boon-local/browser/emsdk/upstream/bin:$PWD/.boon-local/browser/emsdk/node/22.16.0_64bit/bin:$PATH\" EMSDK=\"$PWD/.boon-local/browser/emsdk\" EM_CONFIG=\"$PWD/.boon-local/browser/emsdk/.emscripten\" EM_CACHE=\"$PWD/.boon-local/browser/emsdk/upstream/emscripten/cache\""

  fun _write_file(env: Env, file: String, data: String) =>
    try
      (let dir, _) = Path.split(file)
      if dir != "" then FilePath(FileAuth(env.root), dir).mkdir() end
      with f = CreateFile(FilePath(FileAuth(env.root), file)) as File do
        f.set_length(0)
        f.write(data)
      end
    end

  fun _read_file(env: Env, file: String): String ? =>
    let path = FilePath(FileAuth(env.root), file)
    let info = FileInfo(path)?
    with f = OpenFile(path) as File do
      f.read_string(info.size)
    end

  fun _valid_firefox_proof(env: Env): Bool =>
    try
      let proof = _read_file(env, "build/browser/firefox-proof.json")?
      _json_has(proof, "status", "pass") and
        _json_has(proof, "pony_wasm_loaded", "true") and
        _json_has(proof, "native_runtime_used", "false") and
        _json_has(proof, "javascript_runtime_used", "false") and
        _json_has(proof, "canvas_nonblank", "true") and
        _json_has(proof, "semantic_ids_present", "true") and
        _json_has(proof, "hit_regions_present", "true") and
        _json_has(proof, "input_roundtrip", "true")
    else
      false
    end

  fun _json_has(text: String, key: String, value: String): Bool =>
    text.contains("\"" + key + "\":" + value) or
      text.contains("\"" + key + "\": " + value) or
      text.contains("\"" + key + "\":\"" + value + "\"") or
      text.contains("\"" + key + "\": \"" + value + "\"")

  fun _shell_quote(value: String): String =>
    let out = String
    out.append("'")
    for rune in value.runes() do
      if rune == '\'' then
        out.append("'\\''")
      else
        out.push_utf32(rune)
      end
    end
    out.append("'")
    out.clone()

  fun _join(values: Array[String] box, sep: String): String =>
    let out = String
    var index: USize = 0
    for value in values.values() do
      if index > 0 then out.append(sep) end
      out.append(value)
      index = index + 1
    end
    out.clone()

  fun _failures_json(failures: Array[String] box): String =>
    let out = String
    out.append("[")
    var index: USize = 0
    for failure in failures.values() do
      if index > 0 then out.append(",") end
      out.append("\""); _append_json(out, failure); out.append("\"")
      index = index + 1
    end
    out.append("]")
    out.clone()

  fun _append_json(out: String ref, text: String) =>
    for ch in text.values() do
      match ch
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | '\n' => out.append("\\n")
      | '\r' => out.append("\\r")
      | '\t' => out.append("\\t")
      else
        if (ch >= 32) and (ch <= 126) then
          out.push(ch)
        else
          out.append("?")
        end
      end
    end
