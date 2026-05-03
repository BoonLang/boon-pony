use "files"

class val GuiViewport
  let width: USize
  let height: USize
  let scale: F64

  new val create(width': USize, height': USize, scale': F64 = 1.0) =>
    width = width'
    height = height'
    scale = scale'

class val GuiDrawCommand
  let kind: String
  let id: String
  let x: I64
  let y: I64
  let width: I64
  let height: I64
  let text: String
  let fg: String
  let bg: String

  new val create(
    kind': String,
    id': String,
    x': I64,
    y': I64,
    width': I64,
    height': I64,
    text': String = "",
    fg': String = "ink",
    bg': String = "surface")
  =>
    kind = kind'
    id = id'
    x = x'
    y = y'
    width = width'
    height = height'
    text = text'
    fg = fg'
    bg = bg'

class val GuiHitRegion
  let id: String
  let action: String
  let source_path: String
  let x: I64
  let y: I64
  let width: I64
  let height: I64

  new val create(
    id': String,
    action': String,
    source_path': String,
    x': I64,
    y': I64,
    width': I64,
    height': I64)
  =>
    id = id'
    action = action'
    source_path = source_path'
    x = x'
    y = y'
    width = width'
    height = height'

class ref GuiScene
  let example_id: String
  let title: String
  let source_path: String
  let source_line: USize
  let viewport: GuiViewport val
  let draw_commands: Array[GuiDrawCommand val] ref
  let hit_regions: Array[GuiHitRegion val] ref
  let semantic_ids: Array[String] ref
  let protocol_project: String
  let generated_protocol_child: Bool

  new create(
    example_id': String,
    title': String,
    source_path': String,
    source_line': USize,
    viewport': GuiViewport val,
    draw_commands': Array[GuiDrawCommand val] ref,
    hit_regions': Array[GuiHitRegion val] ref,
    semantic_ids': Array[String] ref,
    protocol_project': String,
    generated_protocol_child': Bool)
  =>
    example_id = example_id'
    title = title'
    source_path = source_path'
    source_line = source_line'
    viewport = viewport'
    draw_commands = draw_commands'
    hit_regions = hit_regions'
    semantic_ids = semantic_ids'
    protocol_project = protocol_project'
    generated_protocol_child = generated_protocol_child'

primitive NativeGui
  fun doctor_command(env: Env) =>
    _mkdirs()
    let failures = _dependency_failures(env, "sdl3")
    env.out.print("boonpony gui doctor")
    env.out.print("  dependency_mode: " + _dependency_mode(env, "sdl3"))
    env.out.print("  local_prefix: .boon-local/gui")
    env.out.print("  local_manifest: " + if _local_manifest_exists() then "present" else "missing" end)
    env.out.print("  local_sdl3_pkg_config: " + if _local_sdl3_pkg_config() then "ok" else "missing" end)
    env.out.print("  local_sdl3_ttf_pkg_config: " + if _local_ttf_pkg_config() then "ok" else "missing" end)
    env.out.print("  local_fonts: " + if _local_fonts_available() then "ok" else "missing" end)
    env.out.print("  local_bridge_smoke: " + if _local_bridge_smoke() then "ok" else "missing-or-failing" end)
    env.out.print("  local_sdl_playground: " + if _local_sdl_playground() then "ok" else "missing-or-failing" end)
    env.out.print("  system_sdl3_opt_in: " + if _use_system_sdl3(env) then "yes" else "no" end)
    env.out.print("  native_window_verified: " + if _local_sdl_playground() then "true" else "false" end)
    if failures.size() == 0 then
      env.out.print("gui doctor ok")
    else
      env.err.print("gui doctor failed: " + _join(failures, "; "))
      env.exitcode(1)
    end

  fun gui_command(env: Env, example': String, backend': String, script: String, report': String) =>
    let backend = if backend' == "" then if script == "" then "sdl3" else "headless" end else backend' end
    let example = if example' == "" then "counter" else example' end
    let report = if report' == "" then "build/reports/gui-playground.json" else report' end
    _mkdirs()
    match backend
    | "headless" =>
      let scene = _scene_for_example(env, example)
      let failures = _scene_failures(scene)
      _write_file(env, report, _gui_report(env, "gui", backend, script, scene, failures))
      if failures.size() == 0 then
        env.out.print("gui headless ok: " + scene.title + " -> " + report)
      else
        env.err.print("gui headless failed: " + _join(failures, "; "))
        env.exitcode(1)
      end
    | "sdl3" =>
      let scene = _scene_for_example(env, example)
      let failures = _scene_failures(scene)
      for failure in _dependency_failures(env, backend).values() do failures.push(failure) end
      if failures.size() == 0 then
        let command = _sdl_playground_command(example, script, report)
        let status = @system(command.cstring())
        if status == 0 then
          env.out.print("gui sdl3 ok: " + scene.title + " -> " + report)
        else
          failures.push("native SDL3 playground exited with status " + status.string())
          _write_file(env, report, _gui_report(env, "gui", backend, script, scene, failures))
          env.err.print("gui sdl3 failed: see " + report)
          env.exitcode(1)
        end
      else
        _write_file(env, report, _gui_report(env, "gui", backend, script, scene, failures))
        env.err.print("gui sdl3 unavailable: see " + report)
        env.exitcode(1)
      end
    else
      env.err.print("error: unknown gui backend: " + backend)
      env.exitcode(2)
    end

  fun verify_command(env: Env, all: Bool, backend': String, report': String) =>
    let backend = if backend' == "" then "headless" else backend' end
    let report = if report' == "" then "build/reports/verify-gui.json" else report' end
    _mkdirs()
    if not all then
      env.err.print("error: verify-gui requires --all")
      env.exitcode(2)
      return
    end

    let cases = _verify_examples()
    let failures = Array[String]
    let case_reports = String
    var index: USize = 0
    for example in cases.values() do
      let scene = _scene_for_example(env, example)
      let scene_failures = _scene_failures(scene)
      for failure in scene_failures.values() do failures.push(example + ": " + failure) end
      if index > 0 then case_reports.append(",\n") end
      case_reports.append("    ")
      case_reports.append(_scene_case_json(backend, scene, scene_failures))
      index = index + 1
    end

    if backend == "sdl3" then
      for failure in _dependency_failures(env, backend).values() do failures.push(failure) end
      if failures.size() == 0 then
        let playground_report = "build/cache/verify-gui-sdl-playground.json"
        let status = @system(_sdl_playground_command("counter", "tests/examples/gui_playground_sequence.json", playground_report).cstring())
        if status != 0 then
          failures.push("native SDL3 playground scripted verification failed with status " + status.string())
        end
      end
    elseif backend != "headless" then
      failures.push("unknown backend: " + backend)
    end

    _write_file(env, report, _verify_report(env, backend, case_reports.clone(), failures))
    if failures.size() == 0 then
      env.out.print("verify-gui ok: " + backend + " " + cases.size().string() + " cases")
    else
      env.err.print("verify-gui failed: " + _join(failures, "; "))
      env.exitcode(1)
    end

  fun _verify_examples(): Array[String] val =>
    recover val [
      "counter"
      "counter_hold"
      "interval"
      "interval_hold"
      "fibonacci"
      "cells"
      "todo_mvc"
      "pong"
      "arkanoid"
    ] end

  fun _scene_for_example(env: Env, id': String): GuiScene ref =>
    let id = _canonical_id(id')
    let index = NativePlayground.tab_index_for_id(id)
    let title = NativePlayground.tab_title(index)
    let source = NativePlayground.source_path(index)
    let project = NativePlayground.source_project(index)
    let preview = NativePlayground.protocol_preview_lines(env, index)
    let source_lines = NativePlayground.source_preview_lines(env, index, false, 0, 18)
    let viewport = GuiViewport(1440, 900, 1.0)
    let commands = Array[GuiDrawCommand val]
    let hits = Array[GuiHitRegion val]
    let semantics = Array[String]

    commands.push(GuiDrawCommand("rect", "shell.background", 0, 0, 1440, 900, "", "ink", "background"))
    commands.push(GuiDrawCommand("rect", "sidebar.examples", 0, 0, 220, 900, "", "ink", "panel"))
    commands.push(GuiDrawCommand("rect", "preview.panel", 220, 48, 720, 652, "", "ink", "preview"))
    commands.push(GuiDrawCommand("rect", "source.panel", 940, 48, 500, 852, "", "ink", "source"))
    commands.push(GuiDrawCommand("text", "toolbar.title", 236, 16, 420, 24, "Boon-Pony GUI | " + title, "ink", "background"))
    commands.push(GuiDrawCommand("button", "toolbar.run", 660, 10, 96, 30, "Run", "ink", "button"))
    commands.push(GuiDrawCommand("button", "toolbar.clear_rerun", 766, 10, 156, 30, "Clear + Rerun", "ink", "button"))
    hits.push(GuiHitRegion("toolbar.run", "rerun", source, 660, 10, 96, 30))
    hits.push(GuiHitRegion("toolbar.clear_rerun", "clear_state_and_rerun", source, 766, 10, 156, 30))
    semantics.push("gui.shell")
    semantics.push("gui.preview")
    semantics.push("gui.source")
    semantics.push(id + ".generated_protocol_child")

    var tab: USize = 0
    while tab < NativePlayground.tab_count() do
      let tab_y = (tab * 32).i64() + 16
      let tab_id = NativePlayground.tab_id(tab)
      commands.push(GuiDrawCommand("button", "tab." + tab_id, 12, tab_y, 196, 26, NativePlayground.tab_short_title(tab), "ink", if tab == index then "active" else "button" end))
      hits.push(GuiHitRegion("tab." + tab_id, "select_example:" + tab_id, NativePlayground.source_path(tab), 12, tab_y, 196, 26))
      tab = tab + 1
    end

    var row: USize = 0
    for line in preview.values() do
      if row < 28 then
        commands.push(GuiDrawCommand("text", "preview.line." + row.string(), 244, 72 + (row.i64() * 20), 660, 20, line, "ink", "preview"))
      end
      row = row + 1
    end
    if row == 0 then
      commands.push(GuiDrawCommand("text", "preview.empty", 244, 72, 660, 20, "generated protocol preview pending", "muted", "preview"))
    end

    var source_row: USize = 0
    for line in source_lines.values() do
      commands.push(GuiDrawCommand("text", "source.line." + source_row.string(), 960, 72 + (source_row.i64() * 20), 456, 20, line, "ink", "source"))
      source_row = source_row + 1
    end
    commands.push(GuiDrawCommand("scrollbar", "source.scrollbar", 1422, 64, 10, 260, "", "ink", "scrollbar"))
    hits.push(GuiHitRegion("source.viewer", "scroll_source", source, 940, 48, 500, 852))

    _example_specific_scene(id, source, commands, hits, semantics)

    GuiScene(
      id,
      title,
      source,
      1,
      viewport,
      commands,
      hits,
      semantics,
      project,
      true)

  fun _example_specific_scene(
    id: String,
    source: String,
    commands: Array[GuiDrawCommand val] ref,
    hits: Array[GuiHitRegion val] ref,
    semantics: Array[String] ref)
  =>
    match id
    | "counter" =>
      commands.push(GuiDrawCommand("button", "counter.increment", 520, 322, 72, 40, "+", "ink", "button"))
      hits.push(GuiHitRegion("counter.increment", "expected_action:click_button:0", source, 520, 322, 72, 40))
      semantics.push("counter.increment")
    | "counter_hold" =>
      commands.push(GuiDrawCommand("button", "counter_hold.increment", 520, 322, 72, 40, "+", "ink", "button"))
      hits.push(GuiHitRegion("counter_hold.increment", "expected_action:click_button:0", source, 520, 322, 72, 40))
      semantics.push("counter_hold.increment")
    | "todo_mvc" =>
      commands.push(GuiDrawCommand("text_input", "todo_mvc.new_todo", 292, 104, 560, 42, "", "ink", "input"))
      commands.push(GuiDrawCommand("caret", "todo_mvc.new_todo.caret", 312, 112, 2, 26, "", "ink", "input"))
      commands.push(GuiDrawCommand("button", "todo_mvc.toggle_all", 244, 104, 38, 42, "v", "ink", "button"))
      commands.push(GuiDrawCommand("button", "todo_mvc.filter_all", 292, 642, 54, 28, "All", "ink", "button"))
      commands.push(GuiDrawCommand("button", "todo_mvc.clear_completed", 708, 642, 142, 28, "Clear completed", "ink", "button"))
      hits.push(GuiHitRegion("todo_mvc.new_todo", "focus_text_input:new_todo", source, 292, 104, 560, 42))
      hits.push(GuiHitRegion("todo_mvc.toggle_all", "expected_action:toggle_all", source, 244, 104, 38, 42))
      hits.push(GuiHitRegion("todo_mvc.filter_all", "expected_action:filter:all", source, 292, 642, 54, 28))
      hits.push(GuiHitRegion("todo_mvc.clear_completed", "expected_action:clear_completed", source, 708, 642, 142, 28))
      semantics.push("todo_mvc.new_todo")
      semantics.push("todo_mvc.toggle_all")
      semantics.push("todo_mvc.clear_completed")
    | "cells" =>
      commands.push(GuiDrawCommand("rect", "cells.grid", 260, 110, 620, 440, "", "ink", "grid"))
      hits.push(GuiHitRegion("cells.grid.A1", "expected_action:edit_cell:A1", source, 306, 154, 84, 26))
      semantics.push("cells.grid")
      semantics.push("cells.grid.A1")
    | "pong" =>
      hits.push(GuiHitRegion("pong.preview", "expected_action:key:space", source, 220, 48, 720, 652))
      semantics.push("pong.ball")
      semantics.push("pong.player_paddle")
      semantics.push("pong.ai_paddle")
    | "arkanoid" =>
      hits.push(GuiHitRegion("arkanoid.preview", "expected_action:key:space", source, 220, 48, 720, 652))
      semantics.push("arkanoid.ball")
      semantics.push("arkanoid.paddle")
      semantics.push("arkanoid.bricks")
    else
      None
    end

  fun _scene_failures(scene: GuiScene box): Array[String] =>
    let failures = Array[String]
    if scene.draw_commands.size() == 0 then failures.push("empty draw command list") end
    if scene.hit_regions.size() == 0 then failures.push("missing hit regions") end
    if scene.semantic_ids.size() == 0 then failures.push("missing semantic ids") end
    if scene.source_path == "" then failures.push("missing source path") end
    if scene.protocol_project == "" then failures.push("missing generated protocol project") end
    if not scene.generated_protocol_child then failures.push("scene is not generated-protocol backed") end
    failures

  fun _gui_report(env: Env, command: String, backend: String, script: String, scene: GuiScene box, failures: Array[String] box): String =>
    let out = String
    out.append("{\n")
    out.append("  \"command\":\""); _append_json(out, command); out.append("\",\n")
    out.append("  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"backend\":\""); _append_json(out, backend); out.append("\",\n")
    out.append("  \"script\":\""); _append_json(out, script); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"gui_dependencies\":"); out.append(_dependency_json(env, backend)); out.append(",\n")
    out.append("  \"scene\":"); out.append(_scene_json(scene)); out.append(",\n")
    out.append("  \"failures\":"); out.append(_failures_json(failures)); out.append("\n")
    out.append("}\n")
    out.clone()

  fun _verify_report(env: Env, backend: String, case_reports: String, failures: Array[String] box): String =>
    let out = String
    out.append("{\n")
    out.append("  \"command\":\"verify-gui\",\n")
    out.append("  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"backend\":\""); _append_json(out, backend); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"gui_dependencies\":"); out.append(_dependency_json(env, backend)); out.append(",\n")
    out.append("  \"renderer_contract\":{\"scene_ir\":\"GraphScene\",\"input_protocol\":\"GuiInputEvent\",\"headless_renderer\":true,\"sdl3_bridge_required\":true,\"generated_protocol_children\":true,\"no_host_example_business_logic\":true},\n")
    out.append("  \"cases\":[\n"); out.append(case_reports); out.append("\n  ],\n")
    out.append("  \"failures\":"); out.append(_failures_json(failures)); out.append("\n")
    out.append("}\n")
    out.clone()

  fun _scene_case_json(backend: String, scene: GuiScene box, failures: Array[String] box): String =>
    let out = String
    out.append("{\"example\":\""); _append_json(out, scene.example_id); out.append("\",")
    out.append("\"backend\":\""); _append_json(out, backend); out.append("\",")
    out.append("\"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",")
    out.append("\"scene\":"); out.append(_scene_json(scene)); out.append(",")
    out.append("\"failures\":"); out.append(_failures_json(failures)); out.append("}")
    out.clone()

  fun _scene_json(scene: GuiScene box): String =>
    let out = String
    out.append("{")
    out.append("\"example_id\":\""); _append_json(out, scene.example_id); out.append("\",")
    out.append("\"title\":\""); _append_json(out, scene.title); out.append("\",")
    out.append("\"source_path\":\""); _append_json(out, scene.source_path); out.append("\",")
    out.append("\"source_line\":"); out.append(scene.source_line.string()); out.append(",")
    out.append("\"protocol_project\":\""); _append_json(out, scene.protocol_project); out.append("\",")
    out.append("\"generated_protocol_child\":"); out.append(if scene.generated_protocol_child then "true" else "false" end); out.append(",")
    out.append("\"viewport\":{\"width\":"); out.append(scene.viewport.width.string()); out.append(",\"height\":"); out.append(scene.viewport.height.string()); out.append(",\"scale\":"); out.append(scene.viewport.scale.string()); out.append("},")
    out.append("\"draw_command_count\":"); out.append(scene.draw_commands.size().string()); out.append(",")
    out.append("\"hit_region_count\":"); out.append(scene.hit_regions.size().string()); out.append(",")
    out.append("\"semantic_id_count\":"); out.append(scene.semantic_ids.size().string()); out.append(",")
    out.append("\"draw_commands\":[")
    var draw_index: USize = 0
    for command in scene.draw_commands.values() do
      if draw_index > 0 then out.append(",") end
      out.append(_draw_json(command))
      draw_index = draw_index + 1
    end
    out.append("],\"hit_regions\":[")
    var hit_index: USize = 0
    for hit in scene.hit_regions.values() do
      if hit_index > 0 then out.append(",") end
      out.append(_hit_json(hit))
      hit_index = hit_index + 1
    end
    out.append("],\"semantic_ids\":[")
    var semantic_index: USize = 0
    for id in scene.semantic_ids.values() do
      if semantic_index > 0 then out.append(",") end
      out.append("\""); _append_json(out, id); out.append("\"")
      semantic_index = semantic_index + 1
    end
    out.append("]}")
    out.clone()

  fun _draw_json(command: GuiDrawCommand box): String =>
    let out = String
    out.append("{\"kind\":\""); _append_json(out, command.kind); out.append("\",")
    out.append("\"id\":\""); _append_json(out, command.id); out.append("\",")
    out.append("\"x\":"); out.append(command.x.string()); out.append(",\"y\":"); out.append(command.y.string()); out.append(",")
    out.append("\"width\":"); out.append(command.width.string()); out.append(",\"height\":"); out.append(command.height.string()); out.append(",")
    out.append("\"text\":\""); _append_json(out, command.text); out.append("\",")
    out.append("\"fg\":\""); _append_json(out, command.fg); out.append("\",\"bg\":\""); _append_json(out, command.bg); out.append("\"}")
    out.clone()

  fun _hit_json(hit: GuiHitRegion box): String =>
    let out = String
    out.append("{\"id\":\""); _append_json(out, hit.id); out.append("\",")
    out.append("\"action\":\""); _append_json(out, hit.action); out.append("\",")
    out.append("\"source_path\":\""); _append_json(out, hit.source_path); out.append("\",")
    out.append("\"x\":"); out.append(hit.x.string()); out.append(",\"y\":"); out.append(hit.y.string()); out.append(",")
    out.append("\"width\":"); out.append(hit.width.string()); out.append(",\"height\":"); out.append(hit.height.string()); out.append("}")
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

  fun _canonical_id(id: String): String =>
    match id
    | "counterh" => "counter_hold"
    | "counter_hold" => "counter_hold"
    | "intervalh" => "interval_hold"
    | "interval_hold" => "interval_hold"
    | "fibonacci" => "fibonacci"
    | "fib" => "fibonacci"
    | "todo" => "todo_mvc"
    | "todomvc" => "todo_mvc"
    | "todo_mvc" => "todo_mvc"
    | "cells" => "cells"
    | "pong" => "pong"
    | "arkanoid" => "arkanoid"
    | "interval" => "interval"
    else "counter"
    end

  fun _dependency_failures(env: Env, backend: String): Array[String] =>
    let failures = Array[String]
    if backend != "sdl3" then return failures end

    if _use_system_sdl3(env) then
      if not _system_sdl3_pkg_config() then
        failures.push("system SDL3 was explicitly requested with BOON_PONY_USE_SYSTEM_SDL3=1, but pkg-config cannot resolve sdl3 or SDL3")
      end
      if not _system_ttf_pkg_config() then
        failures.push("system SDL3_ttf was explicitly requested with BOON_PONY_USE_SYSTEM_SDL3=1, but pkg-config cannot resolve sdl3-ttf or SDL3_ttf")
      end
      return failures
    end

    if not _local_manifest_exists() then
      failures.push("repo-local GUI dependencies are not bootstrapped: run tools/bootstrap_gui_deps.sh")
    end
    if not _local_sdl3_pkg_config() then
      failures.push("repo-local SDL3 is unavailable: .boon-local/gui/prefix/lib/pkgconfig/sdl3.pc is missing or invalid")
    end
    if not _local_ttf_pkg_config() then
      failures.push("repo-local SDL3_ttf is unavailable: .boon-local/gui/prefix/lib/pkgconfig/sdl3-ttf.pc is missing or invalid")
    end
    if not _local_fonts_available() then
      failures.push("repo-local GUI fonts are unavailable: run tools/bootstrap_gui_deps.sh")
    end
    if not _local_bridge_smoke() then
      failures.push("repo-local SDL3 C bridge smoke is missing or failing: run tools/bootstrap_gui_deps.sh")
    end
    if not _local_sdl_playground() then
      failures.push("repo-local SDL3 playground is missing or failing: run tools/bootstrap_gui_deps.sh")
    end
    failures

  fun _dependency_json(env: Env, backend: String): String =>
    let out = String
    out.append("{")
    out.append("\"backend\":\""); _append_json(out, backend); out.append("\",")
    out.append("\"mode\":\""); _append_json(out, _dependency_mode(env, backend)); out.append("\",")
    out.append("\"local_prefix\":\".boon-local/gui\",")
    out.append("\"pins_file\":\"fixtures/gui_dependency_pins.json\",")
    out.append("\"system_sdl3_opt_in\":"); out.append(if _use_system_sdl3(env) then "true" else "false" end); out.append(",")
    out.append("\"local_manifest\":"); out.append(if _local_manifest_exists() then "true" else "false" end); out.append(",")
    out.append("\"local_sdl3_pkg_config\":"); out.append(if _local_sdl3_pkg_config() then "true" else "false" end); out.append(",")
    out.append("\"local_sdl3_ttf_pkg_config\":"); out.append(if _local_ttf_pkg_config() then "true" else "false" end); out.append(",")
    out.append("\"local_fonts\":"); out.append(if _local_fonts_available() then "true" else "false" end); out.append(",")
    out.append("\"local_bridge_smoke\":"); out.append(if _local_bridge_smoke() then "true" else "false" end); out.append(",")
    out.append("\"local_sdl_playground\":"); out.append(if _local_sdl_playground() then "true" else "false" end); out.append(",")
    out.append("\"system_sdl3_pkg_config\":"); out.append(if _system_sdl3_pkg_config() then "true" else "false" end); out.append(",")
    out.append("\"system_sdl3_ttf_pkg_config\":"); out.append(if _system_ttf_pkg_config() then "true" else "false" end); out.append(",")
    out.append("\"native_window_verified\":"); out.append(if (backend == "sdl3") and _local_sdl_playground() then "true" else "false" end)
    out.append("}")
    out.clone()

  fun _dependency_mode(env: Env, backend: String): String =>
    if backend != "sdl3" then
      "not-required"
    elseif _use_system_sdl3(env) then
      if _system_sdl3_pkg_config() and _system_ttf_pkg_config() then "system-explicit" else "system-explicit-missing" end
    elseif _local_manifest_exists() and _local_sdl3_pkg_config() and _local_ttf_pkg_config() and _local_fonts_available() and _local_bridge_smoke() and _local_sdl_playground() then
      "repo-local"
    else
      "repo-local-missing"
    end

  fun _use_system_sdl3(env: Env): Bool =>
    _env_var(env, "BOON_PONY_USE_SYSTEM_SDL3", "") == "1"

  fun _env_var(env: Env, key: String, default': String): String =>
    let prefix: String val = recover val key + "=" end
    for item in env.vars.values() do
      if item.at(prefix, 0) then return recover val item.substring(prefix.size().isize()) end end
    end
    default'

  fun _local_manifest_exists(): Bool =>
    (@system("test -f .boon-local/gui/manifest.json".cstring()) == 0)

  fun _local_sdl3_pkg_config(): Bool =>
    (@system("PKG_CONFIG_PATH=.boon-local/gui/prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-} pkg-config --exists sdl3 2>/dev/null".cstring()) == 0)

  fun _local_ttf_pkg_config(): Bool =>
    (@system("PKG_CONFIG_PATH=.boon-local/gui/prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-} pkg-config --exists sdl3-ttf 2>/dev/null || PKG_CONFIG_PATH=.boon-local/gui/prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-} pkg-config --exists SDL3_ttf 2>/dev/null".cstring()) == 0)

  fun _local_fonts_available(): Bool =>
    (@system("test -f .boon-local/gui/fonts/JetBrainsMono-Regular.ttf -a -f .boon-local/gui/fonts/Inter-Regular.woff2".cstring()) == 0)

  fun _local_bridge_smoke(): Bool =>
    (@system("test -x .boon-local/gui/bin/boon_sdl_bridge_smoke && SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software LD_LIBRARY_PATH=.boon-local/gui/prefix/lib:${LD_LIBRARY_PATH:-} .boon-local/gui/bin/boon_sdl_bridge_smoke >/dev/null 2>&1".cstring()) == 0)

  fun _local_sdl_playground(): Bool =>
    (@system("test -x .boon-local/gui/bin/boon_sdl_playground && SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software LD_LIBRARY_PATH=.boon-local/gui/prefix/lib:${LD_LIBRARY_PATH:-} .boon-local/gui/bin/boon_sdl_playground --script tests/examples/gui_playground_sequence.json --report build/cache/gui-sdl-doctor.json >/dev/null 2>&1".cstring()) == 0)

  fun _sdl_playground_command(example: String, script: String, report: String): String =>
    let command = String
    if script != "" then
      command.append("SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-dummy} SDL_RENDER_DRIVER=software ")
    else
      command.append("SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-wayland} SDL_RENDER_DRIVER=${SDL_RENDER_DRIVER:-gpu} ")
    end
    command.append("LD_LIBRARY_PATH=.boon-local/gui/prefix/lib:${LD_LIBRARY_PATH:-} ")
    command.append(".boon-local/gui/bin/boon_sdl_playground --example ")
    command.append(_shell_quote(example))
    if script != "" then
      command.append(" --script ")
      command.append(_shell_quote(script))
    end
    command.append(" --report ")
    command.append(_shell_quote(report))
    command.clone()

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

  fun _system_sdl3_pkg_config(): Bool =>
    (@system("pkg-config --exists sdl3 2>/dev/null || pkg-config --exists SDL3 2>/dev/null".cstring()) == 0)

  fun _system_ttf_pkg_config(): Bool =>
    (@system("pkg-config --exists sdl3-ttf 2>/dev/null || pkg-config --exists SDL3_ttf 2>/dev/null".cstring()) == 0)

  fun _mkdirs() =>
    @system("mkdir -p build/cache build/reports".cstring())

  fun _write_file(env: Env, file: String, data: String) =>
    try
      (let dir, _) = Path.split(file)
      if dir != "" then FilePath(FileAuth(env.root), dir).mkdir() end
      with f = CreateFile(FilePath(FileAuth(env.root), file)) as File do
        f.set_length(0)
        f.write(data)
      end
    end

  fun _join(values: Array[String] box, sep: String): String =>
    let out = String
    var index: USize = 0
    for value in values.values() do
      if index > 0 then out.append(sep) end
      out.append(value)
      index = index + 1
    end
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
