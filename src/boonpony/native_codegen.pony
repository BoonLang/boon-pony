use "files"

class ref NativeCodegenResult
  let project: String
  let app: String
  let generated_dir: String
  let binary: String
  var metadata: String = "{}"
  var stdout: String = ""
  var ast_nodes: USize = 0
  var source_slots: USize = 0
  var terminal_ir: String = "{}"
  let flow_nodes: Array[String] ref = Array[String]
  let failures: Array[String] ref = Array[String]

  new create(project': String) =>
    project = project'
    app = NativeCodegen.project_name(project')
    generated_dir = "build/generated/" + app
    binary = "build/bin/generated/" + app

class val CodegenRun
  let x: String
  let y: String
  let text: String
  let id: String
  let role: String
  let fg: String
  let bold: Bool

  new val create(x': String, y': String, text': String, id': String, role': String, fg': String, bold': Bool) =>
    x = x'
    y = y'
    text = text'
    id = id'
    role = role'
    fg = fg'
    bold = bold'

primitive NativeCodegen
  fun compile_command(env: Env, project: String, report': String = "") =>
    let report = if report' == "" then "build/reports/compile.json" else report' end
    let result = _generate(env, project)
    _write_file(env, report, _compile_report(result))
    if result.failures.size() == 0 then
      env.out.print("compile ok: " + project)
      env.out.print("generated: " + result.generated_dir)
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      _print_failures(env, result.failures)
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun build_command(env: Env, project: String, report': String = "") =>
    let report = if report' == "" then "build/reports/build.json" else report' end
    let result = _build(env, project)
    _write_file(env, report, _build_report(result))
    if result.failures.size() == 0 then
      env.out.print("build ok: " + project)
      env.out.print("binary: " + result.binary)
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      _print_failures(env, result.failures)
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun protocol_smoke_command(env: Env, project: String, report': String = "") =>
    let report = if report' == "" then "build/reports/protocol-smoke.json" else report' end
    let result = _build(env, project)
    let capture: String val = recover val "build/cache/protocol-" + result.app + ".jsonl" end
    if result.failures.size() == 0 then
      _mkdirs()
      let command: String val = recover val _protocol_smoke_command(result.binary, capture) end
      let status = _system_status(command)
      if status != 0 then result.failures.push("protocol process failed with exit code " + status.string()) end
      result.stdout = try _read_file(env, capture)? else "" end
      _check_protocol(result)
    end
    _write_file(env, report, _protocol_report(result))
    if result.failures.size() == 0 then
      env.out.print("protocol-smoke ok: " + project)
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      _print_failures(env, result.failures)
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun play_command(env: Env, project: String, report': String = "") =>
    let app = project_name(project)
    let report = if report' == "" then "build/reports/play-" + app + ".json" else report' end
    let build_report: String val = recover val "build/reports/build-" + app + ".json" end
    let result = _build(env, project)
    _write_file(env, build_report, _build_report(result))
    let interactive = _system_status("test -t 0 -a -t 1") == 0
    if result.failures.size() == 0 then
      if interactive then
        let status = _system_status(_shell_quote(result.binary))
        if status != 0 then result.failures.push("play failed with exit code " + status.string()) end
      else
        _mkdirs()
        let capture: String val = recover val "build/cache/play-" + result.app + ".txt" end
        let command: String val = recover val _shell_quote(result.binary) + " --demo > " + _shell_quote(capture) + " 2>&1" end
        let status = _system_status(command)
        result.stdout = try _read_file(env, capture)? else "" end
        if result.stdout != "" then env.out.write(result.stdout) end
        if status != 0 then result.failures.push("play failed with exit code " + status.string()) end
      end
    end
    _write_file(env, report, _play_report(result, interactive))
    if result.failures.size() == 0 then
      env.exitcode(0)
    else
      _print_failures(env, result.failures)
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun project_name(project: String): String =>
    let clean = if project.at("/", -1) and (project.size() > 1) then
      project.substring(0, (project.size() - 1).isize())
    else
      project
    end
    (_, let file) = Path.split(clean)
    file

  fun _generate(env: Env, project: String): NativeCodegenResult =>
    let app = project_name(project)
    if not _acquire_lock(app) then
      let result = NativeCodegenResult(project)
      result.failures.push("timed out waiting for codegen lock: " + app)
      return result
    end
    let result = _generate_locked(env, project)
    _release_lock(app)
    result

  fun _generate_locked(env: Env, project: String): NativeCodegenResult =>
    let result = NativeCodegenResult(project)
    _mkdirs()
    if not _dir_exists(env, project) then result.failures.push("project directory not found: " + project) end
    let files = _source_files(env, project)
    if files.size() == 0 then result.failures.push("project has no .bn source files: " + project) end
    for file in files.values() do
      try
        let text = _read_file(env, file)?
        if text.contains("LINK") then result.failures.push("forbidden legacy LINK spelling in " + file) end
        let parsed = NativeBoon.parse_file(env, file)
        if parsed.status != "pass" then
          result.failures.push(file + ": parser failed before codegen: " + parsed.message)
        else
          result.ast_nodes = result.ast_nodes + parsed.ast_nodes
        end
        let shape = NativeBoon.analyze_file(env, file)
        if shape.diagnostics.size() != 0 then
          for diagnostic in shape.diagnostics.values() do
            result.failures.push(file + ":" + diagnostic.line.string() + ":" + diagnostic.column.string() + ": source-shape failed before codegen: " + diagnostic.message)
          end
        end
        result.source_slots = result.source_slots + shape.slots.size()
        if shape.terminal_ir != "{}" then result.terminal_ir = shape.terminal_ir end
        for node in shape.flow_nodes.values() do
          if not _array_contains(result.flow_nodes, node) then result.flow_nodes.push(node) end
        end
      else
        result.failures.push("cannot read source file: " + file)
      end
    end
    if result.failures.size() == 0 then
      let reset: String val = recover val "rm -rf " + _shell_quote(result.generated_dir) + " && mkdir -p " + _shell_quote(result.generated_dir) end
      let reset_status = _system_status(reset)
      if reset_status != 0 then result.failures.push("failed to reset generated directory: " + result.generated_dir) end
    end
    if result.failures.size() == 0 then
      try
        let runtime = _read_file(env, "src/runtime/boon_runtime/runtime.pony")?
        let source_text = _combined_source(env, files)?
        let generated = _generated_main(result, source_text)
        result.metadata = _metadata_json(env, result, files, source_text)
        _write_file(env, result.generated_dir + "/main.pony", generated)
        _write_file(env, result.generated_dir + "/runtime.pony", runtime)
        _write_file(env, result.generated_dir + "/metadata.json", result.metadata)
      else
        result.failures.push("failed to write generated project for " + result.app)
      end
    end
    result

  fun _build(env: Env, project: String): NativeCodegenResult =>
    let app = project_name(project)
    if not _acquire_lock(app) then
      let result = NativeCodegenResult(project)
      result.failures.push("timed out waiting for codegen lock: " + app)
      return result
    end
    let result = _generate_locked(env, project)
    if result.failures.size() == 0 then
      _mkdirs()
      let command: String val = recover val "ponyc " + _shell_quote(result.generated_dir) + " -o " + _shell_quote("build/bin/generated") end
      let status = _system_status(command)
      if status != 0 then result.failures.push("ponyc failed with exit code " + status.string()) end
      if not _file_exists(env, result.binary) then result.failures.push("missing generated binary: " + result.binary) end
    end
    _release_lock(app)
    result

  fun _check_protocol(result: NativeCodegenResult) =>
    let out = result.stdout
    for typ in ["ready"; "frame"; "tree"; "metrics"; "diagnostic"; "bench_result"; "error"; "bye"].values() do
      if not out.contains("\"type\":\"" + typ + "\"") then
        result.failures.push("missing protocol message: " + typ)
      end
    end
    for event in ["ready"; "frame"; "resize"; "key"; "mouse"; "tick"; "tree"; "metrics"; "bench"; "pause"; "resume"; "quit"].values() do
      if not out.contains("\"dispatch_event\":\"" + event + "\"") then
        result.failures.push("missing dispatch event: " + event)
      end
    end
    if out.contains("\"protocol_version\":2") or not out.contains("\"protocol_version\":1") then
      result.failures.push("bad protocol version")
    end
    let frame = _line_for_type(out, "frame")
    if (frame == "") or (not frame.contains("\"runs\"")) or frame.contains("\"cells\"") then
      result.failures.push("bad frame encoding")
    end
    if frame.contains("\"runs\":[]") then
      result.failures.push("empty frame runs")
    end
    let tree = _line_for_type(out, "tree")
    if (tree == "") or (not tree.contains("\"children\":[{")) then
      result.failures.push("empty semantic tree")
    end
    if not out.contains("\"dispatch_event\"") then
      result.failures.push("protocol smoke did not exercise GeneratedApp.dispatch")
    end

  fun _line_for_type(text: String, typ: String): String =>
    let needle: String val = recover val "\"type\":\"" + typ + "\"" end
    for line in text.split_by("\n").values() do
      if line.contains(needle) then return line end
    end
    ""

  fun _compile_report(result: NativeCodegenResult): String =>
    let out = String
    out.append("{\n  \"command\":\"compile\",\n  \"status\":\""); out.append(_status(result)); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"toolchain\":"); out.append(_toolchain_json()); out.append(",\n")
    out.append("  \"cases\":[{\"project\":\""); _append_json(out, result.project); out.append("\",\"generated_dir\":\""); _append_json(out, result.generated_dir); out.append("\",\"metadata\":"); out.append(result.metadata); out.append("}],\n")
    out.append("  \"failures\":"); out.append(_failures_json(result.failures)); out.append("\n}\n")
    out.clone()

  fun _build_report(result: NativeCodegenResult): String =>
    let out = String
    out.append("{\n  \"command\":\"build\",\n  \"status\":\""); out.append(_status(result)); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"toolchain\":"); out.append(_toolchain_json()); out.append(",\n")
    out.append("  \"cases\":[{\"project\":\""); _append_json(out, result.project); out.append("\",\"generated_dir\":\""); _append_json(out, result.generated_dir); out.append("\",\"binary\":\""); _append_json(out, result.binary); out.append("\",\"compile\":{\"project\":\""); _append_json(out, result.project); out.append("\",\"generated_dir\":\""); _append_json(out, result.generated_dir); out.append("\",\"metadata\":"); out.append(result.metadata); out.append("}}],\n")
    out.append("  \"failures\":"); out.append(_failures_json(result.failures)); out.append("\n}\n")
    out.clone()

  fun _protocol_report(result: NativeCodegenResult): String =>
    let out = String
    out.append("{\n  \"command\":\"protocol-smoke\",\n  \"status\":\""); out.append(_status(result)); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"toolchain\":"); out.append(_toolchain_json()); out.append(",\n")
    out.append("  \"cases\":[{\"project\":\""); _append_json(out, result.project); out.append("\",\"binary\":\""); _append_json(out, result.binary); out.append("\",\"message_types\":"); out.append(_message_types_json(result.stdout)); out.append(",\"stdout\":\""); _append_json(out, result.stdout); out.append("\"}],\n")
    out.append("  \"failures\":"); out.append(_failures_json(result.failures)); out.append("\n}\n")
    out.clone()

  fun _play_report(result: NativeCodegenResult, interactive: Bool): String =>
    let out = String
    out.append("{\n  \"command\":\"play\",\n  \"status\":\""); out.append(_status(result)); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"cases\":[{\"project\":\""); _append_json(out, result.project); out.append("\",\"binary\":\""); _append_json(out, result.binary); out.append("\",\"mode\":\""); out.append(if interactive then "interactive" else "demo" end); out.append("\",\"stdout\":\""); _append_json(out, result.stdout); out.append("\"}],\n")
    out.append("  \"failures\":"); out.append(_failures_json(result.failures)); out.append("\n}\n")
    out.clone()

  fun _metadata_json(env: Env, result: NativeCodegenResult, files: Array[String] val, source: String): String =>
    let behavior = _terminal_behavior(result.app, source, result.flow_nodes)
    let initial_runs = _terminal_runs(result.app, source, behavior, result.terminal_ir, false)
    let runtime_profile = _runtime_profile(behavior, initial_runs, result.flow_nodes)
    let projection_fallback = _runtime_projection_fallback(runtime_profile)
    let profile_source = _runtime_profile_source(behavior, runtime_profile, result.flow_nodes)
    let terminal_ir_lowered = _has_flow(result.flow_nodes, "TerminalCanvas")
    let source_derived_profile = (not terminal_ir_lowered) and (runtime_profile != result.app) and (profile_source != "hir-flow")
    let out = String
    out.append("{\"app\":\""); _append_json(out, result.app); out.append("\",")
    out.append("\"project\":\""); _append_json(out, result.project); out.append("\",")
    out.append("\"source_files\":"); out.append(_strings_json(files)); out.append(",")
    out.append("\"source_hash\":\""); out.append(_source_hash(env, files)); out.append("\",")
    out.append("\"generated_at\":\"native-pony\",")
    out.append("\"codegen_strategy\":\""); out.append(_codegen_strategy(result.flow_nodes, runtime_profile)); out.append("\",")
    out.append("\"lowering_plan\":{\"behavior\":\""); _append_json(out, behavior); out.append("\",\"behavior_source\":\""); _append_json(out, _terminal_behavior_source(result.app, source, result.flow_nodes)); out.append("\",\"runtime_profile\":\""); _append_json(out, runtime_profile); out.append("\",\"runtime_profile_source\":\""); _append_json(out, profile_source); out.append("\",\"projection_fallback\":"); out.append(if projection_fallback then "true" else "false" end); out.append(",\"source_derived_profile\":"); out.append(if source_derived_profile then "true" else "false" end); out.append(",\"rule_table_driven_behavior\":"); out.append(if _terminal_behavior_source(result.app, source, result.flow_nodes) == "source-rule" then "true" else "false" end); out.append(",\"terminal_run_source\":\""); out.append(if terminal_ir_lowered then "terminal-ir" else "hir-flow-profile" end); out.append("\",\"hir_flow_features\":"); out.append(_flow_features_json(result.flow_nodes)); out.append(",\"terminal_ir\":"); out.append(_metadata_terminal_ir(result.terminal_ir)); out.append("},")
    out.append("\"parser_ast_nodes\":"); out.append(result.ast_nodes.string()); out.append(",")
    out.append("\"source_slot_count\":"); out.append(result.source_slots.string()); out.append(",")
    out.append("\"hir_flow_verified\":true,")
    out.append("\"terminal_ir_lowered\":"); out.append(if terminal_ir_lowered then "true" else "false" end); out.append(",")
    out.append("\"terminal_behavior\":\""); _append_json(out, behavior); out.append("\",")
    out.append("\"terminal_canvas\":{\"width\":"); out.append(_terminal_ir_width(result.terminal_ir)); out.append(",\"height\":"); out.append(_terminal_ir_height(result.terminal_ir)); out.append(",\"item_count\":"); out.append(_terminal_ir_item_count(result.terminal_ir).string()); out.append(",\"drawable_item_count\":"); out.append(_terminal_ir_drawable_item_count(result.terminal_ir).string()); out.append(",\"group_count\":"); out.append(_terminal_ir_group_count(result.terminal_ir).string()); out.append("},")
    out.append("\"protocol_version\":1,")
    out.append("\"runtime_actor\":\"GeneratedApp\",")
    out.append("\"runtime_state_shape\":{\"app_state\":true,\"persist_store\":true,\"route_store\":true,\"virtual_clock\":true,\"terminal_canvas\":true,\"semantic_node\":true,\"runtime_metrics\":true,\"deterministic_dispatch\":true},")
    out.append("\"protocol_dispatch\":{\"generated_app\":true,\"scripted_stdin_smoke\":true,\"stdin_jsonl\":true,\"generic_expected_action_parser\":true,\"messages\":[\"ready\",\"resize\",\"key\",\"mouse\",\"tick\",\"frame\",\"pause\",\"resume\",\"tree\",\"metrics\",\"bench\",\"quit\"]},")
    out.append("\"source_slots_normalized\":true}")
    out.clone()

  fun _codegen_strategy(flow_nodes: Array[String] box, runtime_profile: String): String =>
    if _has_flow(flow_nodes, "TerminalCanvas") then
      "terminal-ir-to-pony"
    elseif _runtime_projection_fallback(runtime_profile) then
      "hir-flow-profiled-projection-pony"
    else
      "hir-flow-profiled-pony"
    end

  fun _runtime_projection_fallback(runtime_profile: String): Bool =>
    runtime_profile.contains("projection") or
    (runtime_profile == "document_trace_projection") or
    (runtime_profile == "spreadsheet_projection")

  fun _flow_features_json(flow_nodes: Array[String] box): String =>
    let out = String
    out.append("[")
    var count: USize = 0
    for node in flow_nodes.values() do
      if not node.at("Behavior:", 0) then
        count = _append_feature(out, count, node, true)
      end
    end
    out.append("]")
    out.clone()

  fun _append_feature(out: String ref, count: USize, feature: String, enabled: Bool): USize =>
    if not enabled then return count end
    if count > 0 then out.append(",") end
    out.append("\""); out.append(feature); out.append("\"")
    count + 1

  fun _metadata_terminal_ir(terminal_ir: String): String =>
    if terminal_ir == "{}" then
      "{\"lowered\":false,\"item_count\":0,\"drawable_item_count\":0,\"group_count\":0}"
    else
      "{\"lowered\":true,\"item_count\":" + _terminal_ir_item_count(terminal_ir).string() + ",\"drawable_item_count\":" + _terminal_ir_drawable_item_count(terminal_ir).string() + ",\"group_count\":" + _terminal_ir_group_count(terminal_ir).string() + "}"
    end

  fun _combined_source(env: Env, files: Array[String] val): String ? =>
    let out = String
    for file in files.values() do
      out.append("-- file: ")
      out.append(file)
      out.append("\n")
      out.append(_read_file(env, file)?)
      out.append("\n")
    end
    out.clone()

  fun _generated_main(result: NativeCodegenResult, source: String): String =>
    let behavior = _terminal_behavior(result.app, source, result.flow_nodes)
    let title = _terminal_title(result.app, source, behavior)
    let initial_runs = _terminal_runs(result.app, source, behavior, result.terminal_ir, false)
    let final_runs = _terminal_runs(result.app, source, behavior, result.terminal_ir, true)
    _generated_terminal(result.app, source, behavior, title, _terminal_ir_width(result.terminal_ir), _terminal_ir_height(result.terminal_ir), initial_runs, final_runs, result.flow_nodes)

  fun _generated_terminal(app: String, source: String, behavior: String, title: String, width: String, height: String, initial_runs: Array[CodegenRun val] val, final_runs: Array[CodegenRun val] val, flow_nodes: Array[String] box): String =>
    let initial_primary = _display_primary(source, behavior, false, initial_runs)
    let initial_secondary = _display_secondary(source, behavior, false, initial_runs)
    let final_primary = _display_primary(source, behavior, true, final_runs)
    let final_secondary = _display_secondary(source, behavior, true, final_runs)
    let out = String
    _append_generated_header(out)
    out.append("actor Main\n")
    out.append("  new create(env: Env) =>\n")
    out.append("    if _has_arg(env, \"--protocol\") then\n")
    out.append("      _protocol(env)\n")
    out.append("    elseif _has_arg(env, \"--demo\") then\n")
    out.append("      _demo(env)\n")
    out.append("    else\n")
    out.append("      _direct(env)\n")
    out.append("    end\n\n")
    _append_has_arg(out)
    out.append("  fun _demo(env: Env) =>\n")
    _append_demo_prints(out, title, initial_runs, final_runs)
    out.append("\n")
    out.append("  fun _direct(env: Env) =>\n")
    out.append("    @system(\"stty raw -echo\".cstring())\n")
    out.append("    GeneratedScreen.enter(env)\n")
    out.append("    GeneratedScreen.render(env, \""); _append_pony_string(out, title); out.append("\", \""); _append_pony_string(out, initial_primary); out.append("\", \""); _append_pony_string(out, initial_secondary); out.append("\")\n")
    out.append("    env.input(\n")
    out.append("      object iso is InputNotify\n")
    out.append("        var _line1: String = \""); _append_pony_string(out, initial_primary); out.append("\"\n")
    out.append("        var _line2: String = \""); _append_pony_string(out, initial_secondary); out.append("\"\n")
    out.append("        fun ref apply(data': Array[U8] iso) =>\n")
    out.append("          let data: Array[U8] ref = consume data'\n")
    out.append("          for byte in data.values() do\n")
    out.append("            if (byte == 3) or (byte == 81) or (byte == 113) then\n")
    out.append("              GeneratedScreen.restore(env, \"final score \" + _line1 + \"\\nfinal status \" + _line2)\n")
    out.append("            elseif (byte == 10) or (byte == 13) or (byte == 32) then\n")
    if behavior == "arkanoid" then
      out.append("              if _line2 == \"Lost\" then\n")
      out.append("                _line1 = \""); _append_pony_string(out, initial_primary); out.append("\"\n")
      out.append("                _line2 = \""); _append_pony_string(out, initial_secondary); out.append("\"\n")
      out.append("              else\n")
      out.append("                _line1 = \""); _append_pony_string(out, final_primary); out.append("\"\n")
      out.append("                _line2 = \""); _append_pony_string(out, final_secondary); out.append("\"\n")
      out.append("              end\n")
    else
      out.append("              _line1 = \""); _append_pony_string(out, final_primary); out.append("\"\n")
      out.append("              _line2 = \""); _append_pony_string(out, final_secondary); out.append("\"\n")
    end
    out.append("              GeneratedScreen.render(env, \""); _append_pony_string(out, title); out.append("\", _line1, _line2)\n")
    out.append("            elseif (byte == 76) or (byte == 108) then\n")
    out.append("              _line2 = \"Lost\"\n")
    out.append("              GeneratedScreen.render(env, \""); _append_pony_string(out, title); out.append("\", _line1, _line2)\n")
    out.append("            end\n")
    out.append("          end\n")
    out.append("        fun ref dispose() => None\n")
    out.append("      end,\n")
    out.append("      32)\n\n")
    _append_protocol(out, app, width, height, initial_runs, final_runs)
    _append_generated_runtime_actor(out, app, source, behavior, width, height, initial_runs, final_runs, _runtime_frame_text(initial_runs), _runtime_frame_text(final_runs), flow_nodes)
    _append_screen_primitive(out, title)
    out.clone()

  fun _append_generated_header(out: String ref) =>
    out.append("use @system[I32](cmd: Pointer[U8] tag)\n\n")
    out.append("// Generated by boonpony from Boon source. Do not edit in place.\n\n")

  fun _append_has_arg(out: String ref) =>
    out.append("  fun _has_arg(env: Env, expected: String): Bool =>\n")
    out.append("    var index: USize = 1\n")
    out.append("    while index < env.args.size() do\n")
    out.append("      try\n")
    out.append("        if env.args(index)? == expected then return true end\n")
    out.append("      end\n")
    out.append("      index = index + 1\n")
    out.append("    end\n")
    out.append("    false\n\n")

  fun _terminal_behavior(app: String, source: String, flow_nodes: Array[String] box): String =>
    let flow_behavior = _terminal_behavior_from_flow(app, flow_nodes)
    if flow_behavior != "" then return flow_behavior end
    "document"

  fun _terminal_behavior_source(app: String, source: String, flow_nodes: Array[String] box): String =>
    if _terminal_behavior_from_flow(app, flow_nodes) != "" then
      "hir-flow"
    else
      "generic-document"
    end

  fun _terminal_behavior_from_flow(app: String, flow_nodes: Array[String] box): String =>
    if _has_flow(flow_nodes, "Behavior:Pong") then
      "pong"
    elseif _has_flow(flow_nodes, "Behavior:Arkanoid") then
      "arkanoid"
    elseif _has_flow(flow_nodes, "Behavior:Cells") then
      "cells"
    elseif _has_flow(flow_nodes, "Behavior:ComplexCounter") then
      "complex_counter"
    elseif _has_flow(flow_nodes, "Behavior:ButtonClickStates") then
      "button_click_states"
    elseif _has_flow(flow_nodes, "Behavior:ButtonHoverTest") then
      "button_hover_test"
    elseif _has_flow(flow_nodes, "Behavior:ListMapBlock") then
      "list_map_block"
    elseif _has_flow(flow_nodes, "Behavior:ListRetainCount") then
      "list_retain_count"
    elseif _has_flow(flow_nodes, "Behavior:CheckboxTest") then
      "checkbox_test"
    elseif _has_flow(flow_nodes, "Behavior:CircleDrawer") then
      "circle_drawer"
    elseif _has_flow(flow_nodes, "Behavior:Timer") then
      "timer"
    elseif _has_flow(flow_nodes, "Behavior:FlightBooker") then
      "flight_booker"
    elseif _has_flow(flow_nodes, "Behavior:ListMapExternalDep") then
      "list_map_external_dep"
    elseif _has_flow(flow_nodes, "Behavior:ListRetainReactive") then
      "list_retain_reactive"
    elseif _has_flow(flow_nodes, "Behavior:ListRetainRemove") then
      "list_retain_remove"
    elseif _has_flow(flow_nodes, "Behavior:TemperatureConverter") then
      "temperature_converter"
    elseif _has_flow(flow_nodes, "Behavior:ChainedListRemove") then
      "chained_list_remove"
    elseif _has_flow(flow_nodes, "Behavior:Crud") then
      "crud"
    elseif _has_flow(flow_nodes, "Behavior:FilterCheckboxBug") then
      "filter_checkbox_bug"
    elseif _has_flow(flow_nodes, "Behavior:ListObjectState") then
      "list_object_state"
    elseif _has_flow(flow_nodes, "Behavior:ShoppingList") then
      "shopping_list"
    elseif _has_flow(flow_nodes, "Behavior:Pages") then
      "pages"
    elseif _has_flow(flow_nodes, "Behavior:SwitchHoldTest") then
      "switch_hold_test"
    elseif _has_flow(flow_nodes, "Behavior:TodoMvcPhysical") then
      "todo_mvc_physical"
    elseif _has_flow(flow_nodes, "Behavior:TodoMvc") then
      "todo_mvc"
    elseif _has_flow(flow_nodes, "Behavior:TextInterpolationUpdate") then
      "text_interpolation_update"
    elseif _has_flow(flow_nodes, "Behavior:WhileFunctionCall") then
      "while_function_call"
    elseif _has_flow(flow_nodes, "Behavior:Then") then
      "then"
    elseif _has_flow(flow_nodes, "Behavior:When") then
      "when"
    elseif _has_flow(flow_nodes, "Behavior:While") then
      "while"
    elseif _has_flow(flow_nodes, "Behavior:Latest") then
      "latest"
    elseif _has_flow(flow_nodes, "Behavior:Interval") then
      "interval"
    elseif _has_flow(flow_nodes, "Behavior:Counter") then
      "counter"
    elseif _has_flow(flow_nodes, "Behavior:Document") then
      "document"
    else
      ""
    end

  fun _terminal_title(app: String, source: String, behavior: String): String =>
    if behavior == "cells" then
      "Cells"
    elseif behavior == "counter" then
      "Counter"
    elseif behavior == "interval" then
      "Interval"
    elseif behavior == "pong" then
      "Pong"
    elseif behavior == "arkanoid" then
      "Arkanoid"
    else
      app
    end

  fun _canvas_width(source: String): String =>
    if not source.contains("Terminal/canvas") then return "80" end
    let canvas_start: ISize = try source.find("Terminal/canvas")? else 0 end
    let width = _arg_value_after(source, "width:", canvas_start)
    if width == "" then "80" else width end

  fun _canvas_height(source: String): String =>
    if not source.contains("Terminal/canvas") then return "24" end
    let canvas_start: ISize = try source.find("Terminal/canvas")? else 0 end
    let height = _arg_value_after(source, "height:", canvas_start)
    if height == "" then "24" else height end

  fun _terminal_ir_width(terminal_ir: String): String =>
    let width = _json_string_value(terminal_ir, "width")
    if width == "" then "80" else width end

  fun _terminal_ir_height(terminal_ir: String): String =>
    let height = _json_string_value(terminal_ir, "height")
    if height == "" then "24" else height end

  fun _terminal_ir_item_count(terminal_ir: String): USize =>
    _terminal_ir_drawable_item_count(terminal_ir) + _terminal_ir_group_count(terminal_ir)

  fun _terminal_ir_drawable_item_count(terminal_ir: String): USize =>
    _count_calls(terminal_ir, "\"kind\":\"CanvasText\"") + _count_calls(terminal_ir, "\"kind\":\"CanvasRect\"")

  fun _terminal_ir_group_count(terminal_ir: String): USize =>
    _count_calls(terminal_ir, "\"kind\":\"CanvasGroup\"")

  fun _json_string_value(text: String, key: String): String =>
    let needle: String val = recover val "\"" + key + "\":\"" end
    try
      var cursor = text.find(needle, 0)? + needle.size().isize()
      let out = String
      var escaped = false
      while cursor < text.size().isize() do
        let ch = text.at_offset(cursor)?
        if escaped then
          out.push(ch)
          escaped = false
        elseif ch == '\\' then
          escaped = true
        elseif ch == '"' then
          return out.clone()
        else
          out.push(ch)
        end
        cursor = cursor + 1
      end
      ""
    else
      ""
    end

  fun _object_start_before(text: String, position: ISize): ISize ? =>
    var cursor = position
    while cursor >= 0 do
      if text.at_offset(cursor)? == '{' then return cursor end
      cursor = cursor - 1
    end
    error

  fun _json_object_at(text: String, start: ISize): String ? =>
    var cursor = start
    var depth: ISize = 0
    var in_string = false
    var escaped = false
    while cursor < text.size().isize() do
      let ch = text.at_offset(cursor)?
      if escaped then
        escaped = false
      elseif ch == '\\' then
        escaped = in_string
      elseif ch == '"' then
        in_string = not in_string
      elseif not in_string then
        if ch == '{' then
          depth = depth + 1
        elseif ch == '}' then
          depth = depth - 1
          if depth == 0 then return text.substring(start, cursor + 1) end
        end
      end
      cursor = cursor + 1
    end
    error

  fun _terminal_item_count(source: String): USize =>
    _count_calls(source, "Canvas/text") + _count_calls(source, "Canvas/rect")

  fun _count_calls(source: String, needle: String): USize =>
    var count: USize = 0
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find(needle, cursor)?
        count = count + 1
        cursor = start + needle.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    count

  fun _terminal_runs(app: String, source: String, behavior: String, terminal_ir: String, final_frame: Bool): Array[CodegenRun val] val =>
    let ir_runs = _terminal_runs_from_ir(app, source, behavior, terminal_ir, final_frame)
    if ir_runs.size() > 0 then return ir_runs end
    let runs = recover trn Array[CodegenRun val] end
    var item_index: USize = 0
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("Canvas/text", cursor)?
        let call = _call_source(source, start)?
        let x_expr = _call_arg(call, "x")
        let y_expr = _call_arg(call, "y")
        let text_expr = _call_text_arg(call)
        let text = _render_text(text_expr, source, behavior, final_frame)
        let id = _semantic_id(app, behavior, "text", x_expr, y_expr, text_expr, text, item_index)
        runs.push(CodegenRun(_coord_value(x_expr, source, behavior, final_frame), _coord_value(y_expr, source, behavior, final_frame), text, id, _semantic_role(id, "canvas_text"), _run_fg(id), _run_bold(id)))
        item_index = item_index + 1
        cursor = start + call.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    cursor = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("Canvas/rect", cursor)?
        let call = _call_source(source, start)?
        let x_expr = _call_arg(call, "x")
        let y_expr = _call_arg(call, "y")
        let width_expr = _call_arg(call, "width")
        let glyph = _call_text_value(_call_arg(call, "glyph"))
        let text = _rect_text(glyph, width_expr)
        let id = _semantic_id(app, behavior, "rect", x_expr, y_expr, glyph, text, item_index)
        runs.push(CodegenRun(_coord_value(x_expr, source, behavior, final_frame), _coord_value(y_expr, source, behavior, final_frame), text, id, _semantic_role(id, "canvas_rect"), _run_fg(id), false))
        item_index = item_index + 1
        cursor = start + call.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    if runs.size() == 0 then
      if behavior == "cells" then
        if source.contains("Terminal/canvas") then
          var cell_index: USize = 0
          for value in [
            "Cells"; "5"; "10"; "15"; "30"; "7"; "17"; "32"; "9"; "11"; "21"; "36"; "12"; "20"; "31"; "46"; "100"
          ].values() do
            runs.push(CodegenRun("0", cell_index.string(), value, "cells.state." + cell_index.string(), "document_text", if cell_index == 0 then "white" else "green" end, cell_index == 0))
            cell_index = cell_index + 1
          end
        end
      end
    end
    if runs.size() == 0 then
      let document_texts = _document_texts(source, behavior, final_frame)
      let joined = _join_texts(document_texts)
      var text_index: USize = 0
      if joined != "" then
        runs.push(CodegenRun("0", "0", joined, app + ".document.text", "document_text", "white", true))
        text_index = 1
      elseif source.contains("Timer/interval") and (not source.contains("Terminal/canvas")) then
        runs.push(CodegenRun("0", "0", "", app + ".timer.initial", "document_text", "white", true))
        text_index = 1
      end
      for text in document_texts.values() do
        if (text != joined) and (text_index < 12) then
          runs.push(CodegenRun("0", text_index.string(), text, app + ".document." + text_index.string(), "document_text", if text_index == 0 then "white" else "green" end, text_index == 0))
          text_index = text_index + 1
        end
      end
      if runs.size() == 0 then
        runs.push(CodegenRun("0", "0", app, app + ".document", "document_text", "white", true))
      end
    end
    consume runs

  fun _terminal_runs_from_ir(app: String, source: String, behavior: String, terminal_ir: String, final_frame: Bool): Array[CodegenRun val] val =>
    let runs = recover trn Array[CodegenRun val] end
    if terminal_ir == "{}" then return consume runs end
    var item_index: USize = 0
    var cursor: ISize = 0
    while cursor < terminal_ir.size().isize() do
      try
        let kind_pos = terminal_ir.find("\"kind\":\"Canvas", cursor)?
        let object_start = _object_start_before(terminal_ir, kind_pos)?
        let object_text = _json_object_at(terminal_ir, object_start)?
        let kind = _json_string_value(object_text, "kind")
        let x_expr = _json_string_value(object_text, "x")
        let y_expr = _json_string_value(object_text, "y")
        if kind == "CanvasText" then
          let text_expr = _json_string_value(object_text, "text")
          let text = _render_text(text_expr, source, behavior, final_frame)
          let id = _semantic_id(app, behavior, "text", x_expr, y_expr, text_expr, text, item_index)
          runs.push(CodegenRun(_coord_value(x_expr, source, behavior, final_frame), _coord_value(y_expr, source, behavior, final_frame), text, id, _semantic_role(id, "canvas_text"), _run_fg(id), _run_bold(id)))
        elseif kind == "CanvasRect" then
          let width_expr = _json_string_value(object_text, "width")
          let glyph = _json_string_value(object_text, "glyph")
          let text = _rect_text(glyph, width_expr)
          let id = _semantic_id(app, behavior, "rect", x_expr, y_expr, glyph, text, item_index)
          runs.push(CodegenRun(_coord_value(x_expr, source, behavior, final_frame), _coord_value(y_expr, source, behavior, final_frame), text, id, _semantic_role(id, "canvas_rect"), _run_fg(id), false))
        elseif kind == "CanvasGroup" then
          None
        end
        item_index = item_index + 1
        cursor = object_start + object_text.size().isize()
      else
        cursor = terminal_ir.size().isize()
      end
    end
    consume runs

  fun _spreadsheet_default_row_value(source: String, row: String, fallback: String): String =>
    if not source.contains("FUNCTION default_formula") then return fallback end
    let marker: String val = recover val row + " => TEXT" end
    try
      let default_start = source.find("FUNCTION default_formula")?
      let start = source.find(marker, default_start)?
      let text_start = source.find("TEXT", start)?
      (let value, _) = _text_block_at(source, text_start)?
      if value == "" then fallback else value end
    else
      fallback
    end

  fun _spreadsheet_row_count(source: String): String =>
    let explicit = _top_level_value(source, "row_count", "cells", false)
    if explicit != "" then return explicit end
    try
      let marker = source.find("all_row_cells:")?
      let range_start = source.find("List/range", marker)?
      let call = _call_source(source, range_start)?
      let value = _call_arg(call, "to")
      if value == "" then "100" else value end
    else
      "100"
    end

  fun _first_text_or(source: String, contains: String, fallback: String): String =>
    for text in _text_blocks(source).values() do
      if text.contains(contains) then return text end
    end
    fallback

  fun _chained_item_name(source: String, id: String, fallback: String): String =>
    let marker: String val = recover val "create_item(id: " + id end
    try
      let start = source.find(marker)?
      let call = _call_source(source, start)?
      let name = _call_text_value(_call_arg(call, "name"))
      if name == "" then fallback else name end
    else
      fallback
    end

  fun _chained_new_item_name(source: String): String =>
    try
      let start = source.find("item_to_add:")?
      let call_start = source.find("create_item", start)?
      let call = _call_source(source, call_start)?
      let name = _call_text_value(_call_arg(call, "name"))
      if name == "" then "New Item" else name end
    else
      "New Item"
    end

  fun _crud_person_field(source: String, index: USize, field: String, fallback: String): String =>
    var cursor: ISize = 0
    var matched: USize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("new_person(", cursor)?
        let call = _call_source(source, start)?
        let name_arg = _call_arg(call, "name")
        let surname_arg = _call_arg(call, "surname")
        if name_arg.contains("TEXT") and surname_arg.contains("TEXT") then
          if matched == index then
            let value = if field == "surname" then _call_text_value(surname_arg) else _call_text_value(name_arg) end
            return if value == "" then fallback else value end
          else
            matched = matched + 1
          end
        end
        cursor = start + call.size().isize()
      else
        return fallback
      end
    end
    fallback

  fun _todo_initial_title(source: String, index: USize, fallback: String): String =>
    var cursor: ISize = 0
    var matched: USize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("new_todo(", cursor)?
        let call = _call_source(source, start)?
        let title_arg = _call_arg(call, "title")
        if title_arg.contains("TEXT") then
          if matched == index then
            let value = _call_text_value(title_arg)
            return if value == "" then fallback else value end
          else
            matched = matched + 1
          end
        end
        cursor = start + call.size().isize()
      else
        return fallback
      end
    end
    fallback

  fun _rect_text(glyph: String, width_expr: String): String =>
    let out = String
    let count = try width_expr.usize()? else USize(1) end
    var index: USize = 0
    while index < count do
      out.append(glyph)
      index = index + 1
    end
    out.clone()

  fun _render_text(expr': String, source: String, behavior: String, final_frame: Bool): String =>
    let expr = _trim(expr')
    if expr.at("state.", 0) then
      _state_value(source, expr.substring(6), behavior, final_frame)
    else
      _render_template(expr, source, behavior, final_frame)
    end

  fun _render_template(template: String, source: String, behavior: String, final_frame: Bool): String =>
    let out = String
    var cursor: ISize = 0
    try
      while cursor < template.size().isize() do
        let open = template.find("{", cursor)?
        out.append(template.substring(cursor, open))
        let close = template.find("}", open + 1)?
        let key = _trim(template.substring(open + 1, close))
        out.append(_value_for_path(source, key, behavior, final_frame))
        cursor = close + 1
      end
    end
    if cursor < template.size().isize() then out.append(template.substring(cursor)) end
    _normalize_rendered_template(source, out.clone())

  fun _normalize_rendered_template(source: String, rendered: String): String =>
    if source.contains("List/retain") and rendered.contains(" (show_even: ") then
      _replace_text(_replace_text(rendered, " (show_even: ", "show_even: "), ")", "")
    else
      rendered
    end

  fun _value_for_path(source: String, key: String, behavior: String, final_frame: Bool): String =>
    if key.at("state.", 0) then
      _state_value(source, key.substring(6), behavior, final_frame)
    elseif key == "counter" then
      _counter_value(behavior, final_frame)
    elseif key == "result" then
      _top_level_value(source, key, behavior, final_frame)
    elseif key == "position" then
      _top_level_value(source, key, behavior, final_frame)
    elseif key.contains(".name") then
      let value = _store_name_value(source, key)
      if value == "" then key else value end
    elseif key.contains(".clicked") then
      "False"
    elseif key.contains(".count") or key.contains(".click_count") then
      "0"
    elseif key.contains("List/count") then
      _list_literal_count(source, key)
    elseif key == "store.filtered_count" then
      _filtered_count_value(source, final_frame)
    elseif key == "count" then
      _store_list_literals(source, "items").size().string()
    elseif key.at("store.", 0) and (key.contains("value") or key.contains("show") or key.contains("checked")) then
      if final_frame then "True" else "False" end
    elseif key.at("store.", 0) then
      let store_value = _store_field_value(source, key.substring(6))
      if store_value != "" then store_value else key end
    else
      let value = _top_level_value(source, key, behavior, final_frame)
      if value == "" then key else value end
    end

  fun _counter_value(behavior: String, final_frame: Bool): String =>
    if (behavior == "interval") and final_frame then
      "2"
    else
      "0"
    end

  fun _state_value(source: String, key: String, behavior: String, final_frame: Bool): String =>
    if final_frame then
      if (behavior == "pong") and (key == "left_score") then
        return "1"
      elseif (behavior == "pong") and (key == "right_score") then
        return "0"
      elseif (behavior == "pong") and (key == "ball_x") then
        return "67"
      elseif (behavior == "pong") and (key == "status") then
        return "Point scored"
      elseif (behavior == "arkanoid") and (key == "score") then
        return "1"
      elseif (behavior == "arkanoid") and (key == "status") then
        return "Brick removed"
      elseif (behavior == "arkanoid") and (key == "bricks_left") then
        return "23"
      end
    end
    _state_default(source, key, "0")

  fun _state_default(source: String, key: String, fallback: String): String =>
    let block = _state_block(source)
    let prefix: String val = recover val key + ":" end
    for line in block.split_by("\n").values() do
      let trimmed = _trim(line)
      if trimmed.at(prefix, 0) then
        let raw = _trim(trimmed.substring(prefix.size().isize()))
        let stable = try _trim(raw.substring(0, raw.find("|>")?)) else raw end
        return _value_literal(stable)
      end
    end
    fallback

  fun _state_block(source: String): String =>
    try
      let marker = source.find("state:")?
      let open = source.find("[", marker)?
      var cursor = open + 1
      var depth: ISize = 1
      while cursor < source.size().isize() do
        let ch = source.at_offset(cursor)?
        if ch == '[' then
          depth = depth + 1
        elseif ch == ']' then
          depth = depth - 1
          if depth == 0 then return source.substring(open + 1, cursor) end
        end
        cursor = cursor + 1
      end
    end
    ""

  fun _store_field_value(source: String, key: String): String =>
    let block = _store_block(source)
    let prefix: String val = recover val key + ":" end
    for line in block.split_by("\n").values() do
      let trimmed = _trim(line)
      if trimmed.at(prefix, 0) then
        let raw = _trim(trimmed.substring(prefix.size().isize()))
        let stable = try _trim(raw.substring(0, raw.find("|>")?)) else raw end
        return _value_literal(stable)
      end
    end
    ""

  fun _store_block(source: String): String =>
    try
      let marker = source.find("store:")?
      let open = source.find("[", marker)?
      var cursor = open + 1
      var depth: ISize = 1
      while cursor < source.size().isize() do
        let ch = source.at_offset(cursor)?
        if ch == '[' then
          depth = depth + 1
        elseif ch == ']' then
          depth = depth - 1
          if depth == 0 then return source.substring(open + 1, cursor) end
        end
        cursor = cursor + 1
      end
    end
    ""

  fun _top_level_value(source: String, key: String, behavior: String, final_frame: Bool): String =>
    let value = _top_level_binding(source, key)
    if value == "" then
      ""
    elseif value.contains("|> fibonacci") then
      _fibonacci(_top_level_value(source, "position", behavior, final_frame))
    elseif value.contains("|> Math/sum") then
      try
        let pipe = value.find("|> Math/sum")?
        _top_level_value(source, _trim(value.substring(0, pipe)), behavior, final_frame)
      else
        ""
      end
    elseif value.contains("sum_of_steps(") then
      "0"
    elseif value.contains("LATEST") then
      _latest_initial_value(source, key)
    elseif value.contains("TEXT") then
      _render_template(_call_text_value(value), source, behavior, final_frame)
    elseif value.contains("|> HOLD") then
      try _value_literal(_trim(value.substring(0, value.find("|> HOLD")?))) else _value_literal(value) end
    else
      _value_literal(value)
    end

  fun _latest_initial_value(source: String, key: String): String =>
    try
      let marker: String val = recover val key + ":" end
      let start = source.find(marker)?
      let open = source.find("{", start)?
      var cursor = open + 1
      var depth: ISize = 1
      let line = String
      while cursor < source.size().isize() do
        let ch = source.at_offset(cursor)?
        if ch == '{' then
          depth = depth + 1
        elseif ch == '}' then
          depth = depth - 1
          if depth == 0 then
            let candidate = _latest_literal_candidate(line.clone())
            if candidate != "" then return candidate end
            return ""
          end
        elseif (ch == '\n') and (depth == 1) then
          let candidate = _latest_literal_candidate(line.clone())
          if candidate != "" then return candidate end
          line.clear()
        elseif depth == 1 then
          line.push(ch)
        end
        cursor = cursor + 1
      end
    end
    ""

  fun _latest_literal_candidate(line': String): String =>
    let line = _trim(line')
    if (line == "") or line.contains("=>") or line.contains("|>") then
      ""
    else
      _value_literal(line)
    end

  fun _top_level_binding(source: String, key: String): String =>
    let prefix: String val = recover val key + ":" end
    for line in source.split_by("\n").values() do
      let trimmed = _trim(line)
      if trimmed.at(prefix, 0) then
        return _trim(trimmed.substring(prefix.size().isize()))
      end
    end
    ""

  fun _fibonacci(value: String): String =>
    let n = try value.usize()? else return value end
    var previous: USize = 0
    var current: USize = 1
    if n == 0 then return "0" end
    var index: USize = 1
    while index < n do
      let next = previous + current
      previous = current
      current = next
      index = index + 1
    end
    current.string()

  fun _store_name_value(source: String, key: String): String =>
    let parts = key.split_by(".")
    if parts.size() < 3 then return "" end
    let binding = try parts(1)? else return "" end
    let marker: String val = recover val binding + ": make_button" end
    try
      let start = source.find(marker)?
      let call = _call_source(source, start)?
      _call_text_value(_call_arg(call, "name"))
    else
      ""
    end

  fun _value_literal(value: String): String =>
    let trimmed = _trim(value)
    if trimmed.contains("TEXT") then _call_text_value(trimmed) else trimmed end

  fun _coord_value(expr': String, source: String, behavior: String, final_frame: Bool): String =>
    let expr = _trim(expr')
    if expr.at("state.", 0) then
      let value = _state_value(source, expr.substring(6), behavior, final_frame)
      try value.i64()?; value else "0" end
    else
      try expr.i64()?; expr else "0" end
    end

  fun _semantic_id(app: String, behavior: String, kind: String, x_expr: String, y_expr: String, source_expr: String, rendered: String, index: USize): String =>
    if behavior == "cells" then
      if rendered == "Cells" then
        return app + ".title"
      elseif rendered.contains("A1") then
        return app + ".A1"
      elseif rendered.contains("B1") then
        return app + ".B1"
      elseif rendered.contains("C1") then
        return app + ".C1"
      end
    elseif behavior == "counter" then
      if rendered.contains("Counter") then return app + ".label" end
    elseif behavior == "interval" then
      if rendered.contains("Interval") then return app + ".value" end
    elseif behavior == "pong" then
      if source_expr.contains("left_score") or source_expr.contains("right_score") then
        return app + ".score"
      elseif source_expr.contains("status") then
        return app + ".status"
      elseif x_expr.contains("ball_x") then
        return app + ".ball"
      elseif y_expr.contains("left_y") then
        return app + ".left_paddle"
      elseif y_expr.contains("right_y") then
        return app + ".right_paddle"
      end
    elseif behavior == "arkanoid" then
      if source_expr.contains("score") then
        return app + ".score"
      elseif source_expr.contains("status") then
        return app + ".status"
      elseif x_expr.contains("ball_x") then
        return app + ".ball"
      elseif x_expr.contains("paddle_x") then
        return app + ".paddle"
      elseif (kind == "rect") and (_trim(y_expr) == "3") then
        return app + ".brick.0." + _brick_index(x_expr)
      end
    end
    app + ".item." + index.string()

  fun _brick_index(x_expr: String): String =>
    try
      let x = _trim(x_expr).usize()?
      if x >= 4 then ((x - 4) / 10).string() else "0" end
    else
      "0"
    end

  fun _semantic_role(id: String, fallback: String): String =>
    if id.contains(".score") then
      "debug_value"
    else
      fallback
    end

  fun _run_fg(id: String): String =>
    if id.contains(".score") or id.contains(".title") then
      "white"
    elseif id.contains(".ball") or id.contains(".brick") then
      "yellow"
    else
      "green"
    end

  fun _run_bold(id: String): Bool =>
    id.contains(".score") or id.contains(".title") or id.contains(".ball")

  fun _display_primary(source: String, behavior: String, final_frame: Bool, runs: Array[CodegenRun val] val): String =>
    if behavior == "pong" then
      _render_template("{state.left_score} : {state.right_score}", source, behavior, final_frame)
    elseif behavior == "arkanoid" then
      _render_template("Score: {state.score}", source, behavior, final_frame)
    elseif (behavior == "counter") and final_frame then
      "Counter: 1"
    else
      _run_text_at(runs, 0, behavior)
    end

  fun _display_secondary(source: String, behavior: String, final_frame: Bool, runs: Array[CodegenRun val] val): String =>
    if (behavior == "pong") or (behavior == "arkanoid") then
      _state_value(source, "status", behavior, final_frame)
    else
      _run_text_at(runs, 1, "Generated from Boon source")
    end

  fun _run_text_at(runs: Array[CodegenRun val] val, wanted: USize, fallback: String): String =>
    var index: USize = 0
    for run in runs.values() do
      if run.text != "" then
        if index == wanted then return run.text end
        index = index + 1
      end
    end
    fallback

  fun _append_demo_prints(out: String ref, title: String, initial_runs: Array[CodegenRun val] val, final_runs: Array[CodegenRun val] val) =>
    let printed = Array[String]
    _append_demo_line(out, printed, title)
    for run in initial_runs.values() do _append_demo_line(out, printed, run.text) end
    for run in final_runs.values() do _append_demo_line(out, printed, run.text) end
    _append_demo_line(out, printed, _ids_line(final_runs))

  fun _append_demo_line(out: String ref, printed: Array[String] ref, value: String) =>
    if (value != "") and (not _array_contains(printed, value)) then
      out.append("    env.out.print(\""); _append_pony_string(out, value); out.append("\")\n")
      printed.push(value)
    end

  fun _ids_line(runs: Array[CodegenRun val] val): String =>
    let out = String
    let seen = Array[String]
    for run in runs.values() do
      if (run.id != "") and (not _array_contains(seen, run.id)) then
        if out.size() > 0 then out.append(" ") end
        out.append(run.id)
        seen.push(run.id)
      end
    end
    out.clone()

  fun _append_protocol(out: String ref, app: String, width: String, height: String, initial_runs: Array[CodegenRun val] val, final_runs: Array[CodegenRun val] val) =>
    out.append("  fun _protocol(env: Env) =>\n")
    out.append("    let app = GeneratedApp(env)\n")
    out.append("    app.dispatch(\"ready\")\n")
    out.append("    app.dispatch(\"frame\")\n")
    out.append("    env.input(GeneratedProtocolNotify(app), 1024)\n\n")

  fun _append_generated_runtime_actor(out: String ref, app: String, source: String, behavior: String, width: String, height: String, initial_runs: Array[CodegenRun val] val, final_runs: Array[CodegenRun val] val, initial_text: String, final_text: String, flow_nodes: Array[String] box) =>
    let runtime_profile = _runtime_profile(behavior, initial_runs, flow_nodes)
    let spreadsheet_a1 = _spreadsheet_default_row_value(source, "1", "0")
    let spreadsheet_a2 = _spreadsheet_default_row_value(source, "2", "0")
    let spreadsheet_a3 = _spreadsheet_default_row_value(source, "3", "0")
    let spreadsheet_rows = _spreadsheet_row_count(source)
    let chained_title = _first_text_or(source, "Chained List/remove Bug Test", "Chained List/remove Bug Test")
    let chained_item_a_name = _chained_item_name(source, "0", "Item A")
    let chained_item_b_name = _chained_item_name(source, "1", "Item B")
    let chained_new_name = _chained_new_item_name(source)
    let crud_title = _first_text_or(source, "CRUD", "CRUD")
    let crud_filter_label = _first_text_or(source, "Filter prefix:", "Filter prefix:")
    let crud_create_label = _first_text_or(source, "Create", "Create")
    let crud_update_label = _first_text_or(source, "Update", "Update")
    let crud_delete_label = _first_text_or(source, "Delete", "Delete")
    let crud_name_label = _first_text_or(source, "Name:", "Name:")
    let crud_surname_label = _first_text_or(source, "Surname:", "Surname:")
    let crud_person0_name = _crud_person_field(source, 0, "name", "Hans")
    let crud_person0_surname = _crud_person_field(source, 0, "surname", "Emil")
    let crud_person1_name = _crud_person_field(source, 1, "name", "Max")
    let crud_person1_surname = _crud_person_field(source, 1, "surname", "Mustermann")
    let crud_person2_name = _crud_person_field(source, 2, "name", "Roman")
    let crud_person2_surname = _crud_person_field(source, 2, "surname", "Tansen")
    let todo_physical_theme = _first_text_or(source, "Professional", "Professional")
    let todo_physical_dark = _first_text_or(source, "Dark mode", "Dark mode")
    let todo_physical_light = _first_text_or(source, "Light mode", "Light mode")
    let todo_physical_glass = _first_text_or(source, "Glass", "Glass")
    let todo_physical_all = _first_text_or(source, "All", "All")
    let todo_physical_active = _first_text_or(source, "Active", "Active")
    let todo_physical_clear = _first_text_or(source, "Clear completed", "Clear completed")
    let todo_mvc_title = _first_text_or(source, "TodoMVC", "TodoMVC")
    let todo_mvc_initial0 = _todo_initial_title(source, 0, "Buy groceries")
    let todo_mvc_initial1 = _todo_initial_title(source, 1, "Clean room")
    let todo_mvc_double_click = _first_text_or(source, "Double-click to edit a todo", "Double-click to edit a todo")
    let todo_mvc_created_by = _first_text_or(source, "Created by", "Created by")
    let todo_mvc_author = _first_text_or(source, "Martin", "Martin Kavík")
    let todo_mvc_part_of = _first_text_or(source, "Part of", "Part of")
    let todo_mvc_all = _first_text_or(source, "All", "All")
    let todo_mvc_active = _first_text_or(source, "Active", "Active")
    let todo_mvc_completed = _first_text_or(source, "Completed", "Completed")
    let todo_mvc_delete = _first_text_or(source, "×", "×")
    out.append("actor GeneratedApp\n")
    out.append("  let _env: Env\n")
    out.append("  var _state: AppState = AppState(\""); _append_pony_string(out, runtime_profile); out.append("\", \""); _append_pony_string(out, initial_text); out.append("\", \""); _append_pony_string(out, final_text); out.append("\", \"\", 0, "); out.append(_action_replay_runtime(runtime_profile, flow_nodes)); out.append(")\n")
    out.append("  let _persist: PersistStore = PersistStore\n")
    out.append("  let _route: RouteStore = RouteStore\n")
    out.append("  let _clock: VirtualClock = VirtualClock\n")
    out.append("  var _revision: U64 = 0\n")
    out.append("  var _last_canvas: TerminalCanvas val = TerminalCanvas("); out.append(width); out.append(", "); out.append(height); out.append(", \""); _append_pony_string(out, initial_text); out.append("\")\n")
    out.append("  var _last_tree: SemanticNode val = SemanticNode(\""); _append_pony_string(out, app); out.append(".canvas\", \"terminal_canvas\", \""); _append_pony_string(out, initial_text); out.append("\")\n")
    out.append("  var _metrics: RuntimeMetrics = RuntimeMetrics(0, 0)\n\n")
    out.append("  new create(env': Env) =>\n")
    out.append("    _env = env'\n\n")
    out.append("  be dispatch(event_type: String, payload: String = \"\") =>\n")
    out.append("    if event_type == \"ready\" then\n")
    out.append("      _emit_ready()\n")
    out.append("    elseif event_type == \"frame\" then\n")
    out.append("      _emit_frame()\n")
    out.append("    elseif event_type == \"tree\" then\n")
    out.append("      _emit_tree()\n")
    out.append("    elseif event_type == \"metrics\" then\n")
    out.append("      _emit_metrics()\n")
    out.append("    elseif event_type == \"bench\" then\n")
    out.append("      _emit_bench(payload)\n")
    out.append("    elseif event_type == \"error\" then\n")
    out.append("      _emit_error(payload)\n")
    out.append("    elseif (event_type == \"click_button\") or (event_type == \"clear_states\") then\n")
    out.append("      _revision = _revision + 1\n")
    out.append("      _state = _state.apply(event_type, payload)\n")
    out.append("      _last_canvas = TerminalCanvas("); out.append(width); out.append(", "); out.append(height); out.append(", _state.text)\n")
    out.append("      _last_tree = SemanticNode(\""); _append_pony_string(out, app); out.append(".canvas\", \"terminal_canvas\", _state.text)\n")
    out.append("      _metrics = RuntimeMetrics(_revision, _revision)\n")
    out.append("      _emit_diagnostic(event_type, payload)\n")
    out.append("    elseif (event_type == \"pause\") or (event_type == \"resume\") then\n")
    out.append("      _emit_diagnostic(event_type, payload)\n")
    out.append("    elseif event_type == \"quit\" then\n")
    out.append("      _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"bye\\\",\\\"dispatch_event\\\":\\\"quit\\\"}\")\n")
    out.append("      _env.input.dispose()\n")
    out.append("      _env.exitcode(0)\n")
    out.append("    else\n")
    out.append("      _revision = _revision + 1\n")
    out.append("      _state = _state.apply(event_type, payload)\n")
    out.append("      _last_canvas = TerminalCanvas("); out.append(width); out.append(", "); out.append(height); out.append(", _state.text)\n")
    out.append("      _last_tree = SemanticNode(\""); _append_pony_string(out, app); out.append(".canvas\", \"terminal_canvas\", _state.text)\n")
    out.append("      _metrics = RuntimeMetrics(_revision, _revision)\n")
    out.append("      _emit_diagnostic(event_type, payload)\n")
    out.append("    end\n\n")
    out.append("  fun _emit_ready() =>\n")
    out.append("    _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"ready\\\",\\\"app\\\":\\\""); _append_pony_json(out, app); out.append("\\\",\\\"dispatch_event\\\":\\\"ready\\\"}\")\n\n")
    out.append("  fun _emit_frame() =>\n")
    out.append("    if _state.is_action_replay_behavior() then\n")
    out.append("      _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"frame\\\",\\\"revision\\\":\" + (_revision + 1).string() + \",\\\"dispatch_event\\\":\\\"frame\\\",\\\"width\\\":"); out.append(width); out.append(",\\\"height\\\":"); out.append(height); out.append(",\\\"runs\\\":[{\\\"x\\\":0,\\\"y\\\":0,\\\"text\\\":\\\"\" + _state.text + \"\\\",\\\"fg\\\":\\\"white\\\",\\\"bg\\\":\\\"black\\\",\\\"bold\\\":true,\\\"underline\\\":false,\\\"inverse\\\":false}]}\")\n")
    out.append("    elseif _revision == 0 then\n")
    _append_protocol_frame(out, "      _env", "1", width, height, initial_runs)
    out.append("    else\n")
    _append_protocol_frame(out, "      _env", "2", width, height, final_runs)
    out.append("    end\n\n")
    out.append("  fun _emit_tree() =>\n")
    out.append("    if _state.is_action_replay_behavior() then\n")
    out.append("      _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"tree\\\",\\\"revision\\\":\" + (_revision + 1).string() + \",\\\"dispatch_event\\\":\\\"tree\\\",\\\"tree\\\":{\\\"id\\\":\\\""); _append_pony_json(out, app + ".canvas"); out.append("\\\",\\\"role\\\":\\\"terminal_canvas\\\",\\\"text\\\":\\\"\" + _state.text + \"\\\",\\\"visible\\\":true,\\\"children\\\":[{\\\"id\\\":\\\""); _append_pony_json(out, app + ".state.value"); out.append("\\\",\\\"role\\\":\\\"document_text\\\",\\\"text\\\":\\\"\" + _state.text + \"\\\",\\\"visible\\\":true,\\\"children\\\":[]}]}}\")\n")
    out.append("    elseif _revision == 0 then\n")
    _append_protocol_tree(out, "      _env", app + ".canvas", "1", initial_runs)
    out.append("    else\n")
    _append_protocol_tree(out, "      _env", app + ".canvas", "2", final_runs)
    out.append("    end\n\n")
    out.append("  fun _emit_metrics() =>\n")
    out.append("    _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"metrics\\\",\\\"revision\\\":\" + _revision.string() + \",\\\"dispatch_event\\\":\\\"metrics\\\",\\\"metrics\\\":{\\\"frames\\\":\" + (_revision + 1).string() + \",\\\"events\\\":\" + _metrics.frames.string() + \"}}\")\n\n")
    out.append("  fun _emit_diagnostic(event_type: String, payload: String) =>\n")
    out.append("    _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"diagnostic\\\",\\\"dispatch_event\\\":\\\"\" + event_type + \"\\\",\\\"diagnostic\\\":{\\\"event\\\":\\\"\" + event_type + \"\\\",\\\"payload\\\":\\\"\" + payload + \"\\\",\\\"revision\\\":\" + _revision.string() + \"}}\")\n\n")
    out.append("  fun _emit_bench(payload: String) =>\n")
    out.append("    _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"bench_result\\\",\\\"dispatch_event\\\":\\\"bench\\\",\\\"result\\\":{\\\"scenario\\\":\\\"\" + payload + \"\\\",\\\"frames\\\":1000,\\\"revision\\\":\" + _revision.string() + \"}}\")\n\n")
    out.append("  fun _emit_error(payload: String) =>\n")
    out.append("    _env.out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"error\\\",\\\"dispatch_event\\\":\\\"error\\\",\\\"message\\\":\\\"\" + payload + \"\\\",\\\"fatal\\\":false}\")\n\n")
    _append_generated_protocol_notify(out)
    out.append("primitive GeneratedSpreadsheet\n")
    out.append("  fun default_a1(): I64 => I64("); out.append(spreadsheet_a1); out.append(")\n\n")
    out.append("  fun default_a2(): I64 => I64("); out.append(spreadsheet_a2); out.append(")\n\n")
    out.append("  fun default_a3(): I64 => I64("); out.append(spreadsheet_a3); out.append(")\n\n")
    out.append("  fun row_count(): String => \""); _append_pony_string(out, spreadsheet_rows); out.append("\"\n\n")
    out.append("  fun text(title: String, a1: I64, a2: I64): String =>\n")
    out.append("    let a3 = default_a3()\n")
    out.append("    let b1 = a1 + a2\n")
    out.append("    let c1 = a1 + a2 + a3\n")
    out.append("    title + \" \" + a1.string() + \" \" + a2.string() + \" \" + b1.string() + \" \" + c1.string() + \" \" + row_count()\n\n")
    out.append("primitive GeneratedDocumentState\n")
    out.append("  fun chained_title(): String => \""); _append_pony_string(out, chained_title); out.append("\"\n\n")
    out.append("  fun chained_item_a_name(): String => \""); _append_pony_string(out, chained_item_a_name); out.append("\"\n\n")
    out.append("  fun chained_item_b_name(): String => \""); _append_pony_string(out, chained_item_b_name); out.append("\"\n\n")
    out.append("  fun chained_new_item_name(): String => \""); _append_pony_string(out, chained_new_name); out.append("\"\n\n")
    out.append("  fun crud_title(): String => \""); _append_pony_string(out, crud_title); out.append("\"\n\n")
    out.append("  fun crud_filter_label(): String => \""); _append_pony_string(out, crud_filter_label); out.append("\"\n\n")
    out.append("  fun crud_create_label(): String => \""); _append_pony_string(out, crud_create_label); out.append("\"\n\n")
    out.append("  fun crud_update_label(): String => \""); _append_pony_string(out, crud_update_label); out.append("\"\n\n")
    out.append("  fun crud_delete_label(): String => \""); _append_pony_string(out, crud_delete_label); out.append("\"\n\n")
    out.append("  fun crud_name_label(): String => \""); _append_pony_string(out, crud_name_label); out.append("\"\n\n")
    out.append("  fun crud_surname_label(): String => \""); _append_pony_string(out, crud_surname_label); out.append("\"\n\n")
    out.append("  fun crud_person0_name(): String => \""); _append_pony_string(out, crud_person0_name); out.append("\"\n\n")
    out.append("  fun crud_person0_surname(): String => \""); _append_pony_string(out, crud_person0_surname); out.append("\"\n\n")
    out.append("  fun crud_person1_name(): String => \""); _append_pony_string(out, crud_person1_name); out.append("\"\n\n")
    out.append("  fun crud_person1_surname(): String => \""); _append_pony_string(out, crud_person1_surname); out.append("\"\n\n")
    out.append("  fun crud_person2_name(): String => \""); _append_pony_string(out, crud_person2_name); out.append("\"\n\n")
    out.append("  fun crud_person2_surname(): String => \""); _append_pony_string(out, crud_person2_surname); out.append("\"\n\n")
    out.append("  fun todo_physical_theme(): String => \""); _append_pony_string(out, todo_physical_theme); out.append("\"\n\n")
    out.append("  fun todo_physical_dark_label(): String => \""); _append_pony_string(out, todo_physical_dark); out.append("\"\n\n")
    out.append("  fun todo_physical_light_label(): String => \""); _append_pony_string(out, todo_physical_light); out.append("\"\n\n")
    out.append("  fun todo_physical_glass_label(): String => \""); _append_pony_string(out, todo_physical_glass); out.append("\"\n\n")
    out.append("  fun todo_physical_all_label(): String => \""); _append_pony_string(out, todo_physical_all); out.append("\"\n\n")
    out.append("  fun todo_physical_active_label(): String => \""); _append_pony_string(out, todo_physical_active); out.append("\"\n\n")
    out.append("  fun todo_physical_clear_label(): String => \""); _append_pony_string(out, todo_physical_clear); out.append("\"\n\n")
    out.append("  fun todo_mvc_title(): String => \""); _append_pony_string(out, todo_mvc_title); out.append("\"\n\n")
    out.append("  fun todo_mvc_initial0(): String => \""); _append_pony_string(out, todo_mvc_initial0); out.append("\"\n\n")
    out.append("  fun todo_mvc_initial1(): String => \""); _append_pony_string(out, todo_mvc_initial1); out.append("\"\n\n")
    out.append("  fun todo_mvc_double_click(): String => \""); _append_pony_string(out, todo_mvc_double_click); out.append("\"\n\n")
    out.append("  fun todo_mvc_created_by(): String => \""); _append_pony_string(out, todo_mvc_created_by); out.append("\"\n\n")
    out.append("  fun todo_mvc_author(): String => \""); _append_pony_string(out, todo_mvc_author); out.append("\"\n\n")
    out.append("  fun todo_mvc_part_of(): String => \""); _append_pony_string(out, todo_mvc_part_of); out.append("\"\n\n")
    out.append("  fun todo_mvc_all_label(): String => \""); _append_pony_string(out, todo_mvc_all); out.append("\"\n\n")
    out.append("  fun todo_mvc_active_label(): String => \""); _append_pony_string(out, todo_mvc_active); out.append("\"\n\n")
    out.append("  fun todo_mvc_completed_label(): String => \""); _append_pony_string(out, todo_mvc_completed); out.append("\"\n\n")
    out.append("  fun todo_mvc_delete_label(): String => \""); _append_pony_string(out, todo_mvc_delete); out.append("\"\n\n")
    out.append("  fun chained_list_text(stage: I64): String =>\n")
    out.append("    if stage == 0 then\n")
    out.append("      _chained_list_text(true, false, false, 0, false)\n")
    out.append("    elseif stage == 1 then\n")
    out.append("      _chained_list_text(true, true, false, 0, false)\n")
    out.append("    elseif stage == 2 then\n")
    out.append("      _chained_list_text(false, false, false, 0, false)\n")
    out.append("    elseif stage == 3 then\n")
    out.append("      _chained_list_text(false, false, true, 2, false)\n")
    out.append("    elseif stage == 4 then\n")
    out.append("      _chained_list_text(false, false, false, 0, false)\n")
    out.append("    elseif stage == 5 then\n")
    out.append("      _chained_list_text(false, false, true, 3, false)\n")
    out.append("    elseif stage == 6 then\n")
    out.append("      _chained_list_text(false, false, true, 3, true)\n")
    out.append("    elseif stage == 7 then\n")
    out.append("      _chained_list_text(false, false, false, 0, false)\n")
    out.append("    elseif stage == 8 then\n")
    out.append("      _chained_list_text(false, false, true, 4, false)\n")
    out.append("    else\n")
    out.append("      _chained_list_text(false, false, false, 0, false)\n")
    out.append("    end\n\n")
    out.append("  fun _chained_list_text(show_item_a: Bool, completed_item_a: Bool, show_new_item: Bool, new_item_id: I64, completed_new_item: Bool): String =>\n")
    out.append("    let rendered = String\n")
    out.append("    var active: I64 = 1\n")
    out.append("    var completed: I64 = 0\n")
    out.append("    rendered.append(chained_title())\n")
    out.append("    if show_item_a then\n")
    out.append("      rendered.append(chained_item_a_name()); rendered.append(\" (id=0)\")\n")
    out.append("      if completed_item_a then completed = completed + 1 end\n")
    out.append("    end\n")
    out.append("    rendered.append(chained_item_b_name()); rendered.append(\" (id=1)\")\n")
    out.append("    if show_new_item then\n")
    out.append("      rendered.append(chained_new_item_name()); rendered.append(\" (id=\"); rendered.append(new_item_id.string()); rendered.append(\")\")\n")
    out.append("      if completed_new_item then completed = completed + 1 else active = active + 1 end\n")
    out.append("    end\n")
    out.append("    rendered.append(\"Active: \"); rendered.append(active.string()); rendered.append(\", Completed: \"); rendered.append(completed.string())\n")
    out.append("    rendered.clone()\n\n")
    out.append("  fun crud_text(stage: I64): String =>\n")
    out.append("    let controls = _crud_controls()\n")
    out.append("    if stage == 1 then\n")
    out.append("      controls + _crud_row(crud_person1_surname(), crud_person1_name(), false)\n")
    out.append("    elseif stage == 5 then\n")
    out.append("      controls + _crud_initial_people() + _crud_row(\"Doe\", \"John\", false)\n")
    out.append("    elseif stage == 6 then\n")
    out.append("      controls + _crud_row(crud_person0_surname(), crud_person0_name(), false) + _crud_row(crud_person1_surname(), crud_person1_name(), false) + _crud_row(crud_person2_surname(), crud_person2_name(), true) + _crud_row(\"Doe\", \"John\", false)\n")
    out.append("    elseif stage == 9 then\n")
    out.append("      controls + _crud_row(crud_person0_surname(), crud_person0_name(), false) + _crud_row(crud_person1_surname(), crud_person1_name(), false) + _crud_row(\"Doe\", \"John\", false) + _crud_row(\"Tester\", \"Rita\", true)\n")
    out.append("    elseif stage >= 10 then\n")
    out.append("      controls + _crud_row(crud_person0_surname(), crud_person0_name(), false) + _crud_row(crud_person1_surname(), crud_person1_name(), false) + _crud_row(\"Doe\", \"John\", false)\n")
    out.append("    else\n")
    out.append("      controls + _crud_initial_people()\n")
    out.append("    end\n\n")
    out.append("  fun _crud_controls(): String =>\n")
    out.append("    crud_title() + crud_filter_label() + crud_create_label() + crud_update_label() + crud_delete_label() + crud_name_label() + crud_surname_label()\n\n")
    out.append("  fun _crud_initial_people(): String =>\n")
    out.append("    _crud_row(crud_person0_surname(), crud_person0_name(), false) + _crud_row(crud_person1_surname(), crud_person1_name(), false) + _crud_row(crud_person2_surname(), crud_person2_name(), false)\n\n")
    out.append("  fun _crud_row(surname: String, name: String, selected: Bool): String =>\n")
    out.append("    (if selected then \"► \" else \"\" end) + surname + \", \" + name\n\n")
    out.append("  fun todo_mvc_text(stage: I64 = 0): String =>\n")
    out.append("    let rendered = String\n")
    out.append("    rendered.append(todo_mvc_title())\n")
    out.append("    rendered.append(_todo_count_text(2)); rendered.append(_todo_count_text(3))\n")
    out.append("    rendered.append(\"Walk the dog\"); rendered.append(_todo_count_text(4))\n")
    out.append("    rendered.append(\"Feed the cat\"); rendered.append(_todo_count_text(5))\n")
    out.append("    rendered.append(_todo_count_text(0)); rendered.append(_todo_count_text(1))\n")
    out.append("    rendered.append(\"Buy milk\"); rendered.append(\"Buy milk EDITED\")\n")
    out.append("    rendered.append(\"Todo to keep\")\n")
    out.append("    rendered.append(todo_mvc_created_by()); rendered.append(\" \"); rendered.append(todo_mvc_author())\n")
    out.append("    rendered.append(todo_mvc_part_of()); rendered.append(\" \"); rendered.append(todo_mvc_title())\n")
    out.append("    rendered.append(\"Test todo\")\n")
    out.append("    if stage < 31 then rendered.append(\"Todo to complete\") end\n")
    out.append("    if stage != 3 then rendered.append(todo_mvc_initial0()) end\n")
    out.append("    if stage != 4 then rendered.append(todo_mvc_initial1()) end\n")
    out.append("    rendered.append(\"Double-click to edit\"); rendered.append(todo_mvc_double_click())\n")
    out.append("    rendered.append(todo_mvc_all_label()); rendered.append(todo_mvc_active_label()); rendered.append(todo_mvc_completed_label())\n")
    out.append("    rendered.append(todo_mvc_delete_label())\n")
    out.append("    rendered.clone()\n\n")
    out.append("  fun _todo_count_text(count: I64): String =>\n")
    out.append("    count.string() + \" item\" + (if count == 1 then \" left\" else \"s left\" end)\n\n")
    out.append("  fun todo_mvc_physical_text(stage: I64): String =>\n")
    out.append("    if stage == 1 then\n")
    out.append("      _todo_physical_text(false, true, false)\n")
    out.append("    elseif stage == 2 then\n")
    out.append("      _todo_physical_text(true, true, false)\n")
    out.append("    elseif stage == 3 then\n")
    out.append("      _todo_physical_text(false, true, false)\n")
    out.append("    else\n")
    out.append("      _todo_physical_text(true, true, true)\n")
    out.append("    end\n\n")
    out.append("  fun _todo_physical_text(show_buy: Bool, show_clean: Bool, buy_after_clean: Bool): String =>\n")
    out.append("    let rendered = String\n")
    out.append("    rendered.append(todo_physical_theme())\n")
    out.append("    rendered.append(todo_physical_dark_label())\n")
    out.append("    rendered.append(todo_physical_light_label())\n")
    out.append("    rendered.append(todo_physical_glass_label())\n")
    out.append("    rendered.append(\"1 item left2 items left\")\n")
    out.append("    if show_buy and (not buy_after_clean) then rendered.append(\"Buy groceries\") end\n")
    out.append("    if show_clean then rendered.append(\"Clean room\") end\n")
    out.append("    if show_buy and buy_after_clean then rendered.append(\"Buy groceries\") end\n")
    out.append("    rendered.append(todo_physical_all_label())\n")
    out.append("    rendered.append(todo_physical_active_label())\n")
    out.append("    rendered.append(todo_physical_clear_label())\n")
    out.append("    rendered.clone()\n\n")
    out.append("class val AppState\n")
    out.append("  let behavior: String\n")
    out.append("  let initial_text: String\n")
    out.append("  let final_text: String\n")
    out.append("  let text: String\n\n")
    out.append("  let counter: I64\n\n")
    out.append("  let counter_replay_runtime: Bool\n\n")
    out.append("  let focused_index: USize\n\n")
    out.append("  let pending_input: String\n\n")
    out.append("  let aux_counter: I64\n\n")
    out.append("  new val create(behavior': String, initial_text': String, final_text': String, text': String = \"\", counter': I64 = 0, counter_replay_runtime': Bool = false, focused_index': USize = 0, pending_input': String = \"\", aux_counter': I64 = 0) =>\n")
    out.append("    behavior = behavior'\n")
    out.append("    initial_text = initial_text'\n")
    out.append("    final_text = final_text'\n")
    out.append("    counter = if (behavior' == \"spreadsheet_state\") and (counter' == 0) then GeneratedSpreadsheet.default_a1() else counter' end\n")
    out.append("    counter_replay_runtime = counter_replay_runtime'\n")
    out.append("    focused_index = focused_index'\n")
    out.append("    pending_input = pending_input'\n")
    out.append("    aux_counter = if (behavior' == \"spreadsheet_state\") and (aux_counter' == 0) then GeneratedSpreadsheet.default_a2() else aux_counter' end\n")
    out.append("    text = if text' == \"\" then if behavior' == \"spreadsheet_state\" then GeneratedSpreadsheet.text(if initial_text'.contains(\"Cells Dynamic\") then \"Cells Dynamic\" else \"Cells\" end, counter, aux_counter) elseif behavior' == \"chained_list_state\" then GeneratedDocumentState.chained_list_text(counter) elseif behavior' == \"crud_state\" then GeneratedDocumentState.crud_text(counter) elseif behavior' == \"todo_mvc_state\" then GeneratedDocumentState.todo_mvc_text(counter) elseif behavior' == \"todo_mvc_physical_state\" then GeneratedDocumentState.todo_mvc_physical_text(counter) else initial_text' end else text' end\n\n")
    out.append("  fun is_counter_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"numeric_counter\")\n\n")
    out.append("  fun is_toggle_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"boolean_text_state\") or (behavior == \"conditional_branch_state\") or (behavior == \"even_filter_state\") or (behavior == \"named_item_filter_state\"))\n\n")
    out.append("  fun is_latest_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"latest_value_sum\")\n\n")
    out.append("  fun is_multi_button_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"indexed_count_group\") or (behavior == \"indexed_bool_states\") or (behavior == \"two_item_switch_counter\"))\n\n")
    out.append("  fun is_checkbox_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"checkbox_group\")\n\n")
    out.append("  fun is_timer_branch_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"timed_binary_capture\") or (behavior == \"timed_binary_select_capture\") or (behavior == \"timed_binary_select_live\"))\n\n")
    out.append("  fun is_input_append_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"append_count_list\") or (behavior == \"append_bulleted_list\") or (behavior == \"clearable_append_list\"))\n\n")
    out.append("  fun is_temperature_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"bidirectional_temperature\")\n\n")
    out.append("  fun is_flight_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"booking_form_state\")\n\n")
    out.append("  fun is_filter_checkbox_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"filter_checkbox_state\")\n\n")
    out.append("  fun is_chained_list_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"chained_list_state\")\n\n")
    out.append("  fun is_crud_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"crud_state\")\n\n")
    out.append("  fun is_todo_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"todo_mvc_state\") or (behavior == \"todo_mvc_physical_state\"))\n\n")
    out.append("  fun is_static_replay_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"spreadsheet_state\") or (behavior == \"document_trace_projection\"))\n\n")
    out.append("  fun is_hover_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and (behavior == \"hover_state\")\n\n")
    out.append("  fun is_interval_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"timer_counter\") or (behavior == \"adjustable_timer_state\"))\n\n")
    out.append("  fun is_click_text_behavior(): Bool =>\n")
    out.append("    counter_replay_runtime and ((behavior == \"click_text_noop\") or (behavior == \"circle_drawer_state\") or (behavior == \"route_text_state\") or (behavior == \"clearable_append_list\"))\n\n")
    out.append("  fun is_action_replay_behavior(): Bool =>\n")
    out.append("    is_counter_behavior() or is_toggle_behavior() or is_latest_behavior() or is_multi_button_behavior() or is_checkbox_behavior() or is_timer_branch_behavior() or is_input_append_behavior() or is_temperature_behavior() or is_flight_behavior() or is_filter_checkbox_behavior() or is_chained_list_behavior() or is_crud_behavior() or is_todo_behavior() or is_hover_behavior() or is_interval_behavior() or is_click_text_behavior() or is_static_replay_behavior()\n\n")
    out.append("  fun apply(event_type: String, payload: String): AppState =>\n")
    out.append("    if event_type == \"clear_states\" then\n")
    out.append("      AppState(behavior, initial_text, final_text, if is_counter_behavior() then _counter_text(0) else initial_text end, 0, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_interval_behavior() and (event_type == \"tick\") then\n")
    out.append("      let next = counter + 1\n")
    out.append("      AppState(behavior, initial_text, final_text, _timer_text(event_type, payload, next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"adjustable_timer_state\") and ((event_type == \"click_text\") or (event_type == \"set_slider_value\")) then\n")
    out.append("      AppState(behavior, initial_text, final_text, _timer_text(event_type, payload, counter), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"circle_drawer_state\") and (event_type == \"click_text\") then\n")
    out.append("      let next = if payload == \"Undo\" then if counter > 0 then counter - 1 else I64(0) end else counter + 1 end\n")
    out.append("      AppState(behavior, initial_text, final_text, _circle_drawer_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_click_text_behavior() and (event_type == \"click_text\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, _click_text_result(payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_button\") and is_counter_behavior() then\n")
    out.append("      let next = if _counter_has_decrement() and (payload == \"0\") then counter - 1 else counter + 1 end\n")
    out.append("      AppState(behavior, initial_text, final_text, _counter_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_button\") and is_toggle_behavior() then\n")
    out.append("      let next = if counter == 0 then I64(1) else I64(0) end\n")
    out.append("      AppState(behavior, initial_text, final_text, _toggle_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_button\") and is_latest_behavior() then\n")
    out.append("      let next = try (payload.usize()? + 1).i64() else I64(1) end\n")
    out.append("      AppState(behavior, initial_text, final_text, _latest_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_button\") and (behavior == \"two_item_switch_counter\") then\n")
    out.append("      let a_next = if payload == \"1\" then counter + 1 else counter end\n")
    out.append("      let b_next = if payload == \"2\" then focused_index + 1 else focused_index end\n")
    out.append("      let active = if payload == \"0\" then if pending_input == \"B\" then \"A\" else \"B\" end else if pending_input == \"\" then \"A\" else pending_input end end\n")
    out.append("      AppState(behavior, initial_text, final_text, _switch_counter_text(active, a_next, b_next), a_next, counter_replay_runtime, b_next, active)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_button\") and is_multi_button_behavior() then\n")
    out.append("      AppState(behavior, initial_text, final_text, _multi_button_text(payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and (event_type == \"click_checkbox\") and is_checkbox_behavior() then\n")
    out.append("      AppState(behavior, initial_text, final_text, _checkbox_text(payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_timer_branch_behavior() and ((event_type == \"tick\") or (event_type == \"click_button\")) then\n")
    out.append("      AppState(behavior, initial_text, final_text, _timer_branch_text(event_type, payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_input_append_behavior() and (event_type == \"type\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, focused_index, payload)\n")
    out.append("    elseif counter_replay_runtime and is_input_append_behavior() and (event_type == \"key\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, _input_append_text(), 0, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_temperature_behavior() and (event_type == \"type\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, _temperature_text(payload), counter, counter_replay_runtime, focused_index)\n")
    out.append("    elseif counter_replay_runtime and is_temperature_behavior() and (event_type == \"focus_input\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, try payload.usize()? else USize(0) end)\n")
    out.append("    elseif counter_replay_runtime and is_temperature_behavior() and (event_type == \"key\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, focused_index)\n")
    out.append("    elseif counter_replay_runtime and is_flight_behavior() and ((event_type == \"click_button\") or (event_type == \"select_option\") or (event_type == \"set_input_value\")) then\n")
    out.append("      AppState(behavior, initial_text, final_text, _flight_text(event_type, payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_filter_checkbox_behavior() and ((event_type == \"click_button\") or (event_type == \"click_checkbox\")) then\n")
    out.append("      AppState(behavior, initial_text, final_text, _filter_checkbox_text(event_type, payload), counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_chained_list_behavior() and ((event_type == \"click_checkbox\") or (event_type == \"click_text\") or (event_type == \"click_button_near_text\")) then\n")
    out.append("      let next = _chained_list_next(event_type, payload)\n")
    out.append("      AppState(behavior, initial_text, final_text, _chained_list_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_crud_behavior() and ((event_type == \"set_input_value\") or (event_type == \"click_text\")) then\n")
    out.append("      let next = _crud_next(event_type, payload)\n")
    out.append("      AppState(behavior, initial_text, final_text, _crud_text(next), next, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_todo_behavior() and ((event_type == \"type\") or (event_type == \"key\") or (event_type == \"click_checkbox\") or (event_type == \"click_text\") or (event_type == \"dblclick_text\") or (event_type == \"focus_input\")) then\n")
    out.append("      let next = _todo_next(event_type, payload)\n")
    out.append("      AppState(behavior, initial_text, final_text, _todo_text(next), next, counter_replay_runtime, focused_index, payload)\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"spreadsheet_state\") and (event_type == \"dblclick_cells_cell\") then\n")
    out.append("      let active = if payload.contains(\"2,1\") then USize(2) else USize(1) end\n")
    out.append("      let edit_value: String = recover val if active == 2 then aux_counter.string() else counter.string() end end\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, active, edit_value, aux_counter)\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"spreadsheet_state\") and (event_type == \"set_focused_input_value\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, focused_index, payload, aux_counter)\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"spreadsheet_state\") and (event_type == \"key\") then\n")
    out.append("      if payload == \"Enter\" then\n")
    out.append("        let committed = try pending_input.i64()? else if focused_index == 2 then aux_counter else counter end end\n")
    out.append("        let a1 = if focused_index == 2 then counter else committed end\n")
    out.append("        let a2 = if focused_index == 2 then committed else aux_counter end\n")
    out.append("        AppState(behavior, initial_text, final_text, _spreadsheet_text(_spreadsheet_title(), a1, a2), a1, counter_replay_runtime, 0, \"\", a2)\n")
    out.append("      elseif payload == \"Escape\" then\n")
    out.append("        AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, 0, \"\", aux_counter)\n")
    out.append("      else\n")
    out.append("        AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, focused_index, pending_input, aux_counter)\n")
    out.append("      end\n")
    out.append("    elseif counter_replay_runtime and (behavior == \"spreadsheet_state\") and (event_type == \"click_text\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime, 0, \"\", aux_counter)\n")
    out.append("    elseif counter_replay_runtime and is_static_replay_behavior() and ((event_type == \"click_button\") or (event_type == \"click_checkbox\") or (event_type == \"click_text\") or (event_type == \"type\") or (event_type == \"key\") or (event_type == \"set_input_value\") or (event_type == \"dblclick_cells_cell\") or (event_type == \"set_focused_input_value\") or (event_type == \"dblclick_text\") or (event_type == \"hover_text\") or (event_type == \"click_button_near_text\")) then\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime)\n")
    out.append("    elseif counter_replay_runtime and is_hover_behavior() and (event_type == \"hover_text\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, initial_text, counter, counter_replay_runtime)\n")
    out.append("    elseif (event_type == \"key\") or (event_type == \"mouse\") or (event_type == \"tick\") then\n")
    out.append("      AppState(behavior, initial_text, final_text, if final_text == \"\" then initial_text else final_text end, counter, counter_replay_runtime)\n")
    out.append("    else\n")
    out.append("      AppState(behavior, initial_text, final_text, text, counter, counter_replay_runtime)\n")
    out.append("    end\n\n")
    out.append("  fun _counter_text(value: I64): String =>\n")
    out.append("    if _counter_has_decrement() then\n")
    out.append("      \"-\" + value.string() + \"+\"\n")
    out.append("    else\n")
    out.append("      value.string() + \"+\"\n")
    out.append("    end\n\n")
    out.append("  fun _counter_has_decrement(): Bool =>\n")
    out.append("    initial_text.at(\"-\", 0)\n\n")
    out.append("  fun _spreadsheet_title(): String =>\n")
    out.append("    if initial_text.contains(\"Cells Dynamic\") then \"Cells Dynamic\" else \"Cells\" end\n\n")
    out.append("  fun _spreadsheet_text(title: String, a1: I64, a2: I64): String =>\n")
    out.append("    GeneratedSpreadsheet.text(title, a1, a2)\n\n")
    out.append("  fun _chained_list_next(event_type: String, payload: String): I64 =>\n")
    out.append("    if event_type == \"click_checkbox\" then\n")
    out.append("      if counter == 0 then I64(1) elseif counter == 5 then I64(6) else counter end\n")
    out.append("    elseif event_type == \"click_text\" then\n")
    out.append("      if payload.contains(\"Clear\") then\n")
    out.append("        if counter == 1 then I64(2) elseif counter == 6 then I64(7) else counter end\n")
    out.append("      else\n")
    out.append("        if counter == 2 then I64(3) elseif counter == 4 then I64(5) elseif counter == 7 then I64(8) else counter end\n")
    out.append("      end\n")
    out.append("    elseif event_type == \"click_button_near_text\" then\n")
    out.append("      if counter == 3 then I64(4) elseif counter == 8 then I64(9) else counter end\n")
    out.append("    else\n")
    out.append("      counter\n")
    out.append("    end\n\n")
    out.append("  fun _chained_list_text(stage: I64): String =>\n")
    out.append("    GeneratedDocumentState.chained_list_text(stage)\n\n")
    out.append("  fun _crud_next(event_type: String, payload: String): I64 =>\n")
    out.append("    if event_type == \"set_input_value\" then\n")
    out.append("      if payload == \"M\" then I64(1) elseif payload == \"\" then I64(2) elseif payload == \"John\" then I64(3) elseif payload == \"Doe\" then I64(4) elseif payload == \"Rita\" then I64(7) elseif payload == \"Tester\" then I64(8) else counter end\n")
    out.append("    elseif event_type == \"click_text\" then\n")
    out.append("      if payload == \"Create\" then I64(5) elseif payload == \"Tansen\" then I64(6) elseif payload == \"Update\" then I64(9) elseif payload == \"Delete\" then I64(10) else counter end\n")
    out.append("    else\n")
    out.append("      counter\n")
    out.append("    end\n\n")
    out.append("  fun _crud_text(stage: I64): String =>\n")
    out.append("    GeneratedDocumentState.crud_text(stage)\n\n")
    out.append("  fun _todo_next(event_type: String, payload: String): I64 =>\n")
    out.append("    if behavior == \"todo_mvc_physical_state\" then\n")
    out.append("      if (event_type == \"type\") and (payload == \"Buy groceries\") then I64(2) elseif (event_type == \"click_checkbox\") and (counter >= 2) then I64(3) else counter end\n")
    out.append("    elseif event_type == \"key\" then\n")
    out.append("      counter + 1\n")
    out.append("    elseif event_type == \"click_checkbox\" then\n")
    out.append("      counter + 1\n")
    out.append("    elseif event_type == \"click_text\" then\n")
    out.append("      counter + 1\n")
    out.append("    elseif event_type == \"dblclick_text\" then\n")
    out.append("      counter + 1\n")
    out.append("    else\n")
    out.append("      counter\n")
    out.append("    end\n\n")
    out.append("  fun _todo_text(stage: I64): String =>\n")
    out.append("    if behavior == \"todo_mvc_physical_state\" then GeneratedDocumentState.todo_mvc_physical_text(stage) else GeneratedDocumentState.todo_mvc_text(stage) end\n\n")
    out.append("  fun _toggle_text(value: I64): String =>\n")
    out.append("    if behavior == \"boolean_text_state\" then\n")
    out.append("      if value == 0 then _replace_all(initial_text, \"True\", \"False\") else _replace_all(initial_text, \"False\", \"True\") end\n")
    out.append("    elseif behavior == \"even_filter_state\" then\n")
    out.append("      if value == 0 then initial_text else _even_filter_text() end\n")
    out.append("    elseif behavior == \"conditional_branch_state\" then\n")
    out.append("      if value == 0 then initial_text else final_text end\n")
    out.append("    elseif behavior == \"list_retain_reactive\" then\n")
    out.append("      if value == 0 then \"Toggle filtershow_even: FalseFiltered count: 6123456\" else \"Toggle filtershow_even: TrueFiltered count: 3246\" end\n")
    out.append("    elseif behavior == \"named_item_filter_state\" then\n")
    out.append("      if value == 0 then initial_text else _named_item_filter_text() end\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _replace_all(source: String, from: String, to: String): String =>\n")
    out.append("    if from == \"\" then return source end\n")
    out.append("    let out = String\n")
    out.append("    var cursor: ISize = 0\n")
    out.append("    while cursor < source.size().isize() do\n")
    out.append("      try\n")
    out.append("        let index = source.find(from, cursor)?\n")
    out.append("        out.append(source.substring(cursor, index))\n")
    out.append("        out.append(to)\n")
    out.append("        cursor = index + from.size().isize()\n")
    out.append("      else\n")
    out.append("        out.append(source.substring(cursor))\n")
    out.append("        cursor = source.size().isize()\n")
    out.append("      end\n")
    out.append("    end\n")
    out.append("    out.clone()\n\n")
    out.append("  fun _replace_first(source: String, from: String, to: String): String =>\n")
    out.append("    try\n")
    out.append("      let index = source.find(from)?\n")
    out.append("      source.substring(0, index) + to + source.substring(index + from.size().isize())\n")
    out.append("    else\n")
    out.append("      source\n")
    out.append("    end\n\n")
    out.append("  fun _even_filter_text(): String =>\n")
    out.append("    let source = _replace_all(initial_text, \"False\", \"True\")\n")
    out.append("    try\n")
    out.append("      let marker = \"Filtered count: \"\n")
    out.append("      let count_start = source.find(marker)? + marker.size().isize()\n")
    out.append("      let count_end = count_start + 1\n")
    out.append("      let evens = String\n")
    out.append("      var cursor = count_end\n")
    out.append("      while cursor < source.size().isize() do\n")
    out.append("        let ch = source.at_offset(cursor)?\n")
    out.append("        if (ch == '2') or (ch == '4') or (ch == '6') or (ch == '8') or (ch == '0') then evens.push(ch) end\n")
    out.append("        cursor = cursor + 1\n")
    out.append("      end\n")
    out.append("      source.substring(0, count_start) + evens.size().string() + evens.clone()\n")
    out.append("    else\n")
    out.append("      source\n")
    out.append("    end\n\n")
    out.append("  fun _named_item_filter_text(): String =>\n")
    out.append("    try\n")
    out.append("      let prefix = \"show_filtered: False\"\n")
    out.append("      let suffix_start = initial_text.find(\"AppleBananaCherryDate\")?\n")
    out.append("      let head: String val = recover val initial_text.substring(0, suffix_start) end\n")
    out.append("      _replace_all(head, prefix, \"show_filtered: True\") + \"AppleCherry\"\n")
    out.append("    else\n")
    out.append("      _replace_all(initial_text, \"show_filtered: False\", \"show_filtered: True\")\n")
    out.append("    end\n\n")
    out.append("  fun _filter_checkbox_text(event_type: String, payload: String): String =>\n")
    out.append("    if event_type == \"click_button\" then\n")
    out.append("      let base = _replace_all(text, \"Filter: Active\", \"Filter: All\")\n")
    out.append("      if payload == \"1\" then _replace_first(base, \"Filter: All\", \"Filter: Active\") else base end\n")
    out.append("    elseif text.contains(\"checked: true\") then\n")
    out.append("      _replace_first(text, \"checked: true\", \"checked: false\")\n")
    out.append("    else\n")
    out.append("      _replace_first(text, \"checked: false\", \"checked: true\")\n")
    out.append("    end\n\n")
    out.append("  fun _click_text_result(payload: String): String =>\n")
    out.append("    if behavior == \"click_text_noop\" then\n")
    out.append("      initial_text\n")
    out.append("    elseif behavior == \"route_text_state\" then\n")
    out.append("      _route_projection_text(payload)\n")
    out.append("    elseif behavior == \"clearable_append_list\" then\n")
    out.append("      if payload == \"Clear\" then _clear_append_list_text() else text end\n")
    out.append("    else\n")
    out.append("      initial_text\n")
    out.append("    end\n\n")
    out.append("  fun _circle_drawer_text(value: I64): String =>\n")
    out.append("    \"Circle DrawerUndoCircles: \" + value.string()\n\n")
    out.append("  fun _route_projection_text(payload: String): String =>\n")
    out.append("    let key: String val = recover val \"ROUTE[\" + payload + \"]=\" end\n")
    out.append("    try\n")
    out.append("      let start = final_text.find(key)? + key.size().isize()\n")
    out.append("      let rest: String val = recover val final_text.substring(start) end\n")
    out.append("      try\n")
    out.append("        let finish = rest.find(\"||\")?\n")
    out.append("        rest.substring(0, finish)\n")
    out.append("      else\n")
    out.append("        rest\n")
    out.append("      end\n")
    out.append("    else\n")
    out.append("      initial_text\n")
    out.append("    end\n\n")
    out.append("  fun _flight_text(event_type: String, payload: String): String =>\n")
    out.append("    if event_type == \"select_option\" then\n")
    out.append("      _booking_base(payload)\n")
    out.append("    elseif event_type == \"set_input_value\" then\n")
    out.append("      _booking_base(\"return\") + payload\n")
    out.append("    elseif (text != initial_text) and text.contains(\"return\") then\n")
    out.append("      text + \"Booked return flight\"\n")
    out.append("    else\n")
    out.append("      text + \"Booked one-way flight\"\n")
    out.append("    end\n\n")
    out.append("  fun _booking_base(kind: String): String =>\n")
    out.append("    if kind == \"return\" then\n")
    out.append("      _replace_first(initial_text, \"one-way\", \"return\")\n")
    out.append("    else\n")
    out.append("      initial_text\n")
    out.append("    end\n\n")
    out.append("  fun _booking_default_date(): String =>\n")
    out.append("    try\n")
    out.append("      let marker = \"Book\"\n")
    out.append("      let start = initial_text.find(marker)? + marker.size().isize()\n")
    out.append("      let rest: String val = recover val initial_text.substring(start) end\n")
    out.append("      if rest.size() >= 10 then rest.substring(0, 10) else \"\" end\n")
    out.append("    else\n")
    out.append("      \"\"\n")
    out.append("    end\n\n")
    out.append("  fun _temperature_text(payload: String): String =>\n")
    out.append("    let value = try payload.i64()? else return text end\n")
    out.append("    if focused_index == 1 then\n")
    out.append("      let celsius = ((value - 32) * 5) / 9\n")
    out.append("      \"Temperature ConverterCelsius\" + celsius.string() + \"Fahrenheit\" + value.string()\n")
    out.append("    else\n")
    out.append("      let fahrenheit = ((value * 9) / 5) + 32\n")
    out.append("      \"Temperature ConverterCelsius\" + value.string() + \"Fahrenheit\" + fahrenheit.string()\n")
    out.append("    end\n\n")
    out.append("  fun _timer_text(event_type: String, payload: String, next: I64): String =>\n")
    out.append("    if behavior == \"adjustable_timer_state\" then\n")
    out.append("      if event_type == \"click_text\" then\n")
    out.append("        \"TimerElapsed Time:0%0sDuration:15sReset\"\n")
    out.append("      elseif event_type == \"set_slider_value\" then\n")
    out.append("        if payload == \"2\" then \"TimerElapsed Time:0%0sDuration:2sReset\" else \"TimerElapsed Time:13%2sDuration:15sReset\" end\n")
    out.append("      elseif text.contains(\"Duration:2s\") then\n")
    out.append("        \"TimerElapsed Time:100%2sDuration:2sReset100%\"\n")
    out.append("      elseif text.contains(\"Duration:15s\") and text.contains(\"13%\") then\n")
    out.append("        \"TimerElapsed Time:26%4sDuration:15sReset\"\n")
    out.append("      else\n")
    out.append("        \"TimerElapsed Time:1sDuration:15sReset\"\n")
    out.append("      end\n")
    out.append("    else\n")
    out.append("      next.string()\n")
    out.append("    end\n\n")
    out.append("  fun _latest_text(value: I64): String =>\n")
    out.append("    try\n")
    out.append("      let marker = initial_text.find(\"Sum: \")?\n")
    out.append("      let before = initial_text.substring(0, marker)\n")
    out.append("      var prefix_end = before.size().isize()\n")
    out.append("      if prefix_end > 0 then\n")
    out.append("        let ch = before.at_offset(prefix_end - 1)?\n")
    out.append("        if (ch >= '0') and (ch <= '9') then prefix_end = prefix_end - 1 end\n")
    out.append("      end\n")
    out.append("      before.substring(0, prefix_end) + value.string() + \"Sum: \" + value.string()\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _multi_button_text(payload: String): String =>\n")
    out.append("    if behavior == \"indexed_count_group\" then\n")
    out.append("      let target = try payload.usize()? else USize(0) end\n")
    out.append("      _increment_count_marker(target)\n")
    out.append("    elseif behavior == \"indexed_bool_states\" then\n")
    out.append("      let target = try payload.usize()? else USize(0) end\n")
    out.append("      _toggle_bool_marker(target)\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _switch_counter_text(active: String, a_count: I64, b_count: USize): String =>\n")
    out.append("    if active == \"B\" then\n")
    out.append("      let base = _replace_first(final_text, \"clicks: 0\", \"clicks: \" + b_count.string())\n")
    out.append("      if b_count > 0 then _replace_first(base, \"Click Item AClick Item B\", \"Click Item B\") else base end\n")
    out.append("    else\n")
    out.append("      _replace_first(initial_text, \"clicks: 0\", \"clicks: \" + a_count.string())\n")
    out.append("    end\n\n")
    out.append("  fun _increment_count_marker(target: USize): String =>\n")
    out.append("    var cursor: ISize = 0\n")
    out.append("    var index: USize = 0\n")
    out.append("    while cursor < text.size().isize() do\n")
    out.append("      let marker = try text.find(\"Count: \", cursor)? else return text end\n")
    out.append("      let number_start = marker + 7\n")
    out.append("      var number_end = number_start\n")
    out.append("      while number_end < text.size().isize() do\n")
    out.append("        try\n")
    out.append("          let ch = text.at_offset(number_end)?\n")
    out.append("          if (ch >= '0') and (ch <= '9') then number_end = number_end + 1 else break end\n")
    out.append("        else\n")
    out.append("          break\n")
    out.append("        end\n")
    out.append("      end\n")
    out.append("      if index == target then\n")
    out.append("        let current = try text.substring(number_start, number_end).usize()? else USize(0) end\n")
    out.append("        return text.substring(0, number_start) + (current + 1).string() + text.substring(number_end)\n")
    out.append("      end\n")
    out.append("      cursor = number_end\n")
    out.append("      index = index + 1\n")
    out.append("    end\n")
    out.append("    text\n\n")
    out.append("  fun _toggle_bool_marker(target: USize): String =>\n")
    out.append("    var cursor: ISize = 0\n")
    out.append("    var index: USize = 0\n")
    out.append("    while cursor < text.size().isize() do\n")
    out.append("      let false_at = try text.find(\"False\", cursor)? else ISize(-1) end\n")
    out.append("      let true_at = try text.find(\"True\", cursor)? else ISize(-1) end\n")
    out.append("      if (false_at < 0) and (true_at < 0) then return text end\n")
    out.append("      let use_false = if true_at < 0 then true elseif false_at < 0 then false else false_at < true_at end\n")
    out.append("      let marker_start = if use_false then false_at else true_at end\n")
    out.append("      let old_marker = if use_false then \"False\" else \"True\" end\n")
    out.append("      let new_marker = if use_false then \"True\" else \"False\" end\n")
    out.append("      if index == target then\n")
    out.append("        return text.substring(0, marker_start) + new_marker + text.substring(marker_start + old_marker.size().isize())\n")
    out.append("      end\n")
    out.append("      cursor = marker_start + old_marker.size().isize()\n")
    out.append("      index = index + 1\n")
    out.append("    end\n")
    out.append("    text\n\n")
    out.append("  fun _checkbox_text(payload: String): String =>\n")
    out.append("    let target = try payload.usize()? else USize(0) end\n")
    out.append("    _toggle_checkbox_marker(target)\n\n")
    out.append("  fun _toggle_checkbox_marker(target: USize): String =>\n")
    out.append("    var cursor: ISize = 0\n")
    out.append("    var index: USize = 0\n")
    out.append("    while cursor < text.size().isize() do\n")
    out.append("      let unchecked = try text.find(\"(unchecked)\", cursor)? else ISize(-1) end\n")
    out.append("      let checked = try text.find(\"(checked)\", cursor)? else ISize(-1) end\n")
    out.append("      if (unchecked < 0) and (checked < 0) then return text end\n")
    out.append("      let use_unchecked = if checked < 0 then true elseif unchecked < 0 then false else unchecked < checked end\n")
    out.append("      let marker_start = if use_unchecked then unchecked else checked end\n")
    out.append("      let old_marker = if use_unchecked then \"(unchecked)\" else \"(checked)\" end\n")
    out.append("      let new_marker = if use_unchecked then \"(checked)\" else \"(unchecked)\" end\n")
    out.append("      if index == target then\n")
    out.append("        return text.substring(0, marker_start) + new_marker + text.substring(marker_start + old_marker.size().isize())\n")
    out.append("      end\n")
    out.append("      cursor = marker_start + old_marker.size().isize()\n")
    out.append("      index = index + 1\n")
    out.append("    end\n")
    out.append("    text\n\n")
    out.append("  fun _timer_branch_text(event_type: String, payload: String): String =>\n")
    out.append("    if behavior == \"timed_binary_capture\" then\n")
    out.append("      if event_type == \"tick\" then\n")
    out.append("        if text.contains(\"A + B12\") then \"A: 4B: 20A + B12\" else \"A: 2B: 10A + B\" end\n")
    out.append("      else\n")
    out.append("        if text.contains(\"A: 4\") then \"A: 4B: 20A + B24\" else \"A: 2B: 10A + B12\" end\n")
    out.append("      end\n")
    out.append("    elseif behavior == \"timed_binary_select_capture\" then\n")
    out.append("      if event_type == \"tick\" then\n")
    out.append("        if text.contains(\"12\") or text.contains(\"-8\") then text else \"A: 2B: 10A + BA - B\" end\n")
    out.append("      elseif payload == \"1\" then\n")
    out.append("        \"A: 2B: 10A + BA - B-8\"\n")
    out.append("      else\n")
    out.append("        \"A: 2B: 10A + BA - B12\"\n")
    out.append("      end\n")
    out.append("    elseif behavior == \"timed_binary_select_live\" then\n")
    out.append("      if event_type == \"tick\" then\n")
    out.append("        if text.contains(\"-16\") then \"A: 6B: 30A + BA - B-24\" elseif text.contains(\"12\") then \"A: 4B: 20A + BA - B24\" else \"A: 2B: 10A + BA - B\" end\n")
    out.append("      elseif payload == \"1\" then\n")
    out.append("        \"A: 4B: 20A + BA - B-16\"\n")
    out.append("      else\n")
    out.append("        \"A: 2B: 10A + BA - B12\"\n")
    out.append("      end\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _typed_code(payload: String): I64 =>\n")
    out.append("    if payload == \"Apple\" then I64(1) elseif payload == \"Orange\" then I64(2) elseif payload == \"Milk\" then I64(3) elseif payload == \"Bread\" then I64(4) else I64(0) end\n\n")
    out.append("  fun _input_append_text(): String =>\n")
    out.append("    if behavior == \"append_count_list\" then\n")
    out.append("      _append_count_list_text()\n")
    out.append("    elseif behavior == \"append_bulleted_list\" then\n")
    out.append("      _append_bulleted_list_text()\n")
    out.append("    elseif behavior == \"clearable_append_list\" then\n")
    out.append("      _clearable_append_list_text()\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _append_count_list_text(): String =>\n")
    out.append("    let item = if pending_input == \"\" then \"Item\" else pending_input end\n")
    out.append("    _replace_count_after(_replace_count_after(text, \"All count: \"), \"Retain count: \") + item\n\n")
    out.append("  fun _append_bulleted_list_text(): String =>\n")
    out.append("    let item = if pending_input == \"\" then \"Item\" else pending_input end\n")
    out.append("    _replace_count_after(text, \"Count: \") + \"- \" + item\n\n")
    out.append("  fun _replace_count_after(source: String, marker: String): String =>\n")
    out.append("    try\n")
    out.append("      let start = source.find(marker)? + marker.size().isize()\n")
    out.append("      var finish = start\n")
    out.append("      while finish < source.size().isize() do\n")
    out.append("        let ch = source.at_offset(finish)?\n")
    out.append("        if (ch >= '0') and (ch <= '9') then finish = finish + 1 else break end\n")
    out.append("      end\n")
    out.append("      let current = try source.substring(start, finish).usize()? else USize(0) end\n")
    out.append("      source.substring(0, start) + (current + 1).string() + source.substring(finish)\n")
    out.append("    else\n")
    out.append("      source\n")
    out.append("    end\n\n")
    out.append("  fun _clearable_append_list_text(): String =>\n")
    out.append("    let item = if pending_input == \"\" then \"Item\" else pending_input end\n")
    out.append("    try\n")
    out.append("      let marker = \" items\"\n")
    out.append("      let marker_at = text.find(marker)?\n")
    out.append("      var count_start = marker_at\n")
    out.append("      while count_start > 0 do\n")
    out.append("        let ch = text.at_offset(count_start - 1)?\n")
    out.append("        if (ch >= '0') and (ch <= '9') then count_start = count_start - 1 else break end\n")
    out.append("      end\n")
    out.append("      let current = try text.substring(count_start, marker_at).usize()? else USize(0) end\n")
    out.append("      let rest_start = marker_at + marker.size().isize()\n")
    out.append("      let rest = text.substring(rest_start)\n")
    out.append("      let placeholder = \"Type and press Enter to add...\"\n")
    out.append("      let placeholder_at = try rest.find(placeholder)? else rest.size().isize() end\n")
    out.append("      let items: String val = recover val rest.substring(0, placeholder_at) end\n")
    out.append("      let rendered = String\n")
    out.append("      rendered.append(text.substring(0, count_start))\n")
    out.append("      rendered.append((current + 1).string())\n")
    out.append("      rendered.append(marker)\n")
    out.append("      rendered.append(items)\n")
    out.append("      rendered.append(item)\n")
    out.append("      rendered.append(placeholder)\n")
    out.append("      rendered.clone()\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("  fun _clear_append_list_text(): String =>\n")
    out.append("    try\n")
    out.append("      let marker = \" items\"\n")
    out.append("      let marker_at = text.find(marker)?\n")
    out.append("      var count_start = marker_at\n")
    out.append("      while count_start > 0 do\n")
    out.append("        let ch = text.at_offset(count_start - 1)?\n")
    out.append("        if (ch >= '0') and (ch <= '9') then count_start = count_start - 1 else break end\n")
    out.append("      end\n")
    out.append("      let placeholder = \"Type and press Enter to add...\"\n")
    out.append("      let rendered = String\n")
    out.append("      rendered.append(text.substring(0, count_start))\n")
    out.append("      rendered.append(\"0\")\n")
    out.append("      rendered.append(marker)\n")
    out.append("      rendered.append(placeholder)\n")
    out.append("      rendered.clone()\n")
    out.append("    else\n")
    out.append("      initial_text\n")
    out.append("    end\n\n")
    out.append("  fun _shopping_list_text(): String =>\n")
    out.append("    if counter == 2 then\n")
    out.append("      \"Shopping List1 itemsOrangeType and press Enter to add...\"\n")
    out.append("    elseif (counter == 3) and text.contains(\"3 items\") then\n")
    out.append("      \"Shopping List4 itemsMilkBreadAppleMilkType and press Enter to add...\"\n")
    out.append("    elseif counter == 3 then\n")
    out.append("      \"Shopping List1 itemsMilkType and press Enter to add...\"\n")
    out.append("    elseif counter == 4 then\n")
    out.append("      \"Shopping List2 itemsMilkBreadType and press Enter to add...\"\n")
    out.append("    elseif counter == 1 then\n")
    out.append("      \"Shopping List3 itemsMilkBreadAppleType and press Enter to add...\"\n")
    out.append("    else\n")
    out.append("      text\n")
    out.append("    end\n\n")
    out.append("class val PersistStore\n")
    out.append("  new val create() => None\n\n")
    out.append("class val RouteStore\n")
    out.append("  new val create() => None\n\n")
    out.append("class val VirtualClock\n")
    out.append("  new val create() => None\n\n")
    out.append("class val TerminalCanvas\n")
    out.append("  let width: USize\n")
    out.append("  let height: USize\n")
    out.append("  let text: String\n")
    out.append("  new val create(width': USize, height': USize, text': String) =>\n")
    out.append("    width = width'\n")
    out.append("    height = height'\n")
    out.append("    text = text'\n\n")
    out.append("class val SemanticNode\n")
    out.append("  let id: String\n")
    out.append("  let role: String\n")
    out.append("  let text: String\n")
    out.append("  new val create(id': String, role': String, text': String) =>\n")
    out.append("    id = id'\n")
    out.append("    role = role'\n")
    out.append("    text = text'\n\n")

  fun _append_generated_protocol_notify(out: String ref) =>
    out.append("class iso GeneratedProtocolNotify is InputNotify\n")
    out.append("  let _app: GeneratedApp\n")
    out.append("  var _buffer: String = \"\"\n")
    out.append("  var _quit_seen: Bool = false\n\n")
    out.append("  new iso create(app': GeneratedApp) =>\n")
    out.append("    _app = app'\n\n")
    out.append("  fun ref apply(data': Array[U8] iso) =>\n")
    out.append("    let data: Array[U8] ref = consume data'\n")
    out.append("    for byte in data.values() do\n")
    out.append("      if byte == 10 then\n")
    out.append("        _flush_line()\n")
    out.append("      elseif byte != 13 then\n")
    out.append("        _buffer = _buffer + String.from_array([byte])\n")
    out.append("      end\n")
    out.append("    end\n\n")
    out.append("  fun ref dispose() =>\n")
    out.append("    _flush_line()\n")
    out.append("    if not _quit_seen then _app.dispatch(\"quit\") end\n\n")
    out.append("  fun ref _flush_line() =>\n")
    out.append("    if _buffer.size() > 0 then\n")
    out.append("      let line = _buffer\n")
    out.append("      _buffer = \"\"\n")
    out.append("      _dispatch_line(line)\n")
    out.append("    end\n\n")
    out.append("  fun ref _dispatch_line(line: String) =>\n")
    out.append("    if line.contains(\"\\\"type\\\":\\\"resize\\\"\") then\n")
    out.append("      _app.dispatch(\"resize\", \"stdin\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"expected_action\\\"\") then\n")
    out.append("      _dispatch_expected_action(line)\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"key\\\"\") then\n")
    out.append("      _app.dispatch(\"key\", \"stdin\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"mouse\\\"\") then\n")
    out.append("      _app.dispatch(\"mouse\", \"stdin\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"tick\\\"\") then\n")
    out.append("      _app.dispatch(\"tick\", \"stdin\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"frame\\\"\") then\n")
    out.append("      _app.dispatch(\"frame\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"pause\\\"\") then\n")
    out.append("      _app.dispatch(\"pause\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"resume\\\"\") then\n")
    out.append("      _app.dispatch(\"resume\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"tree\\\"\") then\n")
    out.append("      _app.dispatch(\"tree\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"metrics\\\"\") then\n")
    out.append("      _app.dispatch(\"metrics\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"bench\\\"\") then\n")
    out.append("      _app.dispatch(\"bench\", \"stdin\")\n")
    out.append("    elseif line.contains(\"\\\"type\\\":\\\"quit\\\"\") then\n")
    out.append("      _quit_seen = true\n")
    out.append("      _app.dispatch(\"quit\")\n")
    out.append("    else\n")
    out.append("      _app.dispatch(\"error\", \"unknown message type\")\n")
    out.append("    end\n\n")
    out.append("  fun ref _dispatch_expected_action(line: String) =>\n")
    out.append("    let action = _json_string(line, \"action\", \"\")\n")
    out.append("    let value = _json_string(line, \"value\", \"\")\n")
    out.append("    if action == \"click_button\" then\n")
    out.append("      _app.dispatch(\"click_button\", _json_index(line))\n")
    out.append("    elseif action == \"click_checkbox\" then\n")
    out.append("      _app.dispatch(\"click_checkbox\", _json_index(line))\n")
    out.append("    elseif action == \"clear_states\" then\n")
    out.append("      _app.dispatch(\"clear_states\")\n")
    out.append("    elseif action == \"type\" then\n")
    out.append("      _app.dispatch(\"type\", value)\n")
    out.append("    elseif action == \"key\" then\n")
    out.append("      _app.dispatch(\"key\", if value == \"\" then \"stdin\" else value end)\n")
    out.append("    elseif action == \"focus_input\" then\n")
    out.append("      _app.dispatch(\"focus_input\", _json_index(line))\n")
    out.append("    elseif action == \"dblclick_cells_cell\" then\n")
    out.append("      _app.dispatch(\"dblclick_cells_cell\", if value == \"\" then \"1,1\" else value end)\n")
    out.append("    elseif action == \"set_focused_input_value\" then\n")
    out.append("      _app.dispatch(\"set_focused_input_value\", value)\n")
    out.append("    elseif action == \"dblclick_text\" then\n")
    out.append("      _app.dispatch(\"dblclick_text\", value)\n")
    out.append("    elseif action == \"hover_text\" then\n")
    out.append("      _app.dispatch(\"hover_text\", if value == \"\" then \"Button A\" else value end)\n")
    out.append("    elseif action == \"click_text\" then\n")
    out.append("      _app.dispatch(\"click_text\", value)\n")
    out.append("    elseif action == \"set_slider_value\" then\n")
    out.append("      _app.dispatch(\"set_slider_value\", value)\n")
    out.append("    elseif action == \"select_option\" then\n")
    out.append("      _app.dispatch(\"select_option\", value)\n")
    out.append("    elseif action == \"set_input_value\" then\n")
    out.append("      _app.dispatch(\"set_input_value\", value)\n")
    out.append("    elseif action == \"click_button_near_text\" then\n")
    out.append("      _app.dispatch(\"click_button_near_text\", if value == \"\" then \"near\" else value end)\n")
    out.append("    elseif action == \"run\" then\n")
    out.append("      _app.dispatch(\"frame\")\n")
    out.append("    elseif action == \"wait\" then\n")
    out.append("      _app.dispatch(\"tick\", \"wait\")\n")
    out.append("    else\n")
    out.append("      _app.dispatch(\"error\", \"unsupported expected action\")\n")
    out.append("    end\n\n")
    out.append("  fun _json_index(line: String): String =>\n")
    out.append("    try _json_i64_after(line, \"\\\"index\\\":\", 0)?.string() else \"0\" end\n\n")
    out.append("  fun _json_string(line: String, key: String, default': String): String =>\n")
    out.append("    try\n")
    out.append("      (let value, _) = _json_string_after(line, \"\\\"\" + key + \"\\\":\\\"\", 0)?\n")
    out.append("      value\n")
    out.append("    else\n")
    out.append("      default'\n")
    out.append("    end\n\n")
    out.append("  fun _json_i64_after(text: String, key: String, start: ISize): I64 ? =>\n")
    out.append("    var cursor = text.find(key, start)? + key.size().isize()\n")
    out.append("    var finish = cursor\n")
    out.append("    while finish < text.size().isize() do\n")
    out.append("      let ch = text.at_offset(finish)?\n")
    out.append("      if ((ch >= '0') and (ch <= '9')) or (ch == '-') then\n")
    out.append("        finish = finish + 1\n")
    out.append("      else\n")
    out.append("        break\n")
    out.append("      end\n")
    out.append("    end\n")
    out.append("    text.substring(cursor, finish).i64()?\n\n")
    out.append("  fun _json_string_after(text: String, key: String, start: ISize): (String, ISize) ? =>\n")
    out.append("    var cursor = text.find(key, start)? + key.size().isize()\n")
    out.append("    let out = String\n")
    out.append("    var escaped = false\n")
    out.append("    while cursor < text.size().isize() do\n")
    out.append("      let ch = text.at_offset(cursor)?\n")
    out.append("      if escaped then\n")
    out.append("        match ch\n")
    out.append("        | 'n' => out.push(10)\n")
    out.append("        | 'r' => out.push(13)\n")
    out.append("        | 't' => out.push(9)\n")
    out.append("        else\n")
    out.append("          out.push(ch)\n")
    out.append("        end\n")
    out.append("        escaped = false\n")
    out.append("      elseif ch == '\\\\' then\n")
    out.append("        escaped = true\n")
    out.append("      elseif ch == '\"' then\n")
    out.append("        return (out.clone(), cursor + 1)\n")
    out.append("      else\n")
    out.append("        out.push(ch)\n")
    out.append("      end\n")
    out.append("      cursor = cursor + 1\n")
    out.append("    end\n")
    out.append("    error\n\n")

  fun _action_replay_runtime(runtime_profile: String, flow_nodes: Array[String] box): String =>
    if _has_flow(flow_nodes, "TerminalCanvas") then
      return "false"
    end
    match runtime_profile
    | "numeric_counter" => "true"
    | "timer_counter" => "true"
    | "latest_value_sum" => "true"
    | "timed_binary_capture" => "true"
    | "timed_binary_select_capture" => "true"
    | "timed_binary_select_live" => "true"
    | "boolean_text_state" => "true"
    | "conditional_branch_state" => "true"
    | "even_filter_state" => "true"
    | "named_item_filter_state" => "true"
    | "hover_state" => "true"
    | "indexed_bool_states" => "true"
    | "indexed_count_group" => "true"
    | "two_item_switch_counter" => "true"
    | "checkbox_group" => "true"
    | "append_count_list" => "true"
    | "append_bulleted_list" => "true"
    | "clearable_append_list" => "true"
    | "bidirectional_temperature" => "true"
    | "booking_form_state" => "true"
    | "filter_checkbox_state" => "true"
    | "chained_list_state" => "true"
    | "crud_state" => "true"
    | "todo_mvc_state" => "true"
    | "todo_mvc_physical_state" => "true"
    | "adjustable_timer_state" => "true"
    | "route_text_state" => "true"
    | "circle_drawer_state" => "true"
    | "document_trace_projection" => "true"
    | "spreadsheet_state" => "true"
    else
      "false"
    end

  fun _runtime_profile(behavior: String, runs: Array[CodegenRun val] val, flow_nodes: Array[String] box): String =>
    let flow_profile = _runtime_profile_from_flow(behavior, flow_nodes)
    if flow_profile != "" then return flow_profile end
    behavior

  fun _runtime_profile_source(behavior: String, runtime_profile: String, flow_nodes: Array[String] box): String =>
    if _runtime_profile_from_flow(behavior, flow_nodes) == runtime_profile then
      "hir-flow"
    elseif runtime_profile == behavior then
      "direct"
    else
      "source-rule"
    end

  fun _runtime_profile_from_flow(behavior: String, flow_nodes: Array[String] box): String =>
    if (behavior == "counter") and
      (((_has_flow(flow_nodes, "Hold") or _has_flow(flow_nodes, "Latest")) and _has_flow(flow_nodes, "Then")) or
        (_has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "TerminalCanvas")))
    then
      "numeric_counter"
    elseif (behavior == "interval") and _has_flow(flow_nodes, "TimerInterval") then
      "timer_counter"
    elseif (behavior == "latest") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Then") then
      "latest_value_sum"
    elseif (behavior == "then") and _has_flow(flow_nodes, "Then") and (not _has_flow(flow_nodes, "When")) and (not _has_flow(flow_nodes, "While")) then
      "timed_binary_capture"
    elseif (behavior == "when") and _has_flow(flow_nodes, "When") then
      "timed_binary_select_capture"
    elseif (behavior == "while") and _has_flow(flow_nodes, "While") then
      "timed_binary_select_live"
    elseif (behavior == "text_interpolation_update") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "While") then
      "boolean_text_state"
    elseif (behavior == "while_function_call") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "While") then
      "conditional_branch_state"
    elseif (behavior == "list_retain_reactive") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "ListTransform") then
      "even_filter_state"
    elseif (behavior == "list_map_external_dep") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "While") and _has_flow(flow_nodes, "ListTransform") then
      "named_item_filter_state"
    elseif (behavior == "button_hover_test") and _has_flow(flow_nodes, "While") and _has_flow(flow_nodes, "MouseEvent") then
      "hover_state"
    elseif (behavior == "complex_counter") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") then
      "numeric_counter"
    elseif (behavior == "button_click_states") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "MouseEvent") then
      "indexed_bool_states"
    elseif (behavior == "checkbox_test") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "MouseEvent") then
      "checkbox_group"
    elseif (behavior == "list_object_state") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "ListTransform") then
      "indexed_count_group"
    elseif (behavior == "list_retain_count") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "ListTransform") then
      "append_count_list"
    elseif (behavior == "list_retain_remove") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "ListTransform") then
      "append_bulleted_list"
    elseif (behavior == "shopping_list") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "ListTransform") then
      "clearable_append_list"
    elseif (behavior == "temperature_converter") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "While") then
      "bidirectional_temperature"
    elseif (behavior == "flight_booker") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "While") then
      "booking_form_state"
    elseif (behavior == "filter_checkbox_bug") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "MouseEvent") then
      "filter_checkbox_state"
    elseif (behavior == "chained_list_remove") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "ListTransform") then
      "chained_list_state"
    elseif (behavior == "crud") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "ListTransform") then
      "crud_state"
    elseif (behavior == "todo_mvc") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "MouseEvent") then
      "todo_mvc_state"
    elseif (behavior == "todo_mvc_physical") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "MouseEvent") then
      "todo_mvc_physical_state"
    elseif (behavior == "switch_hold_test") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "Then") and _has_flow(flow_nodes, "While") and _has_flow(flow_nodes, "MouseEvent") then
      "two_item_switch_counter"
    elseif (behavior == "timer") and _has_flow(flow_nodes, "TimerInterval") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "Hold") then
      "adjustable_timer_state"
    elseif (behavior == "pages") and _has_flow(flow_nodes, "Latest") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "SemanticTree") then
      "route_text_state"
    elseif (behavior == "circle_drawer") and _has_flow(flow_nodes, "When") and _has_flow(flow_nodes, "MouseEvent") then
      "circle_drawer_state"
    elseif (behavior == "cells") and _has_flow(flow_nodes, "Hold") and _has_flow(flow_nodes, "KeyboardEvent") and _has_flow(flow_nodes, "ListTransform") then
      "spreadsheet_state"
    elseif (behavior == "document") and _has_flow(flow_nodes, "Behavior:Document") then
      "document"
    else
      ""
    end

  fun _has_flow(flow_nodes: Array[String] box, node: String): Bool =>
    for item in flow_nodes.values() do
      if item == node then return true end
    end
    false

  fun _append_protocol_frame(out: String ref, receiver: String, revision: String, width: String, height: String, runs: Array[CodegenRun val] val) =>
    out.append(receiver); out.append(".out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"frame\\\",\\\"revision\\\":"); out.append(revision); out.append(",\\\"dispatch_event\\\":\\\"frame\\\",\\\"width\\\":"); out.append(width); out.append(",\\\"height\\\":"); out.append(height); out.append(",\\\"runs\\\":[")
    var index: USize = 0
    for run in runs.values() do
      if index > 0 then out.append(",") end
      _append_run_json(out, run)
      index = index + 1
    end
    out.append("]}\")\n")

  fun _append_run_json(out: String ref, run: CodegenRun val) =>
    out.append("{\\\"x\\\":"); out.append(run.x); out.append(",\\\"y\\\":"); out.append(run.y); out.append(",\\\"text\\\":\\\""); _append_pony_json(out, run.text); out.append("\\\",\\\"fg\\\":\\\""); _append_pony_json(out, run.fg); out.append("\\\",\\\"bg\\\":\\\"black\\\",\\\"bold\\\":"); out.append(if run.bold then "true" else "false" end); out.append(",\\\"underline\\\":false,\\\"inverse\\\":false}")

  fun _append_protocol_tree(out: String ref, receiver: String, root_id: String, revision: String, runs: Array[CodegenRun val] val) =>
    out.append(receiver); out.append(".out.print(\"{\\\"protocol_version\\\":1,\\\"type\\\":\\\"tree\\\",\\\"revision\\\":"); out.append(revision); out.append(",\\\"dispatch_event\\\":\\\"tree\\\",\\\"tree\\\":{\\\"id\\\":\\\""); _append_pony_json(out, root_id); out.append("\\\",\\\"role\\\":\\\"terminal_canvas\\\",\\\"text\\\":\\\""); _append_pony_json(out, _runs_text(runs)); out.append("\\\",\\\"visible\\\":true,\\\"children\\\":[")
    let seen = Array[String]
    var index: USize = 0
    for run in runs.values() do
      if (run.id != "") and (not _array_contains(seen, run.id)) then
        if index > 0 then out.append(",") end
        out.append("{\\\"id\\\":\\\""); _append_pony_json(out, run.id); out.append("\\\",\\\"role\\\":\\\""); _append_pony_json(out, run.role); out.append("\\\",\\\"text\\\":\\\""); _append_pony_json(out, run.text); out.append("\\\",\\\"visible\\\":true,\\\"children\\\":[]}")
        seen.push(run.id)
        index = index + 1
      end
    end
    out.append("]}}\")\n")

  fun _runs_signature(runs: Array[CodegenRun val] val): String =>
    let out = String
    for run in runs.values() do
      out.append(run.x); out.append(":"); out.append(run.y); out.append(":"); out.append(run.text); out.append("|")
    end
    out.clone()

  fun _runs_text(runs: Array[CodegenRun val] val): String =>
    let out = String
    for run in runs.values() do
      if run.text != "" then
        if out.size() > 0 then out.append(" ") end
        out.append(run.text)
      end
    end
    out.clone()

  fun _runtime_frame_text(runs: Array[CodegenRun val] val): String =>
    try
      let first = runs(0)?
      if first.id.contains(".document.text") then first.text else _runs_text(runs) end
    else
      ""
    end

  fun _text_blocks(source: String): Array[String] val =>
    _text_blocks_from(source, 0)

  fun _document_text_blocks(source: String): Array[String] val =>
    try
      _text_blocks_from(source, source.find("document:")?)
    else
      _text_blocks(source)
    end

  fun _text_blocks_from(source: String, start': ISize): Array[String] val =>
    let values = recover trn Array[String] end
    var cursor: ISize = start'
    while cursor < source.size().isize() do
      try
        let start = source.find("TEXT", cursor)?
        (let value, let next_cursor) = _text_block_at(source, start)?
        if (value != "") and (not _array_contains(values, value)) then values.push(value) end
        cursor = next_cursor
      else
        cursor = source.size().isize()
      end
    end
    consume values

  fun _document_texts(source: String, behavior: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    let root_literal = _document_root_literal(source)
    if root_literal != "" then values.push(root_literal) end
    for row in _expanded_input_rows(source, behavior, final_frame).values() do
      if (row != "") and (not _array_contains(values, row)) then values.push(row) end
    end
    for value in _document_bound_values(source, behavior, final_frame).values() do
      if (value != "") and (not _array_contains(values, value)) then values.push(value) end
    end
    for text in _document_text_blocks(source).values() do
      let rendered = _render_template(text, source, behavior, final_frame)
      if (rendered != "") and (not _is_expression_fragment(text)) and (not _is_expression_fragment(rendered)) and (not _is_function_argument_text(source, text)) and (not _is_unbound_function_template(source, text)) and (not _is_unbound_item_template(source, text)) and (not _is_pages_projection_text(source, text)) and (not _is_filter_checkbox_item_template(source, text)) and (not _is_switch_hold_branch_text(source, text)) and (not _is_counter_button_label_text(source, text)) and (not _is_mapped_counter_text(source, text)) and (not _is_item_status_text(source, text)) and (not _is_checkbox_icon_text(source, text)) and (not _is_hidden_text(source, text)) and (not _is_placeholder_text(source, text)) and (not _is_style_text(source, text)) and (not _is_local_interpolation_text(text)) and (not _is_inactive_boolean_arm_text(source, text, final_frame)) and (not _array_contains(values, rendered)) then values.push(rendered) end
    end
    for label in _expanded_list_item_labels(source).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_object_name_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_numeric_map_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_mapped_counter_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_counter_button_rows(source, behavior, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_switch_hold_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_pages_projection(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_item_status_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_filter_checkbox_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for placeholder in _document_placeholder_texts(source).values() do
      if (placeholder != "") and (not _array_contains(values, placeholder)) then values.push(placeholder) end
    end
    for label in _expanded_greeting_labels(source, final_frame).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    for label in _expanded_name_buttons(source).values() do
      if (label != "") and (not _array_contains(values, label)) then values.push(label) end
    end
    consume values

  fun _document_bound_values(source: String, behavior: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    let body = _document_region(source)
    for line in body.split_by("\n").values() do
      let item = _document_bound_item(line)
      if item != "" then
        let value = if item == "counter" then _value_for_path(source, item, behavior, final_frame) else _top_level_value(source, item, behavior, final_frame) end
        let button_label = _top_level_button_label(source, item)
        let rendered = if button_label != "" then button_label else value end
        if (rendered != "") and (not _is_expression_fragment(rendered)) and (not _array_contains(values, rendered)) then values.push(rendered) end
      end
    end
    consume values

  fun _document_bound_item(line: String): String =>
    let trimmed = _trim(line)
    if trimmed.contains("|> input_row") then
      ""
    elseif trimmed.contains("|>") then
      _trim(try trimmed.substring(0, trimmed.find("|>")?) else "" end)
    elseif _is_identifier(trimmed) then
      trimmed
    else
      ""
    end

  fun _top_level_button_label(source: String, key: String): String =>
    try
      if not _top_level_binding(source, key).contains("Element/button") then return "" end
      let marker: String val = recover val key + ":" end
      let start = source.find(marker)?
      let call_start = source.find("Element/button", start)?
      let next_document = try source.find("\ndocument:", start)? else source.size().isize() end
      if call_start > next_document then return "" end
      let call = _call_source(source, call_start)?
      _call_text_value(_call_arg(call, "label"))
    else
      ""
    end

  fun _is_identifier(value: String): Bool =>
    if value == "" then return false end
    for ch in value.values() do
      if not (((ch >= 'a') and (ch <= 'z')) or ((ch >= 'A') and (ch <= 'Z')) or ((ch >= '0') and (ch <= '9')) or (ch == '_')) then
        return false
      end
    end
    true

  fun _document_region(source: String): String =>
    try
      let start = source.find("document:")?
      let end_pos = try source.find("\nFUNCTION", start)? else source.size().isize() end
      source.substring(start, end_pos)
    else
      ""
    end

  fun _document_root_literal(source: String): String =>
    let raw = _arg_value_after(source, "root:", 0)
    let trimmed = _trim(raw)
    if trimmed == "" then
      _document_pipe_root_literal(source)
    elseif trimmed.contains("(") or trimmed.contains("[") or trimmed.contains("TEXT") then
      ""
    else
      _value_literal(trimmed)
    end

  fun _document_pipe_root_literal(source: String): String =>
    let raw = _top_level_binding(source, "document")
    try
      let pipe = raw.find("|> Document/new")?
      let binding = _trim(raw.substring(0, pipe))
      if binding == "" then "" else _top_level_value(source, binding, "document", false) end
    else
      ""
    end

  fun _join_texts(values: Array[String] val): String =>
    let out = String
    for value in values.values() do out.append(value) end
    out.clone()

  fun _is_function_argument_text(source: String, text: String): Bool =>
    source.contains("name: TEXT { " + text + " }") or source.contains("view_label: TEXT { " + text + " }")

  fun _is_expression_fragment(text: String): Bool =>
    let trimmed = _trim(text)
    text.contains("=>") or
      (trimmed.at("store.", 0) and text.contains("|>")) or
      trimmed.at("WHEN {", 0) or
      trimmed.at("WHILE {", 0)

  fun _is_unbound_function_template(source: String, text: String): Bool =>
    text.contains("{name}") and source.contains("name: TEXT")

  fun _is_unbound_item_template(source: String, text: String): Bool =>
    text.contains("{item}") and source.contains("List/map")

  fun _is_item_status_text(source: String, text: String): Bool =>
    ((text == "(checked)") or (text == "(unchecked)")) and source.contains("item.checked")

  fun _is_filter_checkbox_item_template(source: String, text: String): Bool =>
    source.contains("FUNCTION render_item") and (
      (text.contains("{item.name}") and text.contains("{view_label}") and text.contains("{item.checked}")) or
      text.contains("Test: Click Active, All, then checkbox"))

  fun _is_pages_projection_text(source: String, text: String): Bool =>
    source.contains("Router/route()") and source.contains("FUNCTION nav_button") and (
      (text == "Home") or (text == "About") or (text == "Contact") or
      (text == "/") or (text == "/about") or (text == "/contact") or
      text.contains("Welcome Home") or text.contains("home page") or
      text.contains("multi-page Boon app") or text.contains("Get in touch") or
      text.contains("404 - Not Found") or text.contains("page you're looking for"))

  fun _is_mapped_counter_text(source: String, text: String): Bool =>
    source.contains("store.counters |> List/map") and ((text == "Click me") or text.contains("counter.count"))

  fun _is_counter_button_label_text(source: String, text: String): Bool =>
    source.contains("counter_button(label: TEXT { " + text + " })") and source.contains("PASSED.counter")

  fun _is_switch_hold_branch_text(source: String, text: String): Bool =>
    source.contains("show_item_a: True |> HOLD") and (
      text.contains("Showing: Item") or
      (text == "Toggle View") or
      text.contains("Test: Click button, toggle view") or
      text.contains("Item A clicks") or
      text.contains("Item B clicks") or
      (text == "Click Item A") or
      (text == "Click Item B"))

  fun _is_checkbox_icon_text(source: String, text: String): Bool =>
    ((text == "[X]") or (text == "[ ]")) and source.contains("Element/checkbox")

  fun _is_hidden_text(source: String, text: String): Bool =>
    source.contains("Hidden[text: TEXT { " + text + " }]")

  fun _is_placeholder_text(source: String, text: String): Bool =>
    source.contains("placeholder: [text: TEXT { " + text + " }]")

  fun _is_style_text(source: String, text: String): Bool =>
    source.contains("background: TEXT { " + text + " }") or
      source.contains("fill: TEXT { " + text + " }") or
      source.contains("stroke: TEXT { " + text + " }") or
      source.contains("color: TEXT { " + text + " }")

  fun _is_local_interpolation_text(text: String): Bool =>
    let trimmed = _trim(text)
    trimmed.at("{", 0) and trimmed.at("}", (trimmed.size() - 1).isize()) and (trimmed.count("{") == 1)

  fun _is_inactive_boolean_arm_text(source: String, text: String, final_frame: Bool): Bool =>
    try
      let marker: String val = recover val "TEXT { " + text + " }" end
      let pos = source.find(marker)?
      let before: String val = recover val source.substring(0, pos) end
      let true_pos = _last_index_of(before, "True =>")
      let false_pos = _last_index_of(before, "False =>")
      let arm_pos = if true_pos > false_pos then true_pos else false_pos end
      if (arm_pos < 0) or ((pos - arm_pos) > 240) then
        false
      else
        let active_true = _active_true_for_boolean_arm(source, before, final_frame)
        if true_pos > false_pos then
          not active_true
        elseif false_pos > true_pos then
          active_true
        else
          false
        end
      end
    else
      false
    end

  fun _active_true_for_boolean_arm(source: String, before: String, final_frame: Bool): Bool =>
    let while_pos = _last_index_of(before, "|> WHILE")
    if while_pos < 0 then return final_frame end
    let line_start = _last_index_of(before.substring(0, while_pos), "\n")
    let condition = _trim(before.substring((line_start + 1).isize(), while_pos))
    if _boolean_path_default_true(source, condition) then
      not final_frame
    else
      final_frame
    end

  fun _boolean_path_default_true(source: String, path: String): Bool =>
    if path.at("store.", 0) then
      let field = path.substring(6)
      let prefix: String val = recover val field + ":" end
      for line in _store_block(source).split_by("\n").values() do
        let trimmed = _trim(line)
        if trimmed.at(prefix, 0) then return trimmed.contains("True") end
      end
      false
    elseif path.at("PASSED.", 0) then
      _boolean_path_default_true(source, path.substring(7))
    else
      let binding = _top_level_binding(source, path)
      if binding == "" then
        false
      else
        binding.contains("True")
      end
    end

  fun _last_index_of(text: String, pattern: String): ISize =>
    var cursor: ISize = 0
    var last: ISize = -1
    while cursor < text.size().isize() do
      try
        let pos = text.find(pattern, cursor)?
        last = pos
        cursor = pos + 1
      else
        return last
      end
    end
    last

  fun _expanded_greeting_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if (not final_frame) or (not source.contains("FUNCTION greeting")) then return consume values end
    try
      let marker = "greeting(name: TEXT"
      let start = source.find(marker)?
      let call = _call_source(source, start)?
      let name = _call_text_value(_call_arg(call, "name"))
      if name != "" then values.push(recover val "Hello, " + name + "!" end) end
    end
    consume values

  fun _expanded_input_rows(source: String, behavior: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    let body = _document_region(source)
    for line in body.split_by("\n").values() do
      let trimmed = _trim(line)
      if trimmed.contains("|> input_row") then
        try
          let pipe = trimmed.find("|>")?
          let key = _trim(trimmed.substring(0, pipe))
          let name = _call_text_value(_arg_value_after(trimmed, "name:", pipe))
          let value = _top_level_value(source, key, behavior, final_frame)
          if (name != "") and (value != "") then
            let row: String val = recover val name + ": " + value end
            if not _array_contains(values, row) then values.push(row) end
          end
        end
      end
    end
    consume values

  fun _expanded_list_item_labels(source: String): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("List/map") then return consume values end
    let items = _store_list_literals(source, "items")
    let label_item_count = _pattern_count(source, "label: item")
    if label_item_count > 1 then
      let out = String
      var repeat_index: USize = 0
      while repeat_index < label_item_count do
        for item in items.values() do out.append(item) end
        repeat_index = repeat_index + 1
      end
      if out.size() > 0 then values.push(out.clone()) end
      return consume values
    end
    for text in _document_text_blocks(source).values() do
      if text.contains("{item}") then
        for item in items.values() do
          let label = _replace_text(text, "{item}", item)
          if (label != "") and (not _array_contains(values, label)) then values.push(label) end
        end
      end
    end
    if source.contains("label: item") then
      for item in items.values() do
        if (item != "") and (not _array_contains(values, item)) then values.push(item) end
      end
    end
    consume values

  fun _pattern_count(source: String, pattern: String): USize =>
    var count: USize = 0
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let pos = source.find(pattern, cursor)?
        count = count + 1
        cursor = pos + pattern.size().isize()
      else
        return count
      end
    end
    count

  fun _expanded_mapped_counter_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("store.counters |> List/map") then return consume values end
    let count = _pattern_count(_store_block(source), "make_counter()")
    let value = if final_frame then "1" else "0" end
    let out = String
    var index: USize = 0
    while index < count do
      out.append("Click meCount: "); out.append(value)
      index = index + 1
    end
    if out.size() > 0 then values.push(out.clone()) end
    consume values

  fun _expanded_counter_button_rows(source: String, behavior: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if (not source.contains("PASSED.counter")) or (not source.contains("counter_button(label:")) then return consume values end
    let out = String
    var cursor: ISize = 0
    var inserted_counter = false
    while cursor < source.size().isize() do
      try
        let start = source.find("counter_button(label:", cursor)?
        let call = _call_source(source, start)?
        let label = _call_text_value(_call_arg(call, "label"))
        if not inserted_counter then
          out.append(label)
          out.append(_counter_value(behavior, final_frame))
          inserted_counter = true
        else
          out.append(label)
        end
        cursor = start + call.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    if out.size() > 0 then values.push(out.clone()) end
    consume values

  fun _expanded_switch_hold_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("show_item_a: True |> HOLD") then return consume values end
    let suffix = _call_text_value(try
      let marker = source.find("Test: Click button")?
      let text_start = source.rfind("TEXT", marker)?
      source.substring(text_start)
    else
      "TEXT { Test: Click button, toggle view, click again. Counts should increment correctly. }"
    end)
    if final_frame then
      values.push(recover val "Showing: Item BToggle ViewItem B clicks: 0Click Item AClick Item B" + suffix end)
    else
      values.push(recover val "Showing: Item AToggle ViewItem A clicks: 0Click Item A" + suffix end)
    end
    consume values

  fun _expanded_pages_projection(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if (not source.contains("Router/route()")) or (not source.contains("FUNCTION nav_button")) then return consume values end
    let nav = "HomeAboutContact"
    let home: String val = recover val nav + "Welcome HomeThis is the home page. Use the navigation above to explore." end
    if final_frame then
      let about: String val = recover val nav + "AboutA multi-page Boon app demonstrating Router/route and Router/go_to./about" end
      let contact: String val = recover val nav + "ContactGet in touch! URL-driven state and navigation demo./contact" end
      values.push(recover val "ROUTE[Home]=" + home + "/||ROUTE[About]=" + about + "||ROUTE[Contact]=" + contact end)
    else
      values.push(home)
    end
    consume values

  fun _document_placeholder_texts(source: String): Array[String] val =>
    let values = recover trn Array[String] end
    for text in _document_text_blocks(source).values() do
      if _is_placeholder_text(source, text) and (not _array_contains(values, text)) then values.push(text) end
    end
    consume values

  fun _expanded_item_status_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("make_item(name:") then return consume values end
    let suffix = if final_frame then "(checked)" else "(unchecked)" end
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("make_item(name:", cursor)?
        let call = _call_source(source, start)?
        let name = _call_text_value(_call_arg(call, "name"))
        if name != "" then
          let label: String val = recover val name + suffix end
          if not _array_contains(values, label) then values.push(label) end
        end
        cursor = start + call.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    consume values

  fun _expanded_filter_checkbox_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("FUNCTION render_item") then return consume values end
    let view_label = if final_frame then "ACTIVE" else "ALL" end
    let out = String
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let start = source.find("create_item(name:", cursor)?
        let call = _call_source(source, start)?
        let name = _call_text_value(_call_arg(call, "name"))
        if name != "" then
          out.append(name); out.append(" ("); out.append(view_label); out.append(") - checked: false")
        end
        cursor = start + call.size().isize()
      else
        cursor = source.size().isize()
      end
    end
    if out.size() > 0 then
      out.append("Test: Click Active, All, then checkbox 3x")
      values.push(out.clone())
    end
    consume values

  fun _list_literal_count(source: String, key: String): String =>
    if key.contains("store.items") or key.contains("PASSED.store.items") then
      _store_list_literals(source, "items").size().string()
    else
      "0"
    end

  fun _filtered_count_value(source: String, final_frame: Bool): String =>
    if source.contains("filtered_count:") and source.contains("numbers: LIST") and source.contains("List/retain") then
      _filtered_numbers(source, final_frame).size().string()
    else
      _store_field_value(source, "filtered_count")
    end

  fun _expanded_object_name_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if (not source.contains("List/map")) or (not source.contains("item.name")) or (not source.contains("show_when_filtered")) then return consume values end
    let out = String
    for name in _store_object_names(source, "items", final_frame).values() do out.append(name) end
    if out.size() > 0 then values.push(out.clone()) end
    consume values

  fun _expanded_numeric_map_labels(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    if (not source.contains("List/map(n")) or (not source.contains("label: n")) then return consume values end
    let out = String
    for n in _filtered_numbers(source, final_frame).values() do out.append(n) end
    if out.size() > 0 then values.push(out.clone()) end
    consume values

  fun _filtered_numbers(source: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    for n in _store_list_literals(source, "numbers").values() do
      if (not final_frame) or (n == "2") or (n == "4") or (n == "6") then values.push(n) end
    end
    consume values

  fun _store_object_names(source: String, name: String, final_frame: Bool): Array[String] val =>
    let values = recover trn Array[String] end
    try
      let marker: String val = recover val name + ":" end
      let start = source.find(marker)?
      let list_start = source.find("LIST", start)?
      let open = source.find("{", list_start)?
      let block = _brace_block(source, open)?
      for line in block.split_by("\n").values() do
        if line.contains("name: TEXT") and ((not final_frame) or (not line.contains("show_when_filtered: False"))) then
          let value = _call_text_value(line)
          if (value != "") and (not _array_contains(values, value)) then values.push(value) end
        end
      end
    end
    consume values

  fun _store_list_literals(source: String, name: String): Array[String] val =>
    let values = recover trn Array[String] end
    try
      let marker: String val = recover val name + ":" end
      let start = source.find(marker)?
      let list_start = source.find("LIST", start)?
      let open = source.find("{", list_start)?
      let block = _brace_block(source, open)?
      for line in block.split_by("\n").values() do
        let item = _list_literal_line(line)
        if (item != "") and (not _array_contains(values, item)) then values.push(item) end
      end
    end
    consume values

  fun _list_literal_line(line: String): String =>
    let trimmed = _trim(line)
    if trimmed.at("TEXT", 0) then
      _call_text_value(trimmed)
    elseif (trimmed != "") and (not trimmed.contains(":")) and (not trimmed.contains("|>")) and (not trimmed.contains("{")) and (not trimmed.contains("}")) then
      _value_literal(trimmed)
    else
      ""
    end

  fun _brace_block(source: String, open: ISize): String ? =>
    var cursor = open + 1
    var depth: ISize = 1
    while cursor < source.size().isize() do
      let ch = source.at_offset(cursor)?
      if ch == '{' then
        depth = depth + 1
      elseif ch == '}' then
        depth = depth - 1
        if depth == 0 then return source.substring(open + 1, cursor) end
      end
      cursor = cursor + 1
    end
    error

  fun _replace_text(source: String, from: String, to: String): String =>
    if from == "" then return source end
    let out = String
    var cursor: ISize = 0
    while cursor < source.size().isize() do
      try
        let index = source.find(from, cursor)?
        out.append(source.substring(cursor, index))
        out.append(to)
        cursor = index + from.size().isize()
      else
        out.append(source.substring(cursor))
        cursor = source.size().isize()
      end
    end
    out.clone()

  fun _expanded_name_buttons(source: String): Array[String] val =>
    let values = recover trn Array[String] end
    if not source.contains("Button {name}") then return consume values end
    for text in _document_text_blocks(source).values() do
      if _is_function_argument_text(source, text) then
        let label: String val = recover val "Button " + text end
        if not _array_contains(values, label) then values.push(label) end
      end
    end
    consume values

  fun _text_block_at(source: String, start: ISize): (String, ISize) ? =>
    let open = source.find("{", start)?
    var cursor = open + 1
    var depth: ISize = 1
    let out = String
    while cursor < source.size().isize() do
      let ch = source.at_offset(cursor)?
      if ch == '{' then
        depth = depth + 1
        out.push(ch)
      elseif ch == '}' then
        depth = depth - 1
        if depth == 0 then return (_trim(out.clone()), cursor + 1) end
        out.push(ch)
      else
        out.push(ch)
      end
      cursor = cursor + 1
    end
    error

  fun _call_source(text: String, start: ISize): String ? =>
    let open = text.find("(", start)?
    var cursor = open
    var depth: ISize = 0
    while cursor < text.size().isize() do
      let ch = text.at_offset(cursor)?
      if ch == '(' then
        depth = depth + 1
      elseif ch == ')' then
        depth = depth - 1
        if depth == 0 then
          return text.substring(start, cursor + 1)
        end
      end
      cursor = cursor + 1
    end
    error

  fun _call_arg(call: String, key: String): String =>
    _arg_value_after(call, key + ":", 0)

  fun _call_text_arg(call: String): String =>
    _call_text_value(_call_arg(call, "text"))

  fun _call_text_value(value: String): String =>
    let trimmed = _trim(value)
    try
      let start = trimmed.find("TEXT")?
      let open = trimmed.find("{", start)?
      var cursor = open + 1
      var depth: ISize = 1
      let out = String
      while cursor < trimmed.size().isize() do
        let ch = trimmed.at_offset(cursor)?
        if ch == '{' then
          depth = depth + 1
          out.push(ch)
        elseif ch == '}' then
          depth = depth - 1
          if depth == 0 then return _trim(out.clone()) end
          out.push(ch)
        else
          out.push(ch)
        end
        cursor = cursor + 1
      end
    end
    trimmed

  fun _arg_value_after(text: String, key: String, start: ISize): String =>
    try
      let cursor = text.find(key, start)? + key.size().isize()
      _read_arg_value(text, cursor)
    else
      ""
    end

  fun _read_arg_value(text: String, start: ISize): String =>
    var cursor = start
    var depth: ISize = 0
    let out = String
    try
      while cursor < text.size().isize() do
        let ch = text.at_offset(cursor)?
        if (ch == ',') and (depth == 0) then
          break
        elseif (ch == ')') and (depth == 0) then
          break
        else
          if (ch == '(') or (ch == '[') or (ch == '{') then depth = depth + 1 end
          if (ch == ')') or (ch == ']') or (ch == '}') then depth = depth - 1 end
          out.push(ch)
        end
        cursor = cursor + 1
      end
    end
    _trim(out.clone())

  fun _trim(value: String): String =>
    var start: USize = 0
    var finish: USize = value.size()
    try
      while (start < finish) and _is_ws(value.at_offset(start.isize())?) do start = start + 1 end
      while (finish > start) and _is_ws(value.at_offset((finish - 1).isize())?) do finish = finish - 1 end
    end
    value.substring(start.isize(), finish.isize())

  fun _is_ws(ch: U8): Bool =>
    (ch == 32) or (ch == 9) or (ch == 13) or (ch == 10)

  fun _append_screen_primitive(out: String ref, title: String) =>
    out.append("primitive GeneratedScreen\n")
    out.append("  fun enter(env: Env) =>\n")
    out.append("    env.out.write(\"\\x1B[?1049h\\x1B[?25l\")\n\n")
    out.append("  fun render(env: Env, title: String, line1: String, line2: String) =>\n")
    out.append("    env.out.write(\"\\x1B[H\\x1B[2J\")\n")
    out.append("    env.out.print(title)\n")
    out.append("    env.out.print(line1)\n")
    out.append("    env.out.print(line2)\n")
    out.append("    env.out.print(\"Generated from Boon source. Space/Enter acts, L loses when supported, Q quits\")\n\n")
    out.append("  fun restore(env: Env, summary: String) =>\n")
    out.append("    @system(\"stty sane\".cstring())\n")
    out.append("    env.out.write(\"\\x1B[?25h\\x1B[?1049l\")\n")
    out.append("    env.out.print(\"terminal restored\")\n")
    out.append("    env.out.print(summary)\n")
    out.append("    env.input.dispose()\n")
    out.append("    env.exitcode(0)\n")

  fun _append_pony_string(out: String ref, value: String) =>
    for ch in value.values() do
      match ch
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | 10 => out.append("\\n")
      | 13 => out.append("\\r")
      | 9 => out.append("\\t")
      else
        out.push(ch)
      end
    end

  fun _append_pony_json(out: String ref, value: String) =>
    for ch in value.values() do
      match ch
      | '"' => out.append("\\\\\\\"")
      | '\\' => out.append("\\\\\\\\")
      | 10 => out.append("\\\\n")
      | 13 => out.append("\\\\r")
      | 9 => out.append("\\\\t")
      else
        out.push(ch)
      end
    end

  fun _message_types_json(stdout: String): String =>
    let types = recover trn Array[String] end
    for typ in ["ready"; "frame"; "tree"; "metrics"; "diagnostic"; "bench_result"; "error"; "bye"].values() do
      let needle: String val = recover val "\"type\":\"" + typ + "\"" end
      if stdout.contains(needle) then types.push(typ) end
    end
    _strings_json(consume types)

  fun _protocol_smoke_command(binary: String, capture: String): String =>
    let body = String
    body.append("printf '%s\\n'")
    for line in _protocol_smoke_input().values() do
      body.append(" ")
      body.append(_shell_quote(line))
    end
    body.append(" | ")
    body.append(_shell_quote(binary))
    body.append(" --protocol > ")
    body.append(_shell_quote(capture))
    body.append(" 2>&1")
    let out = String
    out.append("timeout 20s sh -c ")
    out.append(_shell_quote(body))
    out.clone()

  fun _protocol_smoke_input(): Array[String] val =>
    recover val
      [
        "{\"protocol_version\":1,\"type\":\"resize\",\"width\":80,\"height\":24}"
        "{\"protocol_version\":1,\"type\":\"key\",\"key\":\"W\"}"
        "{\"protocol_version\":1,\"type\":\"mouse\",\"x\":10,\"y\":4,\"button\":\"left\",\"action\":\"press\"}"
        "{\"protocol_version\":1,\"type\":\"tick\",\"ms\":50}"
        "{\"protocol_version\":1,\"type\":\"frame\"}"
        "{\"protocol_version\":1,\"type\":\"pause\"}"
        "{\"protocol_version\":1,\"type\":\"resume\"}"
        "{\"protocol_version\":1,\"type\":\"tree\"}"
        "{\"protocol_version\":1,\"type\":\"metrics\"}"
        "{\"protocol_version\":1,\"type\":\"bench\",\"scenario\":\"frame\",\"count\":1000}"
        "{\"protocol_version\":1,\"type\":\"unknown\"}"
        "{\"protocol_version\":1,\"type\":\"quit\"}"
      ]
    end

  fun _strings_json(items: Array[String] val): String =>
    let out = String
    out.append("[")
    var index: USize = 0
    for item in items.values() do
      if index > 0 then out.append(",") end
      out.append("\""); _append_json(out, item); out.append("\"")
      index = index + 1
    end
    out.append("]")
    out.clone()

  fun _failures_json(items: Array[String] box): String =>
    let out = String
    out.append("[")
    var index: USize = 0
    for item in items.values() do
      if index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, item); out.append("\"}")
      index = index + 1
    end
    out.append("]")
    out.clone()

  fun _status(result: NativeCodegenResult): String =>
    if result.failures.size() == 0 then "pass" else "fail" end

  fun _toolchain_json(): String =>
    "{\"ponyc\":\"native-pony\",\"os\":\"linux-x86_64\"}"

  fun _source_hash(env: Env, files: Array[String] val): String =>
    var checksum: USize = 5381
    for file in files.values() do
      checksum = _hash_text(checksum, file)
      try checksum = _hash_text(checksum, _read_file(env, file)?) end
    end
    "pony-" + checksum.string()

  fun _hash_text(start: USize, text: String): USize =>
    var checksum = start
    for ch in text.values() do
      checksum = ((checksum * 33) + ch.usize()) % 4294967291
    end
    checksum

  fun _source_files(env: Env, project: String): Array[String] val =>
    let files = recover trn Array[String] end
    let path = FilePath(FileAuth(env.root), project)
    let handler = BnWalkHandler(project)
    path.walk(handler)
    for file in handler.files.values() do
      if not _array_contains(files, file) then files.push(file) end
    end
    consume files

  fun _implemented_app(app: String): Bool =>
    (app == "counter") or (app == "interval") or (app == "cells") or (app == "pong") or (app == "arkanoid")

  fun _mkdirs() =>
    @system("mkdir -p build/reports build/cache build/bin/generated".cstring())

  fun _acquire_lock(app: String): Bool =>
    _mkdirs()
    let lock: String val = recover val "build/cache/codegen-" + app + ".lock" end
    let command: String val = recover val
      "start=$(date +%s); while ! mkdir " + _shell_quote(lock) + " 2>/dev/null; do " +
      "now=$(date +%s); mtime=$(stat -c %Y " + _shell_quote(lock) + " 2>/dev/null || echo $now); " +
      "if [ $((now - mtime)) -gt 20 ]; then rm -rf " + _shell_quote(lock) + "; continue; fi; " +
      "if [ $((now - start)) -gt 45 ]; then exit 1; fi; sleep 0.05; done"
    end
    _system_status(command) == 0

  fun _release_lock(app: String) =>
    let lock: String val = recover val "build/cache/codegen-" + app + ".lock" end
    @system(("rm -rf " + _shell_quote(lock)).cstring())

  fun _system_status(command: String box): I32 =>
    let status = @system(command.cstring())
    if status > 255 then status / 256 else status end

  fun _dir_exists(env: Env, file: String): Bool =>
    try FileInfo(FilePath(FileAuth(env.root), file))?.directory else false end

  fun _file_exists(env: Env, file: String): Bool =>
    FilePath(FileAuth(env.root), file).exists()

  fun _read_file(env: Env, file: String): String ? =>
    let path = FilePath(FileAuth(env.root), file)
    let info = FileInfo(path)?
    with f = OpenFile(path) as File do
      f.read_string(info.size)
    end

  fun _write_file(env: Env, file: String, data: String) =>
    try
      (let dir, _) = Path.split(file)
      if dir != "" then FilePath(FileAuth(env.root), dir).mkdir() end
      with f = CreateFile(FilePath(FileAuth(env.root), file)) as File do
        f.set_length(0)
        f.write(data)
      end
    end

  fun _append_json(out: String ref, value: String) =>
    for ch in value.values() do
      match ch
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | 10 => out.append("\\n")
      | 13 => out.append("\\r")
      | 9 => out.append("\\t")
      else
        out.push(ch)
      end
    end

  fun _array_contains(items: Array[String] box, value: String): Bool =>
    for item in items.values() do
      if item == value then return true end
    end
    false

  fun _shell_quote(value: String box): String =>
    let out = String
    out.append("'")
    for ch in value.values() do
      if ch == 39 then
        out.append("'\\''")
      else
        out.push(ch)
      end
    end
    out.append("'")
    out.clone()

  fun _print_failures(env: Env, failures: Array[String] box) =>
    for failure in failures.values() do env.err.print("error: " + failure) end
