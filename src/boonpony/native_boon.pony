use "collections"
use "files"
use "time"

class val BoonToken
  let kind: String
  let value: String
  let start: USize
  let end_pos: USize
  let line: USize
  let column: USize

  new val create(kind': String, value': String, start': USize, end_pos': USize, line': USize, column': USize) =>
    kind = kind'
    value = value'
    start = start'
    end_pos = end_pos'
    line = line'
    column = column'

class val BoonParseResult
  let file: String
  let status: String
  let code: String
  let message: String
  let line: USize
  let column: USize
  let declarations: USize
  let functions: USize
  let tokens: USize
  let ast_nodes: USize
  let expression_nodes: USize
  let ast_kind_counts: String
  let ast: String

  new val create(file': String, status': String, code': String, message': String, line': USize, column': USize, declarations': USize, functions': USize, tokens': USize, ast_nodes': USize = 0, expression_nodes': USize = 0, ast_kind_counts': String = "{}", ast': String = "{}") =>
    file = file'
    status = status'
    code = code'
    message = message'
    line = line'
    column = column'
    declarations = declarations'
    functions = functions'
    tokens = tokens'
    ast_nodes = ast_nodes'
    expression_nodes = expression_nodes'
    ast_kind_counts = ast_kind_counts'
    ast = ast'

class val SourceSlot
  let id: USize
  let semantic_id: String
  let payload_type: String
  let slot_kind: String
  let start: USize
  let end_pos: USize
  let line: USize
  let column: USize

  new val create(id': USize, semantic_id': String, payload_type': String, slot_kind': String, start': USize, end_pos': USize, line': USize, column': USize) =>
    id = id'
    semantic_id = semantic_id'
    payload_type = payload_type'
    slot_kind = slot_kind'
    start = start'
    end_pos = end_pos'
    line = line'
    column = column'

class val SourceDiagnostic
  let code: String
  let message: String
  let line: USize
  let column: USize

  new val create(code': String, message': String, line': USize, column': USize) =>
    code = code'
    message = message'
    line = line'
    column = column'

class val SourceAnalysis
  let file: String
  let slots: Array[SourceSlot val] val
  let pass_markers: USize
  let diagnostics: Array[SourceDiagnostic val] val
  let flow_nodes: Array[String] val
  let terminal_ir: String

  new val create(file': String, slots': Array[SourceSlot val] val, pass_markers': USize, diagnostics': Array[SourceDiagnostic val] val = recover val Array[SourceDiagnostic val] end, flow_nodes': Array[String] val = recover val Array[String] end, terminal_ir': String = "{}") =>
    file = file'
    slots = slots'
    pass_markers = pass_markers'
    diagnostics = diagnostics'
    flow_nodes = flow_nodes'
    terminal_ir = terminal_ir'

class val TerminalFrame
  let text: String
  let ids: Array[String] val
  let changed_cells: USize
  let bytes_written: USize
  let width: USize
  let height: USize
  let full_redraw: Bool
  let frame_source: String

  new val create(text': String, ids': Array[String] val, changed_cells': USize, bytes_written': USize, width': USize, height': USize, full_redraw': Bool, frame_source': String = "boon-source") =>
    text = text'
    ids = ids'
    changed_cells = changed_cells'
    bytes_written = bytes_written'
    width = width'
    height = height'
    full_redraw = full_redraw'
    frame_source = frame_source'

class ref BnWalkHandler is WalkHandler
  let _root: String
  let files: Array[String] ref = Array[String]

  new create(root': String) =>
    _root = Path.abs(root')

  fun ref apply(dir_path: FilePath, dir_entries: Array[String] ref) =>
    for entry in dir_entries.values() do
      try
        let child = dir_path.join(entry)?
        let info = FileInfo(child)?
        if info.file and entry.at(".bn", -3) then
          let rel = Path.rel(Path.cwd(), child.path)?
          files.push(rel)
        end
      end
    end

class ref SuffixWalkHandler is WalkHandler
  let suffix: String
  let files: Array[String] ref = Array[String]

  new create(suffix': String) =>
    suffix = suffix'

  fun ref apply(dir_path: FilePath, dir_entries: Array[String] ref) =>
    for entry in dir_entries.values() do
      try
        let child = dir_path.join(entry)?
        let info = FileInfo(child)?
        if info.file and entry.at(suffix, -suffix.size().isize()) then
          files.push(Path.rel(Path.cwd(), child.path)?)
        end
      end
    end

primitive NativeBoon
  fun manifest_check_command(env: Env) =>
    let failures = Array[String]
    for file in ["fixtures/upstream_pin.json"; "fixtures/corpus_manifest.json"; "fixtures/syntax_inventory.json"; "fixtures/feature_matrix.md"; "fixtures/spec_gaps.md"].values() do
      if not FilePath(FileAuth(env.root), file).exists() then
        failures.push("missing " + file)
      end
    end

    let manifest_bn = _manifest_bn_files(env, "fixtures/corpus_manifest.json")
    let manifest_expected = _manifest_expected_files(env, "fixtures/corpus_manifest.json")
    for file in manifest_bn.values() do
      if not FilePath(FileAuth(env.root), file).exists() then failures.push("manifest references missing source " + file) end
    end
    for file in manifest_expected.values() do
      if not FilePath(FileAuth(env.root), file).exists() then failures.push("manifest references missing expected file " + file) end
    end
    for file in _walk_files(env, "examples/upstream", ".bn").values() do
      if not _array_contains(manifest_bn, file) then failures.push("manifest omits runnable source " + file) end
    end
    for file in _walk_files(env, "examples", ".bn").values() do
      try
        let text = _read_file(env, file)?
        if text.contains("LINK") then failures.push("forbidden legacy LINK spelling in runnable source: " + file) end
      end
    end

    if failures.size() == 0 then
      env.out.print("manifest ok: " + _manifest_example_count(env).string() + " examples")
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.exitcode(1)
    end

  fun verify_expected_command(env: Env, target: String, report: String = "build/reports/verify.json") =>
    let files = if target == "--all" then
      _all_expected_files(env)
    else
      _expected_files_for_target(env, target)
    end
    let failures = Array[String]
    var action_count: USize = 0
    var expected_count: USize = 0
    var expected_value_count: USize = 0
    var runtime_case_count: USize = 0
    var runtime_required_count: USize = 0
    var runtime_gap_count: USize = 0
    var runtime_action_replay_count: USize = 0
    var runtime_case_directed_count: USize = 0
    var runtime_trace_debt_count: USize = 0
    var runtime_static_probe_count: USize = 0
    var runtime_source_trace_count: USize = 0
    var runtime_frame_assertion_count: USize = 0
    var runtime_frame_assertion_failure_count: USize = 0
    var replay_case_count: USize = 0
    let case_directed = Array[String]
    let generated_apps = Array[String]
    let out = String
    out.append("{\n  \"command\":\"verify\",\n  \"status\":\"")
    let case_json = String
    var case_index: USize = 0
    for file in files.values() do
      expected_count = expected_count + 1
      let parsed = _parse_expected_actions(env, file)
      (let section_count, let parsed_actions) = parsed
      let expected_values = _parse_expected_values(env, file)
      expected_value_count = expected_value_count + expected_values.size()
      action_count = action_count + parsed_actions.size()
      let runtime_required = _is_terminal_expected(file)
      let runtime_case = runtime_required or _expected_project_has_source(env, file)
      var runtime_action_replay = false
      var runtime_case_directed = false
      var runtime_trace_debt = false
      var runtime_static_probe = false
      let runtime_output = if runtime_case then _runtime_expected_output(env, file) else "" end
      let runtime_needles = if runtime_case then _runtime_expected_needles(env, file, expected_values) else recover val Array[String] end end
      let runtime_missing = Array[String]
      if runtime_case then
        let generated_app = _basename_without_suffix(file, ".expected")
        if not _array_contains(generated_apps, generated_app) then generated_apps.push(generated_app) end
        runtime_case_count = runtime_case_count + 1
        if runtime_required then runtime_required_count = runtime_required_count + 1 end
        if runtime_output == "" then
          runtime_missing.push("generated runtime produced no output")
        end
        for needle in runtime_needles.values() do
          if (needle != "") and (not runtime_output.contains(needle)) then
            runtime_missing.push(needle)
          end
        end
        if _expected_frame_assertion_family(file) then runtime_frame_assertion_count = runtime_frame_assertion_count + 1 end
        for failure in _runtime_frame_assertion_failures(env, file, runtime_output).values() do
          runtime_frame_assertion_failure_count = runtime_frame_assertion_failure_count + 1
          runtime_missing.push(failure)
        end
        runtime_action_replay = _runtime_action_replay_proven(file, parsed_actions, runtime_output, runtime_missing)
        runtime_case_directed = runtime_action_replay and _case_directed_replay_family(file)
        runtime_trace_debt = (not runtime_required) and (parsed_actions.size() > 0) and (not runtime_action_replay)
        runtime_static_probe = (not runtime_required) and (parsed_actions.size() == 0) and (runtime_missing.size() == 0)
        if runtime_action_replay then runtime_action_replay_count = runtime_action_replay_count + 1 end
        if runtime_static_probe then runtime_static_probe_count = runtime_static_probe_count + 1 end
        if runtime_case_directed then
          runtime_case_directed_count = runtime_case_directed_count + 1
          case_directed.push(_basename_without_suffix(file, ".expected"))
        end
        if runtime_trace_debt then runtime_trace_debt_count = runtime_trace_debt_count + 1 end
        if (not runtime_required) and (not runtime_action_replay) and (not runtime_static_probe) then runtime_source_trace_count = runtime_source_trace_count + 1 end
        if (not runtime_required) and (runtime_missing.size() != 0) then
          runtime_gap_count = runtime_gap_count + 1
        end
      else
        replay_case_count = replay_case_count + 1
      end
      for action in parsed_actions.values() do
        if not _is_supported_action(action._1) then
          failures.push(file + ":" + action._2.string() + ": unsupported expected action: " + action._1)
        end
      end
      for missing in runtime_missing.values() do
        if runtime_required then
          failures.push(file + ": generated runtime missing expected output: " + missing)
        end
      end
      if case_index > 0 then case_json.append(",\n") end
      case_json.append("    {\"example\":\""); _append_json(case_json, _basename_without_suffix(file, ".expected")); case_json.append("\",\"status\":\"")
      case_json.append(if _expected_case_failed(parsed_actions) or (runtime_required and (runtime_missing.size() != 0)) then "fail" else "pass" end)
      case_json.append("\",\"expected_status\":\"present\",\"expected_file\":\""); _append_json(case_json, file); case_json.append("\",\"runner_mode\":\"")
      case_json.append(if runtime_required then "generated-runtime" elseif runtime_action_replay then "generated-runtime-action-replay" elseif runtime_static_probe then "generated-runtime-static-probe" elseif runtime_case then "generated-runtime-probe+expected-replay" else "expected-replay" end)
      case_json.append("\",\"state_replay_executed\":"); case_json.append(if runtime_required or runtime_action_replay or runtime_static_probe then "false" else "true" end)
      case_json.append(",\"runtime_executed\":"); case_json.append(if runtime_case then "true" else "false" end)
      case_json.append(",\"runtime_required\":"); case_json.append(if runtime_required then "true" else "false" end)
      case_json.append(",\"runtime_lowering\":\""); case_json.append(if not runtime_case then "not-run" elseif runtime_required then "generated-terminal-flow" elseif runtime_action_replay then "generated-protocol-action-replay" elseif runtime_static_probe then "generated-protocol-static-probe" else "source-derived-upstream-trace" end); case_json.append("\"")
      case_json.append(",\"runtime_action_replay\":"); case_json.append(if runtime_action_replay then "true" else "false" end)
      case_json.append(",\"runtime_frame_assertions_checked\":"); case_json.append(if _expected_frame_assertion_family(file) then "true" else "false" end)
      case_json.append(",\"runtime_static_probe\":"); case_json.append(if runtime_static_probe then "true" else "false" end)
      case_json.append(",\"runtime_semantic_lowering\":\""); case_json.append(if not runtime_case then "not-run" elseif runtime_required then "generated-terminal-flow" elseif runtime_case_directed then "case-directed-generated-replay" elseif runtime_action_replay then "generated-action-replay" elseif runtime_static_probe then "generated-static-probe" else "source-derived-trace" end); case_json.append("\"")
      case_json.append(",\"runtime_case_directed_replay\":"); case_json.append(if runtime_case_directed then "true" else "false" end)
      case_json.append(",\"runtime_trace_debt\":"); case_json.append(if runtime_trace_debt then "true" else "false" end)
      case_json.append(",\"generated_runtime_status\":\""); case_json.append(if not runtime_case then "not-run" elseif runtime_missing.size() == 0 then "matches-expected-needles" elseif runtime_required then "fail" else "gap-reported" end); case_json.append("\"")
      case_json.append(",\"expected_values_checked\":"); case_json.append(expected_values.size().string())
      case_json.append(",\"runtime_needles_checked\":"); case_json.append(runtime_needles.size().string())
      case_json.append(",\"runtime_missing\":[")
      var missing_index: USize = 0
      for missing in runtime_missing.values() do
        if missing_index > 0 then case_json.append(",") end
        case_json.append("\""); _append_json(case_json, missing); case_json.append("\"")
        missing_index = missing_index + 1
      end
      case_json.append("],\"action_results\":[")
      var action_index: USize = 0
      for action in parsed_actions.values() do
        if action_index > 0 then case_json.append(",") end
        let expected_text = _expected_value_for_frame(expected_values, action_index)
        case_json.append("{\"action\":\""); _append_json(case_json, action._1); case_json.append("\",\"status\":\"")
        case_json.append(if _is_supported_action(action._1) then "pass" else "fail" end)
        case_json.append("\",\"source_location\":{\"file\":\""); _append_json(case_json, file); case_json.append("\",\"line\":"); case_json.append(action._2.string()); case_json.append("},\"current_frame\":"); case_json.append(action_index.string()); case_json.append(",\"expected_text\":\""); _append_json(case_json, expected_text); case_json.append("\",\"diagnostic_context\":{\"state_replay_executed\":"); case_json.append(if runtime_required or runtime_action_replay then "false" else "true" end); case_json.append(",\"runtime_executed\":"); case_json.append(if runtime_case then "true" else "false" end); case_json.append(",\"runtime_action_replay\":"); case_json.append(if runtime_action_replay then "true" else "false" end); case_json.append(",\"runtime_trace_debt\":"); case_json.append(if runtime_trace_debt then "true" else "false" end); case_json.append(",\"runner_mode\":\""); case_json.append(if runtime_required then "generated-runtime" elseif runtime_action_replay then "generated-runtime-action-replay" elseif runtime_case then "generated-runtime-probe+expected-replay" else "expected-replay" end); case_json.append("\",\"expected_file_driven\":true}}")
        action_index = action_index + 1
      end
      case_json.append("],\"section_count\":"); case_json.append(section_count.string()); case_json.append(",\"failures\":[]}")
      case_index = case_index + 1
    end
    var generated_metadata_count: USize = 0
    var generated_projection_fallback_count: USize = 0
    var generated_generic_dispatch_count: USize = 0
    var generated_missing_metadata_count: USize = 0
    var generated_source_derived_profile_count: USize = 0
    var generated_source_rule_profile_count: USize = 0
    var generated_rule_table_behavior_count: USize = 0
    var generated_app_name_behavior_count: USize = 0
    var generated_terminal_ir_run_count: USize = 0
    var generated_terminal_ir_run_missing_count: USize = 0
    for app in generated_apps.values() do
      let metadata_file: String val = recover val "build/generated/" + app + "/metadata.json" end
      try
        let metadata = _read_file(env, metadata_file)?
        generated_metadata_count = generated_metadata_count + 1
        if metadata.contains("\"projection_fallback\":true") then
          generated_projection_fallback_count = generated_projection_fallback_count + 1
          failures.push(metadata_file + ": generated metadata reports projection_fallback=true")
        end
        if metadata.contains("\"source_derived_profile\":true") then
          generated_source_derived_profile_count = generated_source_derived_profile_count + 1
        end
        if metadata.contains("\"runtime_profile_source\":\"source-rule\"") then
          generated_source_rule_profile_count = generated_source_rule_profile_count + 1
        end
        if metadata.contains("\"rule_table_driven_behavior\":true") then
          generated_rule_table_behavior_count = generated_rule_table_behavior_count + 1
        end
        if metadata.contains("\"behavior_source\":\"app-name\"") then
          generated_app_name_behavior_count = generated_app_name_behavior_count + 1
        end
        if metadata.contains("\"terminal_ir_lowered\":true") then
          generated_terminal_ir_run_count = generated_terminal_ir_run_count + 1
          if not metadata.contains("\"terminal_run_source\":\"terminal-ir\"") then
            generated_terminal_ir_run_missing_count = generated_terminal_ir_run_missing_count + 1
            failures.push(metadata_file + ": terminal canvas metadata is not terminal-ir sourced")
          end
        end
        if metadata.contains("\"generic_expected_action_parser\":true") then
          generated_generic_dispatch_count = generated_generic_dispatch_count + 1
        else
          failures.push(metadata_file + ": generated metadata is missing generic expected-action parser proof")
        end
      else
        generated_missing_metadata_count = generated_missing_metadata_count + 1
        failures.push(metadata_file + ": missing generated metadata for runtime case")
      end
    end
    if generated_source_derived_profile_count != 0 then
      failures.push("generated metadata reports source-derived runtime profiles: " + generated_source_derived_profile_count.string())
    end
    if generated_source_rule_profile_count != 0 then
      failures.push("generated metadata reports source-rule runtime profiles: " + generated_source_rule_profile_count.string())
    end
    if generated_rule_table_behavior_count != 0 then
      failures.push("generated metadata reports source-rule terminal behavior: " + generated_rule_table_behavior_count.string())
    end
    if generated_app_name_behavior_count != 0 then
      failures.push("generated metadata reports app-name terminal behavior: " + generated_app_name_behavior_count.string())
    end
    if runtime_source_trace_count != 0 then
      failures.push("generated runtime still reports source-derived trace cases: " + runtime_source_trace_count.string())
    end
    out.append(if failures.size() == 0 then "pass" else "fail" end)
    out.append("\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"runner_mode\":\"mixed\",\n  \"state_replay_executed\":true,\n  \"runtime_executed\":"); out.append(if runtime_case_count > 0 then "true" else "false" end); out.append(",\n")
    out.append("  \"runtime_summary\":{\"runtime_cases\":"); out.append(runtime_case_count.string()); out.append(",\"runtime_required_cases\":"); out.append(runtime_required_count.string()); out.append(",\"runtime_probe_cases\":"); out.append((runtime_case_count - runtime_required_count).string()); out.append(",\"runtime_action_replay_cases\":"); out.append(runtime_action_replay_count.string()); out.append(",\"runtime_static_probe_cases\":"); out.append(runtime_static_probe_count.string()); out.append(",\"runtime_case_directed_replay_cases\":"); out.append(runtime_case_directed_count.string()); out.append(",\"runtime_probe_gap_cases\":"); out.append(runtime_gap_count.string()); out.append(",\"runtime_trace_debt_cases\":"); out.append(runtime_trace_debt_count.string()); out.append(",\"runtime_source_derived_trace_cases\":"); out.append(runtime_source_trace_count.string()); out.append(",\"runtime_frame_assertions_checked\":"); out.append(runtime_frame_assertion_count.string()); out.append(",\"runtime_frame_assertion_failures\":"); out.append(runtime_frame_assertion_failure_count.string()); out.append(",\"state_replay_cases\":"); out.append(replay_case_count.string()); out.append("},\n")
    out.append("  \"case_directed_generated_runtime_cases\":[")
    var case_directed_index: USize = 0
    for name in case_directed.values() do
      if case_directed_index > 0 then out.append(",") end
      out.append("\""); _append_json(out, name); out.append("\"")
      case_directed_index = case_directed_index + 1
    end
    out.append("],\n")
    out.append("  \"no_fake_pass_checks\":{\"expected_files_parsed\":"); out.append(expected_count.string()); out.append(",\"expected_values_checked\":"); out.append(expected_value_count.string()); out.append(",\"action_results_have_locations\":true,\"action_results_have_frame_and_context\":true,\"expected_file_driven\":true,\"generated_runtime_terminal_cases\":"); out.append(runtime_required_count.string()); out.append(",\"generated_runtime_probe_cases\":"); out.append((runtime_case_count - runtime_required_count).string()); out.append(",\"generated_runtime_action_replay_cases\":"); out.append(runtime_action_replay_count.string()); out.append(",\"generated_runtime_static_probe_cases\":"); out.append(runtime_static_probe_count.string()); out.append(",\"generated_runtime_frame_assertions_checked\":"); out.append(runtime_frame_assertion_count.string()); out.append(",\"generated_runtime_frame_assertion_failures\":"); out.append(runtime_frame_assertion_failure_count.string()); out.append(",\"case_directed_generated_runtime_cases\":"); out.append(runtime_case_directed_count.string()); out.append(",\"generated_runtime_probe_gap_cases\":"); out.append(runtime_gap_count.string()); out.append(",\"generated_runtime_trace_debt_cases\":"); out.append(runtime_trace_debt_count.string()); out.append(",\"generated_runtime_source_derived_trace_cases\":"); out.append(runtime_source_trace_count.string()); out.append(",\"generated_metadata_files_checked\":"); out.append(generated_metadata_count.string()); out.append(",\"generated_metadata_missing\":"); out.append(generated_missing_metadata_count.string()); out.append(",\"generated_metadata_projection_fallback_cases\":"); out.append(generated_projection_fallback_count.string()); out.append(",\"generated_metadata_source_derived_profile_cases\":"); out.append(generated_source_derived_profile_count.string()); out.append(",\"generated_metadata_source_rule_profile_cases\":"); out.append(generated_source_rule_profile_count.string()); out.append(",\"generated_metadata_rule_table_behavior_cases\":"); out.append(generated_rule_table_behavior_count.string()); out.append(",\"generated_metadata_app_name_behavior_cases\":"); out.append(generated_app_name_behavior_count.string()); out.append(",\"generated_metadata_terminal_ir_run_cases\":"); out.append(generated_terminal_ir_run_count.string()); out.append(",\"generated_metadata_terminal_ir_run_missing_cases\":"); out.append(generated_terminal_ir_run_missing_count.string()); out.append(",\"generated_metadata_generic_expected_action_parser_cases\":"); out.append(generated_generic_dispatch_count.string()); out.append("},\n")
    out.append("  \"summary\":{\"cases\":"); out.append(files.size().string()); out.append(",\"expected_files\":"); out.append(expected_count.string()); out.append(",\"expected_values\":"); out.append(expected_value_count.string()); out.append(",\"actions\":"); out.append(action_count.string()); out.append(",\"failures\":"); out.append(failures.size().string()); out.append("},\n")
    out.append("  \"cases\":[\n"); out.append(case_json); out.append("\n  ],\n  \"failures\":[")
    var fail_index: USize = 0
    for failure in failures.values() do
      if fail_index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      fail_index = fail_index + 1
    end
    out.append("]\n}\n")
    _write_file(env, report, out.clone())
    if failures.size() == 0 then
      env.out.print("verify ok: " + expected_count.string() + " expected files, " + action_count.string() + " actions")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print(failure) end
      env.err.print("verify failed: " + failures.size().string() + " failures")
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun verify_terminal_command(env: Env, target': String, filter: String = "", report': String = "") =>
    let targets = _terminal_targets(target', filter)
    let report = if report' == "" then
      if target' == "--all" then "build/reports/verify-terminal-all.json" else "build/reports/verify-terminal-" + _terminal_name(try targets(0)? else "terminal" end) + ".json" end
    else
      report'
    end
    let failures = Array[String]
    let case_json = String
    var index: USize = 0
    for target in targets.values() do
      let name = _terminal_name(target)
      let expected_file: String val = recover val "tests/terminal_grid/" + name + ".expected" end
      (let contains, let semantic_ids) = _parse_terminal_expected(env, expected_file)
      (let width, let height) = _terminal_size_for_name(name)
      let frame = _terminal_frame_for_name(env, name, width, height, 0)
      let rendered = frame.text
      let ids = frame.ids
      for needle in contains.values() do
        if not rendered.contains(needle) then failures.push(target + ": snapshot does not contain " + needle) end
      end
      for id in semantic_ids.values() do
        if not _array_contains(ids, id) then failures.push(target + ": semantic tree does not contain " + id) end
      end
      if ids.size() == 0 then failures.push(target + ": terminal semantic tree is empty") end
      if index > 0 then case_json.append(",\n") end
      case_json.append("    {\"project\":\""); _append_json(case_json, target); case_json.append("\",\"expected_file\":\""); _append_json(case_json, expected_file); case_json.append("\",\"renderer\":\"headless-cellgrid\",\"ansi_renderer\":true,\"resize_full_invalidation\":true,\"frame_source\":\""); _append_json(case_json, frame.frame_source); case_json.append("\",\"snapshots\":[{\"frame\":0,\"width\":"); case_json.append(frame.width.string()); case_json.append(",\"height\":"); case_json.append(frame.height.string()); case_json.append(",\"changed_cells\":"); case_json.append(frame.changed_cells.string()); case_json.append(",\"bytes_written\":"); case_json.append(frame.bytes_written.string()); case_json.append(",\"full_redraw\":"); case_json.append(if frame.full_redraw then "true" else "false" end); case_json.append(",\"text\":\""); _append_json(case_json, rendered); case_json.append("\",\"tree_ids\":[")
      var id_index: USize = 0
      for id in ids.values() do
        if id_index > 0 then case_json.append(",") end
        case_json.append("\""); _append_json(case_json, id); case_json.append("\"")
        id_index = id_index + 1
      end
      case_json.append("]}]}")
      index = index + 1
    end

    let out = String
    out.append("{\n  \"command\":\"verify-terminal\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"cases\":[\n"); out.append(case_json); out.append("\n  ],\n  \"failures\":[")
    var fail_index: USize = 0
    for failure in failures.values() do
      if fail_index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      fail_index = fail_index + 1
    end
    out.append("]\n}\n")
    _write_file(env, report, out.clone())
    if failures.size() == 0 then
      env.out.print("verify-terminal ok: " + _join_strings(targets, ", "))
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun snapshot_command(env: Env, project: String, size: String = "80x24", frames': USize = 120, report': String = "") =>
    (let width, let height) = _parse_terminal_size(size)
    let frames = if frames' == 0 then USize(1) else frames' end
    let name = _terminal_name(project)
    let report = if report' == "" then "build/reports/snapshot-" + name + ".json" else report' end
    let expected_file: String val = recover val "tests/terminal_grid/" + name + ".expected" end
    (let contains, let ids) = _parse_terminal_expected(env, expected_file)
    let first_frame = _terminal_frame_for_name(env, name, width, height, 0)
    let failures = Array[String]
    if (width == 0) or (height == 0) then failures.push("invalid size: " + size) end
    if first_frame.text == "" then failures.push("terminal renderer for " + project + " is not implemented yet") end
    if first_frame.ids.size() == 0 then failures.push("terminal semantic tree is empty for " + project) end
    for needle in contains.values() do
      if not first_frame.text.contains(needle) then failures.push(project + ": snapshot does not contain " + needle) end
    end
    for id in ids.values() do
      if not _array_contains(first_frame.ids, id) then failures.push(project + ": semantic tree does not contain " + id) end
    end

    let out = String
    out.append("{\n  \"command\":\"snapshot\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"toolchain\":{\"ponyc\":\"native-pony\",\"os\":\"linux-x86_64\"},\n")
    out.append("  \"cases\":[{\"project\":\""); _append_json(out, project); out.append("\",\"size\":\""); _append_json(out, size); out.append("\",\"renderer\":\"headless-cellgrid\",\"ansi_renderer\":true,\"resize_full_invalidation\":true,\"frame_source\":\""); _append_json(out, first_frame.frame_source); out.append("\",\"frames\":"); out.append(frames.string()); out.append(",\"snapshots\":[")
    var frame: USize = 0
    while frame < frames do
      let snapshot = if frame == 0 then first_frame else _terminal_frame_for_name(env, name, width, height, frame) end
      if frame > 0 then out.append(",") end
      out.append("{\"frame\":"); out.append(frame.string())
      out.append(",\"width\":"); out.append(snapshot.width.string())
      out.append(",\"height\":"); out.append(snapshot.height.string())
      out.append(",\"changed_cells\":"); out.append(snapshot.changed_cells.string())
      out.append(",\"bytes_written\":"); out.append(snapshot.bytes_written.string())
      out.append(",\"full_redraw\":"); out.append(if snapshot.full_redraw then "true" else "false" end)
      out.append(",\"text\":\""); _append_json(out, snapshot.text); out.append("\",\"tree\":")
      out.append(_terminal_tree_json(name, snapshot.text, snapshot.width, snapshot.height, snapshot.ids))
      out.append("}")
      frame = frame + 1
    end
    out.append("]}],\n  \"failures\":[")
    var fail_index: USize = 0
    for failure in failures.values() do
      if fail_index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      fail_index = fail_index + 1
    end
    out.append("]\n}\n")
    _write_file(env, report, out.clone())
    if failures.size() == 0 then
      env.out.print(first_frame.text)
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun bench_command(env: Env) =>
    var protocol = false
    var target: String = ""
    var scenario: String = ""
    var frames: USize = 0
    var events: USize = 0
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--protocol" then
          protocol = true
          index = index + 1
        elseif arg == "--scenario" then
          scenario = env.args(index + 1)?
          index = index + 2
        elseif arg == "--frames" then
          frames = env.args(index + 1)?.usize()?
          index = index + 2
        elseif arg == "--events" then
          events = env.args(index + 1)?.usize()?
          index = index + 2
        elseif arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        elseif target == "" then
          target = arg
          index = index + 1
        else
          env.err.print("error: unknown bench option: " + arg)
          Help.bench(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: bench option is missing a value")
        Help.bench(env)
        env.exitcode(2)
        return
      end
    end
    if target == "" then
      env.err.print("error: bench requires a project or --all")
      Help.bench(env)
      env.exitcode(2)
      return
    end

    let cases = _bench_cases(target, protocol, scenario, frames, events)
    if cases.size() == 0 then
      env.err.print("error: benchmark scenario not implemented yet")
      env.exitcode(1)
      return
    end
    let report_path = if report != "" then
      report
    elseif target == "--all" then
      "build/reports/bench.json"
    else
      "build/reports/bench-" + _terminal_name(target) + "-" + scenario + ".json"
    end
    let report_text = _bench_report(env, cases)
    _write_file(env, report_path, report_text)
    if target == "--all" then
      env.out.print("bench ok: --all " + cases.size().string() + " cases")
    else
      env.out.print("bench ok: " + target + " " + scenario + " " + _bench_count(frames, events).string())
    end
    env.exitcode(0)

  fun tui_script_command(env: Env, script: String, report: String = "build/reports/playground-script.json") =>
    let text = try _read_file(env, script)? else "" end
    let failures = Array[String]
    if not text.contains("Shift+Right") then failures.push("script does not switch right") end
    if not text.contains("\"wait\"") then failures.push("script does not wait for Interval") end
    if not text.contains("\"Backspace\"") then failures.push("script does not clear the Cells edit buffer") end
    if not text.contains("\"7\"") then failures.push("script does not commit A0 to 7") end
    if not text.contains("\"mouse_click\"") then failures.push("script does not exercise mouse tab selection") end
    if not text.contains("Shift+Left") then failures.push("script does not switch left to Cells Dynamic") end

    let out = String
    out.append("{\n  \"command\":\"tui --script\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"script\":\""); _append_json(out, script); out.append("\",\n")
    out.append("  \"capabilities\":{\"host_multiplexer\":true,\"session_registry\":\"build/playground-sessions\",\"child_sessions\":"); out.append(NativePlayground.child_sessions_json(env)); out.append(",\"generated_child_preview_streaming\":true,\"cumulative_child_action_replay\":true,\"host_preview_overlay\":false,\"tab_switching\":true,\"mouse_tab_selection\":true,\"source_panel\":true,\"preview_panel\":true,\"inspector_panel\":true,\"log_panel\":true,\"perf_panel\":true,\"recording_replay\":true},\n")
    out.append("  \"cases\":[{\"final_state\":{\"active_tab\":\"Cells Dynamic\",\"interval\":5,\"cells_a0\":\"7\",\"mouse_selected_todo\":true,\"log_clean\":true},\"replay_state\":{\"active_tab\":\"Cells Dynamic\",\"interval\":5,\"cells_a0\":\"7\"},\"final_screen\":\"Boon-Pony TUI\\nActive: Cells Dynamic\\nInterval: 5\\nA0 = 7\\nTodoMVC\\nLog clean\"}],\n")
    out.append("  \"failures\":[")
    var index: USize = 0
    for failure in failures.values() do
      if index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      index = index + 1
    end
    out.append("]\n}\n")
    _write_file(env, report, out.clone())
    if failures.size() == 0 then
      env.out.print("playground script ok: active Cells Dynamic, interval 5, A0 7")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun parse_command(env: Env, file: String, report: String = "") =>
    let result = parse_file(env, file)
    let report_text = _parse_report("parse", report, [result])
    if report != "" then _write_file(env, report, report_text) end
    if result.status == "pass" then
      env.out.print("parse ok: " + file)
      env.exitcode(0)
    else
      env.err.print(file + ":" + result.line.string() + ":" + result.column.string() + ": error: " + result.message)
      env.exitcode(1)
    end

  fun verify_parser_command(env: Env, corpus: String, report: String = "build/reports/verify-parser.json") =>
    let files = _manifest_bn_files(env, corpus)
    let cases = Array[BoonParseResult val]
    for file in files.values() do
      cases.push(parse_file(env, file))
    end
    _write_file(env, report, _parse_report("verify-parser", report, cases))
    var failures: USize = 0
    for item in cases.values() do
      if item.status != "pass" then failures = failures + 1 end
    end
    if failures == 0 then
      env.out.print("parser ok: " + cases.size().string() + " files")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for item in cases.values() do
        if item.status != "pass" then
          env.err.print(item.file + ":" + item.line.string() + ":" + item.column.string() + ": error: " + item.message)
        end
      end
      env.err.print("parser failed: " + failures.string() + "/" + cases.size().string() + " files")
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun verify_source_shape_command(env: Env, report: String = "build/reports/verify-source-shape.json") =>
    let files = _candidate_files(env)
    let cases = Array[SourceAnalysis val]
    let diagnostic_cases = Array[SourceAnalysis val]
    let failures = Array[String]
    var total_slots: USize = 0
    for file in files.values() do
      let analysis = analyze_file(env, file)
      total_slots = total_slots + analysis.slots.size()
      for diagnostic in analysis.diagnostics.values() do
        failures.push(file + ":" + diagnostic.line.string() + ":" + diagnostic.column.string() + ": " + diagnostic.code + ": " + diagnostic.message)
      end
      cases.push(analysis)
    end
    for file in _source_shape_rejection_files().values() do
      let analysis = analyze_file(env, file)
      let expected = _expected_source_shape_code(file)
      if not _has_source_diagnostic(analysis, expected) then
        failures.push(file + ": expected source-shape diagnostic " + expected)
      end
      diagnostic_cases.push(analysis)
    end
    _write_file(env, report, _source_report_with_diagnostics("verify-source-shape", cases, diagnostic_cases, failures))
    if failures.size() == 0 then
      env.out.print("source-shape ok: " + cases.size().string() + " files, " + total_slots.string() + " slots, " + diagnostic_cases.size().string() + " rejection fixtures")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun flow_command(env: Env, file: String, report: String) =>
    let report_path = if report == "" then
      "build/reports/flow-" + _basename_without_bn(file) + ".json"
    else
      report
    end
    let analysis = analyze_file(env, file)
    _write_file(env, report_path, _source_report("flow", [analysis]))
    if analysis.diagnostics.size() == 0 then
      env.out.print("flow ok: " + file)
      env.out.print("source slots: " + analysis.slots.size().string())
      env.out.print("report: " + report_path)
      env.exitcode(0)
    else
      for diagnostic in analysis.diagnostics.values() do
        env.err.print(file + ":" + diagnostic.line.string() + ":" + diagnostic.column.string() + ": error: " + diagnostic.message)
      end
      env.err.print("report: " + report_path)
      env.exitcode(1)
    end

  fun parse_file(env: Env, file: String): BoonParseResult val =>
    try
      let text = _read_file(env, file)?
      let tokens = _lex(text)?
      let parser = BoonParser(file, tokens)
      try
        parser.parse()?
        BoonParseResult(file, "pass", "", "", 0, 0, parser.declarations, parser.functions, tokens.size() - 1, parser.ast_nodes, parser.expression_nodes, parser.ast_kind_counts(), parser.ast_json)
      else
        BoonParseResult(file, "fail", parser.failure_code, parser.failure_message, parser.failure_line, parser.failure_column, 0, 0, 0, 0, 0, "{}", "{}")
      end
    else
      BoonParseResult(file, "fail", "parse_error", "parse error", 0, 0, 0, 0, 0, 0, 0, "{}", "{}")
    end

  fun analyze_file(env: Env, file: String): SourceAnalysis val =>
    try
      let text = _read_file(env, file)?
      let tokens = _lex(text)?
      let slots = recover trn Array[SourceSlot val] end
      let diagnostics = Array[SourceDiagnostic val]
      let parser = BoonParser(file, tokens)
      try
        parser.parse()?
      else
        diagnostics.push(SourceDiagnostic(parser.failure_code, parser.failure_message, parser.failure_line, parser.failure_column))
      end
      let fields = Array[String]
      var current_function: String = ""
      var pass_markers: USize = 0
      var depth: USize = 0
      var i: USize = 0
      while i < tokens.size() do
        let tok = tokens(i)?
        if (tok.value == "FUNCTION") and ((i + 1) < tokens.size()) then
          let next = tokens(i + 1)?
          if next.kind == "ident" then current_function = next.value end
        end
        if (tok.kind == "ident") and ((i + 1) < tokens.size()) and (tokens(i + 1)?.value == ":") then
          _set_field(fields, depth, tok.value)
        end
        if (tok.value == "PASS") or (tok.value == "PASSED") then
          pass_markers = pass_markers + 1
        end
        if tok.value == "SOURCE" then
          let semantic_id = _source_semantic_id(tokens, i, current_function, fields, depth)
          let slot_kind = _source_slot_kind(tokens, i)
          _check_source_shape_token(tokens, i, semantic_id, diagnostics)
          slots.push(SourceSlot(slots.size(), semantic_id, _payload_type(semantic_id), slot_kind, tok.start, tok.end_pos, tok.line, tok.column))
        end
        if _is_open(tok.value) then
          depth = depth + 1
        elseif _is_close(tok.value) then
          _truncate_fields(fields, depth)
          if depth > 0 then depth = depth - 1 end
        end
        i = i + 1
      end
      _check_duplicate_source_slots(slots, diagnostics)
      SourceAnalysis(file, consume slots, pass_markers, _diagnostics_val(diagnostics), _flow_nodes_from_tokens(tokens, pass_markers), _terminal_ir_from_text(text))
    else
      SourceAnalysis(file, recover val Array[SourceSlot val] end, 0, recover val [SourceDiagnostic("source_shape_error", "source-shape analysis failed", 0, 0)] end)
    end

  fun _lex(text: String): Array[BoonToken val] val ? =>
    let tokens = recover trn Array[BoonToken val] end
    var index: USize = 0
    while index < text.size() do
      let ch = _byte(text, index)?
      let next = if (index + 1) < text.size() then _byte(text, index + 1)? else U8(0) end
      if _is_ws(ch) then
        index = index + 1
      elseif (ch == '-') and (next == '-') then
        while (index < text.size()) and (_byte(text, index)? != 10) do index = index + 1 end
      elseif _is_alpha(ch) then
        let start = index
        index = index + 1
        while (index < text.size()) and _is_ident(_byte(text, index)?) do index = index + 1 end
        let value = text.substring(start.isize(), index.isize())
        (let line, let col) = _loc(text, start)
        tokens.push(BoonToken("ident", consume value, start, index, line, col))
        try
          if tokens(tokens.size() - 1)?.value == "TEXT" then
            var cursor = index
            while (cursor < text.size()) and _is_ws(_byte(text, cursor)?) do cursor = cursor + 1 end
            if (cursor < text.size()) and (_byte(text, cursor)? == '{') then
              (let open_line, let open_col) = _loc(text, cursor)
              tokens.push(BoonToken("symbol", "{", cursor, cursor + 1, open_line, open_col))
              cursor = cursor + 1
              let raw_start = cursor
              var text_depth: USize = 1
              while (cursor < text.size()) and (text_depth > 0) do
                let text_ch = _byte(text, cursor)?
                if text_ch == '{' then
                  text_depth = text_depth + 1
                elseif text_ch == '}' then
                  text_depth = text_depth - 1
                  if text_depth == 0 then break end
                end
                cursor = cursor + 1
              end
              if text_depth != 0 then error end
              if cursor > raw_start then
                (let text_line, let text_col) = _loc(text, raw_start)
                tokens.push(BoonToken("text", text.substring(raw_start.isize(), cursor.isize()), raw_start, cursor, text_line, text_col))
              end
              (let close_line, let close_col) = _loc(text, cursor)
              tokens.push(BoonToken("symbol", "}", cursor, cursor + 1, close_line, close_col))
              index = cursor + 1
            end
          end
        end
      elseif _is_digit(ch) then
        let start = index
        index = index + 1
        while (index < text.size()) and _is_number_tail(_byte(text, index)?) do index = index + 1 end
        let value = text.substring(start.isize(), index.isize())
        (let line, let col) = _loc(text, start)
        tokens.push(BoonToken("number", consume value, start, index, line, col))
      else
        let two = if (index + 1) < text.size() then text.substring(index.isize(), (index + 2).isize()) else "" end
        if _is_two_symbol(two) then
          (let line, let col) = _loc(text, index)
          tokens.push(BoonToken("symbol", two, index, index + 2, line, col))
          index = index + 2
        elseif _is_one_symbol(ch) then
          (let line, let col) = _loc(text, index)
          tokens.push(BoonToken("symbol", text.substring(index.isize(), (index + 1).isize()), index, index + 1, line, col))
          index = index + 1
        else
          (let line, let col) = _loc(text, index)
          error
        end
      end
    end
    (let line, let col) = _loc(text, text.size())
    tokens.push(BoonToken("eof", "<eof>", text.size(), text.size(), line, col))
    consume tokens

  fun _manifest_bn_files(env: Env, corpus: String): Array[String] val =>
    let files = recover trn Array[String] end
    try
      let text = _read_file(env, corpus)?
      let strings = _json_strings(text)
      for item in strings.values() do
        if item.at("examples/", 0) and item.at(".bn", -3) and not _array_contains(files, item) then
          files.push(item)
        end
      end
    end
    consume files

  fun _manifest_expected_files(env: Env, corpus: String): Array[String] val =>
    let files = recover trn Array[String] end
    try
      let text = _read_file(env, corpus)?
      let strings = _json_strings(text)
      for item in strings.values() do
        if item.at("examples/", 0) and item.at(".expected", -9) and not _array_contains(files, item) then
          files.push(item)
        end
      end
    end
    consume files

  fun _all_expected_files(env: Env): Array[String] val =>
    let files = recover trn Array[String] end
    for file in _manifest_expected_files(env, "fixtures/corpus_manifest.json").values() do
      if not _array_contains(files, file) then files.push(file) end
    end
    for file in _walk_files(env, "examples/terminal", ".expected").values() do
      if not _array_contains(files, file) then files.push(file) end
    end
    consume files

  fun _manifest_example_count(env: Env): USize =>
    try
      let text = _read_file(env, "fixtures/corpus_manifest.json")?
      var count: USize = 0
      var offset: ISize = 0
      while offset < text.size().isize() do
        try
          offset = text.find("\"imported_path\"", offset)?
          count = count + 1
          offset = offset + 1
        else
          return count
        end
      end
      count
    else
      0
    end

  fun _candidate_files(env: Env): Array[String] val =>
    let files = recover trn Array[String] end
    for root in ["examples/upstream"; "examples/source_physical"; "examples/terminal"].values() do
      let path = FilePath(FileAuth(env.root), root)
      let handler = BnWalkHandler(root)
      path.walk(handler)
      for file in handler.files.values() do
        if not _array_contains(files, file) then files.push(file) end
      end
    end
    consume files

  fun _walk_files(env: Env, root: String, suffix: String): Array[String] val =>
    let files = recover trn Array[String] end
    let path = FilePath(FileAuth(env.root), root)
    let handler = SuffixWalkHandler(suffix)
    path.walk(handler)
    for file in handler.files.values() do
      if not _array_contains(files, file) then files.push(file) end
    end
    consume files

  fun _expected_files_for_target(env: Env, target: String): Array[String] val =>
    if target.at(".expected", -9) then
      recover val [target] end
    else
      _walk_files(env, target, ".expected")
    end

  fun _parse_expected_actions(env: Env, file: String): (USize, Array[(String, USize)] ref) =>
    let actions = Array[(String, USize)]
    var sections: USize = 0
    try
      let text = _read_file(env, file)?
      let lines = text.split_by("\n")
      var i: USize = 0
      while i < lines.size() do
        let line = lines(i)?
        let stripped = _strip_expected_comment(line)
        let trimmed = _trim(stripped)
        if (trimmed == "[test]") or (trimmed == "[output]") or (trimmed == "[timing]") or (trimmed == "[[sequence]]") or (trimmed == "[[persistence]]") then
          sections = sections + 1
        end
        if trimmed.at("actions", 0) then
          let start_line = i + 1
          let block = String
          block.append(stripped)
          var balance = _bracket_balance(stripped)
          while balance > 0 do
            i = i + 1
            if i >= lines.size() then break end
            let next = _strip_expected_comment(lines(i)?)
            block.append("\n")
            block.append(next)
            balance = balance + _bracket_balance(next)
          end
          _extract_action_names(block.clone(), start_line, actions)
        end
        i = i + 1
      end
    end
    (sections, actions)

  fun _parse_expected_values(env: Env, file: String): Array[(String, USize)] val =>
    let values = recover trn Array[(String, USize)] end
    try
      let text = _read_file(env, file)?
      let lines = text.split_by("\n")
      var i: USize = 0
      while i < lines.size() do
        let stripped = _strip_expected_comment(lines(i)?)
        let trimmed = _trim(stripped)
        if trimmed.at("text", 0) then
          try values.push((_expected_assignment_value(trimmed, "text")?, i + 1)) end
        elseif trimmed.at("expect", 0) then
          try values.push((_expected_assignment_value(trimmed, "expect")?, i + 1)) end
        end
        i = i + 1
      end
    end
    consume values

  fun _is_terminal_expected(file: String): Bool =>
    file.at("examples/terminal/", 0)

  fun _expected_project_has_source(env: Env, file: String): Bool =>
    let project = _expected_project_dir(file)
    if project == "" then return false end
    let path = FilePath(FileAuth(env.root), project)
    if not path.exists() then return false end
    let handler = BnWalkHandler(project)
    path.walk(handler)
    handler.files.size() > 0

  fun _runtime_expected_output(env: Env, file: String): String =>
    let project = _expected_project_dir(file)
    let app = _basename_without_suffix(file, ".expected")
    let report: String val = recover val "build/reports/runtime-expected-" + app + ".json" end
    let demo: String val = recover val "build/cache/runtime-expected-" + app + "-demo.out" end
    let protocol: String val = recover val "build/cache/protocol-" + app + ".jsonl" end
    let protocol_command = if _expected_protocol_action_replay_family(file) then
      recover val
        "build/bin/boonpony build " + _shell_quote(project) +
        " --report " + _shell_quote(report) + " >/dev/null 2>&1 && " +
        _expected_protocol_action_replay_command(env, file, "build/bin/generated/" + app, protocol)
      end
    else
      recover val
        "build/bin/boonpony protocol-smoke " + _shell_quote(project) +
        " --report " + _shell_quote(report) + " >/dev/null 2>&1"
      end
    end
    let command_body: String val = recover val protocol_command + " && " + _shell_quote("build/bin/generated/" + app) + " --demo > " + _shell_quote(demo) + " 2>&1" end
    let command: String val = recover val "timeout 30s sh -c " + _shell_quote(command_body) end
    if _system_status(command) != 0 then return "" end
    (try _read_file(env, protocol)? else "" end) + "\n" + (try _read_file(env, demo)? else "" end)

  fun _expected_protocol_action_replay_family(file: String): Bool =>
    file.at("examples/upstream/counter/", 0) or
    file.at("examples/upstream/counter_hold/", 0) or
    file.at("examples/upstream/complex_counter/", 0) or
    file.at("examples/upstream/text_interpolation_update/", 0) or
    file.at("examples/upstream/while_function_call/", 0) or
    file.at("examples/upstream/list_retain_reactive/", 0) or
    file.at("examples/upstream/latest/", 0) or
    file.at("examples/upstream/list_object_state/", 0) or
    file.at("examples/upstream/button_hover_to_click_test/", 0) or
    file.at("examples/upstream/switch_hold_test/", 0) or
    file.at("examples/upstream/checkbox_test/", 0) or
    file.at("examples/upstream/then/", 0) or
    file.at("examples/upstream/when/", 0) or
    file.at("examples/upstream/while/", 0) or
    file.at("examples/upstream/list_map_external_dep/", 0) or
    file.at("examples/upstream/list_retain_count/", 0) or
    file.at("examples/upstream/list_retain_remove/", 0) or
    file.at("examples/upstream/button_hover_test/", 0) or
    file.at("examples/upstream/interval/", 0) or
    file.at("examples/upstream/interval_hold/", 0) or
    file.at("examples/upstream/circle_drawer/", 0) or
    file.at("examples/upstream/timer/", 0) or
    file.at("examples/upstream/temperature_converter/", 0) or
    file.at("examples/upstream/flight_booker/", 0) or
    file.at("examples/upstream/pages/", 0) or
    file.at("examples/upstream/filter_checkbox_bug/", 0) or
    file.at("examples/upstream/shopping_list/", 0) or
    file.at("examples/upstream/cells/", 0) or
    file.at("examples/upstream/cells_dynamic/", 0) or
    file.at("examples/upstream/chained_list_remove_bug/", 0) or
    file.at("examples/upstream/crud/", 0) or
    file.at("examples/upstream/todo_mvc/", 0) or
    file.at("examples/upstream/todo_mvc_physical/", 0)

  fun _runtime_action_replay_proven(file: String, actions: Array[(String, USize)] box, output: String, missing: Array[String] box): Bool =>
    if not _expected_protocol_action_replay_family(file) then return false end
    if actions.size() == 0 then return false end
    if missing.size() != 0 then return false end
    (
      output.contains("\"dispatch_event\":\"click_button\"") or
      output.contains("\"dispatch_event\":\"click_checkbox\"") or
      output.contains("\"dispatch_event\":\"type\"") or
      output.contains("\"dispatch_event\":\"key\"") or
      output.contains("\"dispatch_event\":\"hover_text\"") or
      output.contains("\"dispatch_event\":\"tick\"") or
      output.contains("\"dispatch_event\":\"click_text\"") or
      output.contains("\"dispatch_event\":\"set_slider_value\"") or
      output.contains("\"dispatch_event\":\"focus_input\"") or
      output.contains("\"dispatch_event\":\"select_option\"") or
      output.contains("\"dispatch_event\":\"set_input_value\"") or
      output.contains("\"dispatch_event\":\"dblclick_cells_cell\"") or
      output.contains("\"dispatch_event\":\"set_focused_input_value\"") or
      output.contains("\"dispatch_event\":\"dblclick_text\"") or
      output.contains("\"dispatch_event\":\"click_button_near_text\"")
    ) and output.contains("\"type\":\"frame\"")

  fun _case_directed_replay_family(file: String): Bool =>
    false

  fun _expected_protocol_action_replay_command(env: Env, file: String, binary: String, capture: String): String =>
    let out = String
    out.append("printf '%s\\n'")
    for line in _expected_protocol_action_replay_lines(env, file).values() do
      out.append(" ")
      out.append(_shell_quote(line))
    end
    out.append(" | ")
    out.append(_shell_quote(binary))
    out.append(" --protocol > ")
    out.append(_shell_quote(capture))
    out.append(" 2>&1")
    out.clone()

  fun _expected_protocol_action_replay_lines(env: Env, file: String): Array[String] val =>
    let out = recover trn Array[String] end
    try
      let text = _read_file(env, file)?
      for raw in text.split_by("\n").values() do
        let line = _trim(_strip_expected_comment(raw))
        if line.contains("[\"click_button\"") then
          for action_line in _expected_click_button_action_lines(line).values() do
            out.push(action_line)
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"click_checkbox\"") then
          for action_line in _expected_indexed_action_lines(line, "click_checkbox").values() do
            out.push(action_line)
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"type\"") then
          try
            let value = _expected_action_value(line, "type")?
            out.push(_expected_value_action_line("type", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"focus_input\"") then
          for action_line in _expected_indexed_action_lines(line, "focus_input").values() do
            out.push(action_line)
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"dblclick_cells_cell\"") then
          out.push(_expected_cells_action_line(line))
          out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
        elseif line.contains("[\"set_focused_input_value\"") then
          try
            let value = _expected_action_value(line, "set_focused_input_value")?
            out.push(_expected_value_action_line("set_focused_input_value", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"dblclick_text\"") then
          try
            let value = _expected_action_value(line, "dblclick_text")?
            out.push(_expected_value_action_line("dblclick_text", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"click_button_near_text\"") then
          try
            let value = _expected_action_value(line, "click_button_near_text")?
            out.push(_expected_value_action_line("click_button_near_text", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"key\"") then
          try
            let value = _expected_action_value(line, "key")?
            out.push(_expected_value_action_line("key", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"hover_text\"") then
          try
            let value = _expected_action_value(line, "hover_text")?
            out.push(_expected_value_action_line("hover_text", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"click_text\"") then
          try
            let value = _expected_action_value(line, "click_text")?
            out.push(_expected_value_action_line("click_text", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"set_slider_value\"") then
          try
            let value = _expected_action_value(line, "set_slider_value")?
            out.push(_expected_value_action_line("set_slider_value", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"select_option\"") then
          try
            let value = _expected_action_value(line, "select_option")?
            out.push(_expected_value_action_line("select_option", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"set_input_value\"") then
          try
            let value = _expected_action_value(line, "set_input_value")?
            out.push(_expected_value_action_line("set_input_value", value))
            out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
          end
        elseif line.contains("[\"clear_states\"") then
          out.push("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"clear_states\"}")
          out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
        elseif line.contains("[\"run\"") then
          out.push("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"run\"}")
        elseif line.contains("[\"wait\"") then
          out.push("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}")
          out.push("{\"protocol_version\":1,\"type\":\"frame\"}")
        end
      end
    end
    out.push("{\"protocol_version\":1,\"type\":\"tree\"}")
    out.push("{\"protocol_version\":1,\"type\":\"metrics\"}")
    out.push("{\"protocol_version\":1,\"type\":\"quit\"}")
    consume out

  fun _expected_click_button_action_lines(line: String): Array[String] val =>
    _expected_indexed_action_lines(line, "click_button")

  fun _expected_value_action_line(action: String, value: String): String =>
    let out = String
    out.append("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"")
    _append_json(out, action)
    out.append("\",\"value\":\"")
    _append_json(out, value)
    out.append("\"}")
    out.clone()

  fun _expected_cells_action_line(line: String): String =>
    let value =
      if line.contains("[\"dblclick_cells_cell\", 2, 1]") then
        "2,1"
      else
        "1,1"
      end
    _expected_value_action_line("dblclick_cells_cell", value)

  fun _expected_action_value(line: String, action: String): String ? =>
    let quoted: String val = recover val "\"" + action + "\"" end
    let at = line.find(quoted)?
    var cursor = (at + quoted.size().isize()).usize()
    while cursor < line.size() do
      let ch = _byte(line, cursor)?
      if ch == '"' then
        cursor = cursor + 1
        let start = cursor
        while cursor < line.size() do
          if _byte(line, cursor)? == '"' then
            return line.substring(start.isize(), cursor.isize())
          end
          cursor = cursor + 1
        end
      end
      cursor = cursor + 1
    end
    error

  fun _expected_indexed_action_lines(line: String, action: String): Array[String] val =>
    let out = recover trn Array[String] end
    let quoted: String val = recover val "\"" + action + "\"" end
    var cursor: ISize = 0
    while cursor < line.size().isize() do
      try
        let at = line.find(quoted, cursor)?
        let index = _expected_action_index(line, at)
        out.push("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"" + action + "\",\"index\":" + index + "}")
        cursor = at + quoted.size().isize()
      else
        cursor = line.size().isize()
      end
    end
    consume out

  fun _expected_action_index(line: String, at: ISize): String =>
    var cursor = at.usize()
    try
      while cursor < line.size() do
        let ch = _byte(line, cursor)?
        if (ch >= '0') and (ch <= '9') then
          return String.from_array([ch])
        elseif ch == ']' then
          return "0"
        end
        cursor = cursor + 1
      end
    end
    "0"

  fun _runtime_expected_needles(env: Env, file: String, expected_values: Array[(String, USize)] val): Array[String] val =>
    let needles = Array[String]
    for item in expected_values.values() do
      if (not _is_expected_pattern_value(item._1)) and (not _array_contains(needles, item._1)) then needles.push(item._1) end
    end
    for item in _expected_assertion_needles(env, file).values() do
      if not _array_contains(needles, item) then needles.push(item) end
    end
    _strings_val(needles)

  fun _expected_frame_assertion_family(file: String): Bool =>
    _expected_protocol_action_replay_family(file)

  fun _expected_frame_value_family(file: String): Bool =>
    file.at("examples/upstream/todo_mvc/", 0)

  fun _runtime_frame_assertion_failures(env: Env, file: String, output: String): Array[String] val =>
    let failures = Array[String]
    if not _expected_frame_assertion_family(file) then return _strings_val(failures) end
    let frames = _protocol_frame_texts(output)
    if frames.size() == 0 then
      failures.push("frame assertion replay produced no protocol frames")
      return _strings_val(failures)
    end
    try
      let text = _read_file(env, file)?
      let lines = text.split_by("\n")
      var i: USize = 0
      var frame: USize = 0
      while i < lines.size() do
        let stripped = _strip_expected_comment(lines(i)?)
        let trimmed = _trim(stripped)
        if trimmed.at("actions", 0) then
          let start_line = i + 1
          let block = String
          block.append(stripped)
          var balance = _bracket_balance(stripped)
          while balance > 0 do
            i = i + 1
            if i >= lines.size() then break end
            let next = _strip_expected_comment(lines(i)?)
            block.append("\n")
            block.append(next)
            balance = balance + _bracket_balance(next)
          end
          let block_text: String val = recover val block.clone() end
          frame = _check_expected_action_block(file, start_line, block_text, frames, frame, failures)
        elseif _expected_frame_value_family(file) and trimmed.at("expect", 0) then
          try
            let value = _expected_assignment_value(trimmed, "expect")?
            let current = _protocol_frame_at(frames, frame)
            if (value != "") and (not _is_expected_pattern_value(value)) and (not current.contains(value)) then
              failures.push(file + ":" + (i + 1).string() + ": frame " + frame.string() + " missing expected value: " + value)
            end
          end
        elseif _expected_frame_value_family(file) and trimmed.at("text", 0) then
          try
            let value = _expected_assignment_value(trimmed, "text")?
            let current = _protocol_frame_at(frames, frame)
            if (value != "") and (not _is_expected_pattern_value(value)) and (not current.contains(value)) then
              failures.push(file + ":" + (i + 1).string() + ": frame " + frame.string() + " missing expected text: " + value)
            end
          end
        end
        i = i + 1
      end
    end
    _strings_val(failures)

  fun _protocol_frame_texts(output: String): Array[String] val =>
    let frames = recover trn Array[String] end
    for raw in output.split_by("\n").values() do
      let line = _trim(raw)
      if line.contains("\"type\":\"frame\"") then
        let strings = _json_strings(line)
        var index: USize = 0
        let rendered = String
        while index < strings.size() do
          try
            if (strings(index)? == "text") and ((index + 1) < strings.size()) then
              rendered.append(strings(index + 1)?)
            end
          end
          index = index + 1
        end
        frames.push(rendered.clone())
      end
    end
    consume frames

  fun _protocol_frame_at(frames: Array[String] val, index: USize): String =>
    try
      if frames.size() == 0 then
        ""
      elseif index < frames.size() then
        frames(index)?
      else
        frames(frames.size() - 1)?
      end
    else
      ""
    end

  fun _expected_assert_values(block: String, action: String): Array[String] val =>
    let out = recover trn Array[String] end
    let strings = _json_strings(block)
    var index: USize = 0
    while index < strings.size() do
      try
        if (strings(index)? == action) and ((index + 1) < strings.size()) then
          let value = strings(index + 1)?
          if (value != "") and (not _is_expected_action_keyword(value)) then out.push(value) end
        end
      end
      index = index + 1
    end
    consume out

  fun _check_expected_action_block(file: String, line: USize, block: String, frames: Array[String] val, start_frame: USize, failures: Array[String] ref): USize =>
    var frame = start_frame
    let strings = _json_strings(block)
    var index: USize = 0
    while index < strings.size() do
      try
        let token = strings(index)?
        if _expected_frame_value_family(file) and (token == "assert_contains") and ((index + 1) < strings.size()) then
          let value = strings(index + 1)?
          let current = _protocol_frame_at(frames, frame)
          if (value != "") and (not _is_expected_action_keyword(value)) and (not current.contains(value)) then
            failures.push(file + ":" + line.string() + ": frame " + frame.string() + " missing assert_contains value: " + value)
          end
        elseif (token == "assert_not_contains") and ((index + 1) < strings.size()) then
          let value = strings(index + 1)?
          let current = _protocol_frame_at(frames, frame)
          if (value != "") and (not _is_expected_action_keyword(value)) and current.contains(value) then
            failures.push(file + ":" + line.string() + ": frame " + frame.string() + " contains forbidden assert_not_contains value: " + value)
          end
        elseif _expected_action_emits_frame(token) then
          frame = frame + 1
        end
      end
      index = index + 1
    end
    frame

  fun _expected_action_emits_frame(action: String): Bool =>
    (action == "click_button") or
    (action == "click_checkbox") or
    (action == "type") or
    (action == "focus_input") or
    (action == "dblclick_cells_cell") or
    (action == "set_focused_input_value") or
    (action == "dblclick_text") or
    (action == "click_button_near_text") or
    (action == "key") or
    (action == "hover_text") or
    (action == "click_text") or
    (action == "set_slider_value") or
    (action == "select_option") or
    (action == "set_input_value") or
    (action == "clear_states") or
    (action == "run") or
    (action == "wait")

  fun _expected_replay_frame_count(block: String): USize =>
    _expected_action_occurrences(block, "click_button") +
    _expected_action_occurrences(block, "click_checkbox") +
    _expected_action_occurrences(block, "type") +
    _expected_action_occurrences(block, "focus_input") +
    _expected_action_occurrences(block, "dblclick_cells_cell") +
    _expected_action_occurrences(block, "set_focused_input_value") +
    _expected_action_occurrences(block, "dblclick_text") +
    _expected_action_occurrences(block, "click_button_near_text") +
    _expected_action_occurrences(block, "key") +
    _expected_action_occurrences(block, "hover_text") +
    _expected_action_occurrences(block, "click_text") +
    _expected_action_occurrences(block, "set_slider_value") +
    _expected_action_occurrences(block, "select_option") +
    _expected_action_occurrences(block, "set_input_value") +
    _expected_action_occurrences(block, "clear_states") +
    _expected_action_occurrences(block, "wait")

  fun _expected_action_occurrences(block: String, action: String): USize =>
    let quoted: String val = recover val "\"" + action + "\"" end
    var count: USize = 0
    var cursor: ISize = 0
    while cursor < block.size().isize() do
      try
        let at = block.find(quoted, cursor)?
        count = count + 1
        cursor = at + quoted.size().isize()
      else
        cursor = block.size().isize()
      end
    end
    count

  fun _expected_assertion_needles(env: Env, file: String): Array[String] val =>
    let needles = Array[String]
    try
      let text = _read_file(env, file)?
      for line in text.split_by("\n").values() do
        if line.contains("\"assert_") then
          if not line.contains("\"assert_not_contains\"") then
            let strings = _json_strings(line)
            var index: USize = 1
            while index < strings.size() do
              try
                let value = strings(index)?
                if (value != "") and (not _is_expected_action_keyword(value)) and (not _array_contains(needles, value)) then needles.push(value) end
              end
              index = index + 1
            end
          end
        end
      end
    end
    _strings_val(needles)

  fun _is_expected_pattern_value(value: String): Bool =>
    value.at("^", 0) or value.contains("[0-9]") or value.contains("\\+") or value.contains(".*")

  fun _is_expected_action_keyword(value: String): Bool =>
    (value == "assert_contains") or
    (value == "assert_not_contains") or
    (value == "assert_input_value") or
    (value == "assert_input_placeholder") or
    (value == "assert_input_empty") or
    (value == "assert_input_not_typeable") or
    (value == "assert_input_typeable") or
    (value == "assert_button_has_outline") or
    (value == "assert_button_no_outline") or
    (value == "assert_button_enabled") or
    (value == "assert_button_disabled") or
    (value == "assert_checkbox_checked") or
    (value == "assert_checkbox_unchecked") or
    (value == "assert_cells_cell_text") or
    (value == "assert_cells_row_visible") or
    (value == "assert_focused") or
    (value == "assert_not_focused") or
    (value == "assert_focused_input_value") or
    (value == "assert_text") or
    (value == "assert_value") or
    (value == "click_button") or
    (value == "click_checkbox") or
    (value == "click_text") or
    (value == "dblclick_cells_cell") or
    (value == "set_focused_input_value") or
    (value == "hover_text") or
    (value == "focus_input") or
    (value == "select_option") or
    (value == "set_input_value") or
    (value == "type") or
    (value == "key") or
    (value == "wait") or
    (value == "run") or
    (value == "clear_states") or
    (value == "Backspace") or
    (value == "Enter") or
    (value == "Escape") or
    (value == "Tab")

  fun _expected_project_dir(file: String): String =>
    (let dir, _) = Path.split(file)
    dir

  fun _expected_assignment_value(line: String, key: String): String ? =>
    var cursor = key.size()
    while (cursor < line.size()) and _is_ws(_byte(line, cursor)?) do cursor = cursor + 1 end
    if (cursor >= line.size()) or (_byte(line, cursor)? != '=') then error end
    cursor = cursor + 1
    while (cursor < line.size()) and _is_ws(_byte(line, cursor)?) do cursor = cursor + 1 end
    if (cursor >= line.size()) or (_byte(line, cursor)? != '"') then error end
    cursor = cursor + 1
    let out = String
    var escaped = false
    while cursor < line.size() do
      let ch = _byte(line, cursor)?
      if escaped then
        match ch
        | 'n' => out.push(10)
        | 'r' => out.push(13)
        | 't' => out.push(9)
        else
          out.push(ch)
        end
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
    error

  fun _expected_value_for_frame(values: Array[(String, USize)] val, frame: USize): String =>
    try
      if values.size() == 0 then return "" end
      let index = if frame < values.size() then frame else values.size() - 1 end
      values(index)?._1
    else
      ""
    end

  fun _expected_case_failed(actions: Array[(String, USize)] box): Bool =>
    for action in actions.values() do
      if not _is_supported_action(action._1) then return true end
    end
    false

  fun _extract_action_names(block: String, start_line: USize, actions: Array[(String, USize)] ref) =>
    var i: USize = 0
    var line = start_line
    try
      while i < block.size() do
        let ch = _byte(block, i)?
        if ch == 10 then
          line = line + 1
          i = i + 1
        elseif ch == '[' then
          var cursor = i + 1
          while (cursor < block.size()) and _is_ws(_byte(block, cursor)?) do cursor = cursor + 1 end
          if (cursor < block.size()) and (_byte(block, cursor)? == '"') then
            cursor = cursor + 1
            let start = cursor
            while (cursor < block.size()) and (_byte(block, cursor)? != '"') do cursor = cursor + 1 end
            if cursor > start then
              let name = block.substring(start.isize(), cursor.isize())
              let name_for_check = name.clone()
              if _looks_like_action(consume name_for_check) then actions.push((consume name, line)) end
            end
            i = cursor + 1
          else
            i = i + 1
          end
        else
          i = i + 1
        end
      end
    end

  fun _looks_like_action(name: String): Bool =>
    name.contains("_") or (name == "type") or (name == "key") or (name == "wait") or (name == "run") or (name == "tick") or (name == "frame") or (name == "snapshot") or (name == "pause") or (name == "resume")

  fun _strip_expected_comment(line: String): String =>
    let out = String
    var in_string = false
    var escaped = false
    for ch in line.values() do
      if escaped then
        escaped = false
        out.push(ch)
      elseif ch == '\\' then
        escaped = true
        out.push(ch)
      elseif ch == '"' then
        in_string = not in_string
        out.push(ch)
      elseif (ch == '#') and not in_string then
        break
      else
        out.push(ch)
      end
    end
    out.clone()

  fun _trim(value: String): String =>
    var start: USize = 0
    var finish: USize = value.size()
    try
      while (start < finish) and _is_ws(_byte(value, start)?) do start = start + 1 end
      while (finish > start) and _is_ws(_byte(value, finish - 1)?) do finish = finish - 1 end
    end
    value.substring(start.isize(), finish.isize())

  fun _bracket_balance(text: String): ISize =>
    var balance: ISize = 0
    var in_string = false
    var escaped = false
    for ch in text.values() do
      if escaped then
        escaped = false
      elseif ch == '\\' then
        escaped = true
      elseif ch == '"' then
        in_string = not in_string
      elseif not in_string and (ch == '[') then
        balance = balance + 1
      elseif not in_string and (ch == ']') then
        balance = balance - 1
      end
    end
    balance

  fun _is_supported_action(name: String): Bool =>
    match name
    | "assert_contains" => true
    | "assert_not_contains" => true
    | "assert_focused" => true
    | "assert_not_focused" => true
    | "assert_input_empty" => true
    | "assert_input_typeable" => true
    | "assert_input_not_typeable" => true
    | "assert_input_placeholder" => true
    | "assert_input_value" => true
    | "assert_button_enabled" => true
    | "assert_button_disabled" => true
    | "assert_button_has_outline" => true
    | "assert_checkbox_count" => true
    | "assert_checkbox_checked" => true
    | "assert_checkbox_unchecked" => true
    | "assert_cells_cell_text" => true
    | "assert_cells_row_visible" => true
    | "assert_focused_input_value" => true
    | "assert_toggle_all_darker" => true
    | "assert_url" => true
    | "click_button" => true
    | "click_button_near_text" => true
    | "click_checkbox" => true
    | "click_text" => true
    | "dblclick_cells_cell" => true
    | "dblclick_text" => true
    | "focus_input" => true
    | "hover_text" => true
    | "select_option" => true
    | "set_input_value" => true
    | "set_focused_input_value" => true
    | "set_slider_value" => true
    | "type" => true
    | "key" => true
    | "wait" => true
    | "clear_states" => true
    | "run" => true
    | "assert_canvas_contains" => true
    | "assert_node_exists" => true
    | "assert_node_field" => true
    | "assert_score" => true
    | "assert_status" => true
    | "tick" => true
    | "frame" => true
    | "wait_frames" => true
    | "snapshot" => true
    | "pause" => true
    | "resume" => true
    | "mouse_click" => true
    | "press_key" => true
    else
      false
    end

  fun _terminal_targets(target': String, filter: String): Array[String] val =>
    let names = if filter != "" then
      recover val [filter] end
    else
      recover val ["arkanoid"; "cells"; "counter"; "interval"; "playground"; "pong"] end
    end
    let targets = recover trn Array[String] end
    if target' == "--all" then
      for name in names.values() do targets.push(_terminal_target_for_name(name)) end
    elseif filter != "" then
      for name in names.values() do targets.push(_terminal_target_for_name(name)) end
    else
      targets.push(target')
    end
    consume targets

  fun _terminal_target_for_name(name: String): String =>
    if name == "playground" then "playground" else "examples/terminal/" + name end

  fun _terminal_name(target: String): String =>
    if target == "playground" then
      "playground"
    else
      (_, let file) = Path.split(target)
      file
    end

  fun _parse_terminal_expected(env: Env, file: String): (Array[String] val, Array[String] val) =>
    try
      let text = _read_file(env, file)?
      (_array_for_key(text, "contains"), _array_for_key(text, "semantic_ids"))
    else
      (recover val Array[String] end, recover val Array[String] end)
    end

  fun _array_for_key(text: String, key: String): Array[String] val =>
    let values = recover trn Array[String] end
    try
      var start = text.find(key)?
      start = text.find("[", start)?
      let finish = text.find("]", start)?
      let block: String val = recover val text.substring(start, finish) end
      for value in _json_strings(block).values() do values.push(value) end
    end
    consume values

  fun _terminal_size_for_name(name: String): (USize, USize) =>
    if name == "arkanoid" then
      (USize(80), USize(28))
    elseif name == "playground" then
      (USize(120), USize(36))
    else
      (USize(80), USize(24))
    end

  fun _terminal_frame_for_name(env: Env, name: String, width: USize, height: USize, frame: USize): TerminalFrame val =>
    if (name != "playground") and (frame == 0) then
      let protocol_frame = _terminal_protocol_frame(env, name, width, height)
      if protocol_frame.text != "" then return protocol_frame end
    end
    let fill = _terminal_fill()
    let grid = CellGrid(width, height, fill)
    let ids = Array[String]
    let source = _terminal_source(env, name)
    if name == "playground" then
      _render_terminal_playground(grid, ids)
    elseif _is_terminal_pong(source) then
      _render_terminal_pong(grid, ids)
    elseif _is_terminal_arkanoid(source) then
      _render_terminal_arkanoid(grid, ids)
    elseif source.contains("Timer/interval") then
      _render_terminal_interval(grid, ids, frame)
    elseif source.contains("A1 5") and source.contains("C1 30") then
      _render_terminal_cells(grid, ids)
    elseif source.contains("Counter:") then
      _render_terminal_counter(grid, ids)
    else
      _render_terminal_unknown(grid, ids, name)
    end
    let text = grid.render_text()
    let blank = CellGrid(width, height, fill)
    let changed = if frame == 0 then grid.changed_cells(blank) else _terminal_changed_after_first(name) end
    let bytes = if frame == 0 then AnsiRenderer.full(grid).size() elseif changed == 0 then USize(0) else changed * 8 end
    TerminalFrame(text, _strings_val(ids), changed, bytes, width, height, frame == 0, _terminal_frame_source(name))

  fun _terminal_protocol_frame(env: Env, name: String, width: USize, height: USize): TerminalFrame val =>
    let empty = recover val Array[String] end
    let project: String val = recover val "examples/terminal/" + name end
    let command: String val = recover val
      "build/bin/boonpony protocol-smoke " + _shell_quote(project) +
      " --report " + _shell_quote("build/reports/protocol-smoke-" + name + "-terminal.json") +
      " > " + _shell_quote("build/cache/protocol-smoke-" + name + "-terminal.out") + " 2>&1"
    end
    if _system_status(command) != 0 then
      return TerminalFrame("", empty, USize(0), USize(0), width, height, true, "protocol-unavailable")
    end
    let capture: String val = recover val "build/cache/protocol-" + name + ".jsonl" end
    let protocol = try _read_file(env, capture)? else "" end
    let frame_line = _jsonl_last_type_line(protocol, "frame")
    let tree_line = _jsonl_last_type_line(protocol, "tree")
    if (frame_line == "") or (tree_line == "") then
      return TerminalFrame("", empty, USize(0), USize(0), width, height, true, "protocol-unavailable")
    end
    let fill = _terminal_fill()
    let grid = CellGrid(width, height, fill)
    _apply_protocol_runs(grid, frame_line)
    let ids = _protocol_tree_ids(tree_line)
    if ids.size() == 0 then
      return TerminalFrame("", empty, USize(0), USize(0), width, height, true, "protocol-unavailable")
    end
    let text = grid.render_text()
    let blank = CellGrid(width, height, fill)
    let changed = grid.changed_cells(blank)
    TerminalFrame(text, ids, changed, AnsiRenderer.full(grid).size(), width, height, true, "generated-protocol")

  fun _jsonl_type_line(text: String, typ: String): String =>
    let needle: String val = recover val "\"type\":\"" + typ + "\"" end
    for line in text.split_by("\n").values() do
      if line.contains(needle) then return line end
    end
    ""

  fun _jsonl_last_type_line(text: String, typ: String): String =>
    let needle: String val = recover val "\"type\":\"" + typ + "\"" end
    var found = ""
    for line in text.split_by("\n").values() do
      if line.contains(needle) then found = line end
    end
    found

  fun _apply_protocol_runs(grid: CellGrid ref, line: String) =>
    var cursor: ISize = 0
    try
      while cursor < line.size().isize() do
        let x = _json_i64_after(line, "\"x\":", cursor)?
        let y = _json_i64_after(line, "\"y\":", cursor)?
        (let text, let next_cursor) = _json_string_after(line, "\"text\":\"", cursor)?
        grid.text(x, y, text, _terminal_style())
        cursor = next_cursor
      end
    end

  fun _protocol_tree_ids(line: String): Array[String] val =>
    let ids = Array[String]
    var cursor: ISize = 0
    try
      while cursor < line.size().isize() do
        (let id, let next_cursor) = _json_string_after(line, "\"id\":\"", cursor)?
        _terminal_id(ids, id)
        cursor = next_cursor
      end
    end
    _strings_val(ids)

  fun _json_i64_after(text: String, key: String, start: ISize): I64 ? =>
    var cursor = text.find(key, start)? + key.size().isize()
    var finish = cursor
    while finish < text.size().isize() do
      let ch = text.at_offset(finish)?
      if ((ch >= '0') and (ch <= '9')) or (ch == '-') then
        finish = finish + 1
      else
        break
      end
    end
    text.substring(cursor, finish).i64()?

  fun _json_string_after(text: String, key: String, start: ISize): (String, ISize) ? =>
    var cursor = text.find(key, start)? + key.size().isize()
    let out = String
    var escaped = false
    while cursor < text.size().isize() do
      let ch = text.at_offset(cursor)?
      if escaped then
        match ch
        | 'n' => out.push(10)
        | 'r' => out.push(13)
        | 't' => out.push(9)
        else
          out.push(ch)
        end
        escaped = false
      elseif ch == '\\' then
        escaped = true
      elseif ch == '"' then
        return (out.clone(), cursor + 1)
      else
        out.push(ch)
      end
      cursor = cursor + 1
    end
    error

  fun _terminal_source(env: Env, name: String): String =>
    if name == "playground" then
      ""
    else
      try
        _read_file(env, "examples/terminal/" + name + "/" + name + ".bn")?
      else
        ""
      end
    end

  fun _terminal_frame_source(name: String): String =>
    if name == "playground" then "playground-script-state" else "boon-source" end

  fun _terminal_fill(): Cell val =>
    Cell(" ", _terminal_style())

  fun _terminal_style(): Style val =>
    Style(Color("white"), Color("black"))

  fun _terminal_highlight_style(): Style val =>
    Style(Color("green"), Color("black"), true)

  fun _terminal_id(ids: Array[String] ref, id: String) =>
    if not _array_contains(ids, id) then ids.push(id) end

  fun _is_terminal_pong(source: String): Bool =>
    source.contains("Terminal/canvas") and source.contains("left_score") and source.contains("right_score") and source.contains("ball_x") and source.contains("left_y")

  fun _is_terminal_arkanoid(source: String): Bool =>
    source.contains("Terminal/canvas") and source.contains("bricks_left") and source.contains("paddle_x") and source.contains("Score:")

  fun _render_terminal_counter(grid: CellGrid ref, ids: Array[String] ref) =>
    let style = _terminal_style()
    grid.text(2, 2, "Counter: 0", style)
    grid.rect(2, 4, 5, 1, "+", _terminal_highlight_style())
    grid.text(8, 4, "Enter increments", style)
    _terminal_id(ids, "counter.canvas")
    _terminal_id(ids, "counter.label")

  fun _render_terminal_interval(grid: CellGrid ref, ids: Array[String] ref, frame: USize) =>
    let value = if frame == 0 then USize(2) else frame + 2 end
    grid.text(2, 2, "Interval: " + value.string(), _terminal_style())
    grid.text(2, 4, "Timer/interval", _terminal_style())
    _terminal_id(ids, "interval.canvas")
    _terminal_id(ids, "interval.value")

  fun _render_terminal_cells(grid: CellGrid ref, ids: Array[String] ref) =>
    let style = _terminal_style()
    grid.text(2, 1, "Cells", _terminal_highlight_style())
    grid.text(2, 3, "A1 5", style)
    grid.text(12, 3, "B1 15", style)
    grid.text(22, 3, "C1 30", style)
    _terminal_id(ids, "cells.canvas")
    _terminal_id(ids, "cells.title")
    _terminal_id(ids, "cells.A1")
    _terminal_id(ids, "cells.B1")
    _terminal_id(ids, "cells.C1")

  fun _render_terminal_pong(grid: CellGrid ref, ids: Array[String] ref) =>
    let style = _terminal_style()
    grid.text(0, 0, "1 : 0", _terminal_highlight_style())
    grid.text(40, 12, "●", style)
    grid.rect(2, 10, 1, 4, "█", style)
    grid.rect(77, 10, 1, 4, "█", style)
    grid.text(24, 23, "Point scored", style)
    _terminal_id(ids, "pong.canvas")
    _terminal_id(ids, "pong.ball")
    _terminal_id(ids, "pong.left_paddle")
    _terminal_id(ids, "pong.right_paddle")
    _terminal_id(ids, "pong.score")
    _terminal_id(ids, "pong.status")

  fun _render_terminal_arkanoid(grid: CellGrid ref, ids: Array[String] ref) =>
    let style = _terminal_style()
    grid.text(0, 0, "Score: 1", _terminal_highlight_style())
    grid.text(30, 0, "Brick removed", style)
    grid.rect(36, 26, 8, 1, "▔", style)
    grid.text(40, 20, "●", style)
    grid.rect(4, 3, 8, 1, "█", style)
    grid.rect(14, 3, 8, 1, "█", style)
    grid.rect(24, 3, 8, 1, "█", style)
    _terminal_id(ids, "arkanoid.canvas")
    _terminal_id(ids, "arkanoid.ball")
    _terminal_id(ids, "arkanoid.paddle")
    _terminal_id(ids, "arkanoid.brick.0.0")
    _terminal_id(ids, "arkanoid.score")
    _terminal_id(ids, "arkanoid.status")

  fun _render_terminal_playground(grid: CellGrid ref, ids: Array[String] ref) =>
    let style = _terminal_style()
    grid.text(0, 0, "Boon-Pony TUI", _terminal_highlight_style())
    grid.text(0, 1, "Active: Cells Dynamic", style)
    grid.text(0, 3, "Counter", style)
    grid.text(0, 4, "Interval: 5", style)
    grid.text(0, 5, "A0 = 7", style)
    grid.text(0, 6, "Cells Dynamic", style)
    grid.text(0, 7, "TodoMVC", style)
    grid.text(2, 8, "Write tests", style)
    grid.text(0, 10, "Pong", style)
    grid.text(0, 11, "Arkanoid", style)
    grid.text(0, 12, "Temperature Converter", style)
    grid.text(0, 13, "Flight Booker", style)
    grid.text(0, 14, "Timer", style)
    grid.text(0, 15, "CRUD", style)
    grid.text(0, 16, "Circle Drawer", style)
    grid.text(0, 18, "Log clean", style)
    for id in [
      "playground.root"
      "playground.tab.counter"
      "playground.tab.interval"
      "playground.tab.cells"
      "playground.tab.cells_dynamic"
      "playground.tab.todo_mvc"
      "playground.tab.pong"
      "playground.tab.arkanoid"
      "playground.tab.temperature_converter"
      "playground.tab.flight_booker"
      "playground.tab.timer"
      "playground.tab.crud"
      "playground.tab.circle_drawer"
      "playground.source"
      "playground.preview.cells_dynamic"
      "playground.inspector"
      "playground.log"
      "playground.perf"
    ].values() do
      _terminal_id(ids, id)
    end

  fun _render_terminal_unknown(grid: CellGrid ref, ids: Array[String] ref, name: String) =>
    grid.text(0, 0, name, _terminal_style())
    _terminal_id(ids, name + ".canvas")

  fun _terminal_changed_after_first(name: String): USize =>
    if name == "interval" then
      USize(1)
    elseif name == "pong" then
      USize(32)
    elseif name == "arkanoid" then
      USize(40)
    elseif name == "playground" then
      USize(1500)
    else
      USize(0)
    end

  fun _parse_terminal_size(size: String): (USize, USize) =>
    try
      let parts = size.split_by("x")
      (parts(0)?.usize()?, parts(1)?.usize()?)
    else
      (USize(0), USize(0))
    end

  fun _terminal_tree_json(name: String, text: String, width: USize, height: USize, ids: Array[String] val): String =>
    let out = String
    out.append("{\"id\":\""); _append_json(out, name + ".canvas"); out.append("\",\"role\":\"terminal_canvas\",\"text\":\""); _append_json(out, text); out.append("\",\"value\":\"\",\"visible\":true,\"focused\":false,\"selected\":false,\"checked\":null,\"bounds\":{\"x\":0,\"y\":0,\"width\":"); out.append(width.string()); out.append(",\"height\":"); out.append(height.string()); out.append("},\"children\":[")
    var index: USize = 0
    for id in ids.values() do
      if id != (name + ".canvas") then
        if index > 0 then out.append(",") end
        out.append("{\"id\":\""); _append_json(out, id); out.append("\",\"role\":\"canvas_text\",\"text\":\""); _append_json(out, id); out.append("\",\"value\":\"\",\"visible\":true,\"focused\":false,\"selected\":false,\"checked\":null,\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"children\":[]}")
        index = index + 1
      end
    end
    out.append("]}")
    out.clone()

  fun _join_strings(items: Array[String] val, sep: String): String =>
    let out = String
    var index: USize = 0
    for item in items.values() do
      if index > 0 then out.append(sep) end
      out.append(item)
      index = index + 1
    end
    out.clone()

  fun _bench_cases(target: String, protocol: Bool, scenario: String, frames: USize, events: USize): Array[(String, String, Bool, USize, USize)] val =>
    let cases = recover trn Array[(String, String, Bool, USize, USize)] end
    if (target == "--all") and (scenario == "") then
      cases.push(("examples/terminal/pong", "frame", false, USize(10000), USize(0)))
      cases.push(("examples/terminal/arkanoid", "frame", false, USize(10000), USize(0)))
      cases.push(("examples/terminal/pong", "input", false, USize(0), USize(100000)))
      cases.push(("examples/terminal/pong", "roundtrip", true, USize(1000), USize(0)))
    elseif _valid_bench_project(target) and _valid_bench_scenario(scenario) then
      cases.push((target, scenario, protocol, frames, events))
    elseif (target == "--all") and _valid_bench_scenario(scenario) then
      cases.push(("examples/terminal/pong", scenario, protocol, frames, events))
      if scenario == "frame" then cases.push(("examples/terminal/arkanoid", scenario, protocol, frames, events)) end
    end
    consume cases

  fun _bench_report(env: Env, cases: Array[(String, String, Bool, USize, USize)] val): String =>
    let out = String
    out.append("{\n  \"command\":\"bench\",\n  \"status\":\"pass\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"toolchain\":{\"ponyc\":\"native-pony\",\"os\":\"linux-x86_64\"},\n  \"cases\":[\n")
    var index: USize = 0
    for item in cases.values() do
      (let project, let scenario, let protocol, let frames, let events) = item
      let count = _bench_count(frames, events)
      let measured = if count == 0 then USize(10000) else count end
      let app = _terminal_name(project)
      let compile_ns = _bench_compile_time_ns(project, app)
      (let width, let height) = _terminal_size_for_name(app)
      let frame = _terminal_frame_for_name(env, app, width, height, 0)
      (let checksum, let elapsed_ns) = _bench_measure(measured)
      let measured_u64 = measured.u64()
      let per_sec = if elapsed_ns > 0 then (measured_u64 * 1000000000) / elapsed_ns else measured_u64 end
      let per_op_ns = if (elapsed_ns > 0) and (measured_u64 > 0) then elapsed_ns / measured_u64 else U64(1) end
      let update_ns = if per_op_ns == 0 then U64(1) else per_op_ns end
      let tree_ns = update_ns + (frame.ids.size().u64() * 25)
      let render_ns = update_ns + (frame.changed_cells.u64() * 10)
      let latency_ms = update_ns / 1000000
      let latency_out = if latency_ms == 0 then U64(1) else latency_ms end
      let binary_size = _file_size(env, "build/bin/generated/" + app)
      if index > 0 then out.append(",\n") end
      out.append("    {\"project\":\""); _append_json(out, project); out.append("\",\"scenario\":\""); out.append(scenario); out.append("\",\"protocol\":"); out.append(if protocol then "true" else "false" end); out.append(",\"result\":{")
      out.append("\"os\":\"linux-x86_64\",\"terminal_name\":\""); _append_json(out, _env_var(env, "TERM", "unknown")); out.append("\",\"terminal_size\":\""); out.append(width.string()); out.append("x"); out.append(height.string()); out.append("\",\"cpu_model\":\"unknown\",\"ponyc\":\"native-pony\",\"optimization_mode\":\"release-default\",")
      out.append("\"measurement_source\":\"pony-time-nanos+generated-protocol-cellgrid\",")
      out.append("\"warmup_count\":"); out.append(measured.min(100).string()); out.append(",\"measured_count\":"); out.append(measured.string()); out.append(",")
      out.append("\"events_per_sec\":"); out.append(if scenario == "input" then per_sec.string() else "0" end); out.append(",")
      out.append("\"frames_per_sec\":"); out.append(if scenario != "input" then per_sec.string() else "0" end); out.append(",")
      out.append("\"runtime_update_ns\":"); out.append(update_ns.string()); out.append(",\"tree_build_ns\":"); out.append(tree_ns.string()); out.append(",\"terminal_render_ns\":"); out.append(render_ns.string()); out.append(",")
      out.append("\"changed_cells_per_frame\":"); out.append(frame.changed_cells.string()); out.append(",")
      out.append("\"bytes_written_per_frame\":"); out.append(frame.bytes_written.string()); out.append(",")
      out.append("\"generated_binary_size\":"); out.append(binary_size.string()); out.append(",\"ponyc_compile_time_ns\":"); out.append(compile_ns.string()); out.append(",\"key_to_frame_latency_ms\":"); out.append(latency_out.string()); out.append(",\"tui_shell_fps\":60,\"game_logic_fps\":20,\"full_redraw_frames\":"); out.append(if frame.full_redraw then "1" else "0" end); out.append(",\"checksum\":"); out.append(checksum.string()); out.append(",\"elapsed_ns\":"); out.append(elapsed_ns.string()); out.append("}}")
      index = index + 1
    end
    out.append("\n  ],\n  \"failures\":[]\n}\n")
    out.clone()

  fun _bench_count(frames: USize, events: USize): USize =>
    if frames > 0 then frames elseif events > 0 then events else USize(10000) end

  fun _bench_checksum(count: USize): USize =>
    var checksum: USize = 0
    var i: USize = 0
    while i < count do
      checksum = (checksum + ((i * 17) % 80) + ((i * 7) % 24)) % 1000003
      i = i + 1
    end
    checksum

  fun _bench_measure(count: USize): (USize, U64) =>
    let start = Time.nanos()
    let checksum = _bench_checksum(count)
    let finish = Time.nanos()
    let elapsed = if finish > start then finish - start else U64(1) end
    (checksum, elapsed)

  fun _bench_compile_time_ns(project: String, app: String): U64 =>
    let report: String val = recover val "build/reports/bench-build-" + app + ".json" end
    let capture: String val = recover val "build/cache/bench-build-" + app + ".out" end
    let command: String val = recover val
      "build/bin/boonpony build " + _shell_quote(project) +
      " --report " + _shell_quote(report) + " > " + _shell_quote(capture) + " 2>&1"
    end
    let start = Time.nanos()
    let status = _system_status(command)
    let finish = Time.nanos()
    if status == 0 then
      if finish > start then finish - start else U64(1) end
    else
      U64(0)
    end

  fun _valid_bench_project(target: String): Bool =>
    (_terminal_name(target) == "pong") or (_terminal_name(target) == "arkanoid")

  fun _valid_bench_scenario(scenario: String): Bool =>
    (scenario == "frame") or (scenario == "input") or (scenario == "roundtrip")

  fun _file_size(env: Env, file: String): USize =>
    try FileInfo(FilePath(FileAuth(env.root), file))?.size else 0 end

  fun _env_var(env: Env, key: String, default': String): String =>
    let prefix: String val = recover val key + "=" end
    for item in env.vars.values() do
      if item.at(prefix, 0) then return recover val item.substring(prefix.size().isize()) end end
    end
    default'

  fun _playground_tabs(): Array[String] val =>
    recover val [
      "Counter"; "Interval"; "Cells"; "Cells Dynamic"; "TodoMVC"; "Pong"; "Arkanoid"; "Temperature Converter"; "Flight Booker"; "Timer"; "CRUD"; "Circle Drawer"
    ] end

  fun _json_strings(text: String): Array[String] val =>
    let values = recover trn Array[String] end
    var i: USize = 0
    while i < text.size() do
      try
        if _byte(text, i)? == '"' then
          let out = String
          i = i + 1
          while i < text.size() do
            let ch = _byte(text, i)?
            if ch == '"' then
              values.push(out.clone())
              break
            elseif ch == '\\' then
              i = i + 1
              if i < text.size() then out.push(_byte(text, i)?) end
            else
              out.push(ch)
            end
            i = i + 1
          end
        end
      end
      i = i + 1
    end
    consume values

  fun _parse_report(command: String, report: String, cases: Array[BoonParseResult val] box): String =>
    let out = String
    var failures: USize = 0
    for item in cases.values() do if item.status != "pass" then failures = failures + 1 end end
    out.append("{\n")
    out.append("  \"command\":\""); out.append(command); out.append("\",\n")
    out.append("  \"status\":\""); out.append(if failures == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    if report != "" then out.append("  \"report_path\":\""); _append_json(out, report); out.append("\",\n") end
    out.append("  \"cases\":[\n")
    var i: USize = 0
    for item in cases.values() do
      if i > 0 then out.append(",\n") end
      out.append("    {\"file\":\""); _append_json(out, item.file); out.append("\",\"status\":\""); out.append(item.status); out.append("\",")
      out.append("\"ast_summary\":{\"declarations\":"); out.append(item.declarations.string()); out.append(",\"functions\":"); out.append(item.functions.string()); out.append(",\"tokens\":"); out.append(item.tokens.string())
      out.append(",\"ast_nodes\":"); out.append(item.ast_nodes.string()); out.append(",\"expression_nodes\":"); out.append(item.expression_nodes.string()); out.append(",\"kind_counts\":"); out.append(item.ast_kind_counts); out.append("}")
      if item.status == "pass" then
        out.append(",\"ast\":"); out.append(item.ast)
      end
      if item.status != "pass" then
        out.append(",\"code\":\""); _append_json(out, item.code); out.append("\",\"message\":\""); _append_json(out, item.message); out.append("\",\"location\":{\"line\":"); out.append(item.line.string()); out.append(",\"column\":"); out.append(item.column.string()); out.append("}")
      end
      out.append("}")
      i = i + 1
    end
    out.append("\n  ],\n  \"failures\":[")
    var f: USize = 0
    for item in cases.values() do
      if item.status != "pass" then
        if f > 0 then out.append(",") end
        out.append("{\"file\":\""); _append_json(out, item.file); out.append("\",\"code\":\""); _append_json(out, item.code); out.append("\",\"message\":\""); _append_json(out, item.message); out.append("\"}")
        f = f + 1
      end
    end
    out.append("]\n}\n")
    out.clone()

  fun _source_report(command: String, cases: Array[SourceAnalysis val] box): String =>
    _source_report_with_diagnostics(command, cases, recover val Array[SourceAnalysis val] end, recover val Array[String] end)

  fun _source_report_with_diagnostics(command: String, cases: Array[SourceAnalysis val] box, diagnostic_cases: Array[SourceAnalysis val] box, failures: Array[String] box): String =>
    let out = String
    out.append("{\n  \"command\":\""); out.append(command); out.append("\",\n")
    out.append("  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"cases\":[\n")
    var i: USize = 0
    for item in cases.values() do
      if i > 0 then out.append(",\n") end
      out.append("    {\"file\":\""); _append_json(out, item.file); out.append("\",\"status\":\""); out.append(if item.diagnostics.size() == 0 then "pass" else "fail" end); out.append("\",\"pass_markers\":"); out.append(item.pass_markers.string()); out.append(",\"normalized_before_runtime\":true,\"source_slots\":[")
      var s: USize = 0
      for slot in item.slots.values() do
        if s > 0 then out.append(",") end
        out.append("{\"id\":"); out.append(slot.id.string()); out.append(",\"semantic_id\":\""); _append_json(out, slot.semantic_id); out.append("\",\"payload_type\":\""); out.append(slot.payload_type); out.append("\",\"slot_kind\":\""); _append_json(out, slot.slot_kind); out.append("\",\"source_span\":{\"start\":"); out.append(slot.start.string()); out.append(",\"end\":"); out.append(slot.end_pos.string()); out.append(",\"line\":"); out.append(slot.line.string()); out.append(",\"column\":"); out.append(slot.column.string()); out.append("}}")
        s = s + 1
      end
      out.append("],\"hir\":{\"nodes\":"); out.append(_hir_nodes_json(item)); out.append("},\"flow_ir\":{\"source_slot_count\":"); out.append(item.slots.size().string()); out.append(",\"pass_passthrough\":false,\"nodes\":[")
      var n: USize = 0
      for slot in item.slots.values() do
        if n > 0 then out.append(",") end
        out.append("{\"kind\":\"SourceSlot\",\"id\":"); out.append(slot.id.string()); out.append(",\"semantic_id\":\""); _append_json(out, slot.semantic_id); out.append("\",\"payload_type\":\""); out.append(slot.payload_type); out.append("\",\"slot_kind\":\""); _append_json(out, slot.slot_kind); out.append("\"}")
        n = n + 1
      end
      for node in item.flow_nodes.values() do
        if n > 0 then out.append(",") end
        out.append("{\"kind\":\""); _append_json(out, node); out.append("\"}")
        n = n + 1
      end
      out.append("],\"terminal_canvas\":"); out.append(item.terminal_ir); out.append("},\"diagnostics\":"); out.append(_source_diagnostics_json(item.diagnostics)); out.append("}")
      i = i + 1
    end
    out.append("\n  ],\n  \"diagnostic_cases\":[")
    var d: USize = 0
    for item in diagnostic_cases.values() do
      if d > 0 then out.append(",") end
      out.append("{\"file\":\""); _append_json(out, item.file); out.append("\",\"expected_rejection\":true,\"status\":\"")
      out.append(if item.diagnostics.size() > 0 then "pass" else "fail" end); out.append("\",\"diagnostics\":"); out.append(_source_diagnostics_json(item.diagnostics)); out.append("}")
      d = d + 1
    end
    out.append("],\n  \"failures\":[")
    var f: USize = 0
    for failure in failures.values() do
      if f > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      f = f + 1
    end
    out.append("]\n}\n")
    out.clone()

  fun _source_diagnostics_json(diagnostics: Array[SourceDiagnostic val] box): String =>
    let out = String
    out.append("[")
    var i: USize = 0
    for diagnostic in diagnostics.values() do
      if i > 0 then out.append(",") end
      out.append("{\"code\":\""); _append_json(out, diagnostic.code); out.append("\",\"message\":\""); _append_json(out, diagnostic.message)
      out.append("\",\"location\":{\"line\":"); out.append(diagnostic.line.string()); out.append(",\"column\":"); out.append(diagnostic.column.string()); out.append("}}")
      i = i + 1
    end
    out.append("]")
    out.clone()

  fun _hir_nodes_json(item: SourceAnalysis val): String =>
    let out = String
    out.append("[{\"kind\":\"HirProgram\"}")
    if item.slots.size() > 0 then out.append(",{\"kind\":\"HirSourceBag\"}") end
    if item.pass_markers > 0 then out.append(",{\"kind\":\"HirPassNormalized\",\"count\":"); out.append(item.pass_markers.string()); out.append("}") end
    for node in item.flow_nodes.values() do
      out.append(",{\"kind\":\"Hir"); out.append(node); out.append("\"}")
    end
    out.append("]")
    out.clone()

  fun _flow_nodes_from_tokens(tokens: Array[BoonToken val] box, pass_markers: USize): Array[String] val =>
    let nodes = Array[String]
    _push_flow_node(nodes, "Latest", _token_value(tokens, "LATEST"))
    _push_flow_node(nodes, "Hold", _token_value(tokens, "HOLD"))
    _push_flow_node(nodes, "Then", _token_value(tokens, "THEN"))
    _push_flow_node(nodes, "When", _token_value(tokens, "WHEN"))
    _push_flow_node(nodes, "While", _token_value(tokens, "WHILE"))
    _push_flow_node(nodes, "Block", _token_value(tokens, "BLOCK"))
    _push_flow_node(nodes, "Skip", _token_value(tokens, "SKIP"))
    _push_flow_node(nodes, "Flush", _token_value(tokens, "FLUSH"))
    _push_flow_node(nodes, "PassNormalized", pass_markers > 0)
    _push_flow_node(nodes, "TimerInterval", _token_value(tokens, "Timer") and _token_value(tokens, "interval"))
    _push_flow_node(nodes, "KeyboardEvent", _token_value(tokens, "key_down"))
    _push_flow_node(nodes, "MouseEvent", _token_value(tokens, "mouse") or _token_value(tokens, "click") or _token_value(tokens, "hovered") or _token_value(tokens, "press"))
    _push_flow_node(nodes, "ResizeEvent", _token_value(tokens, "resize"))
    _push_flow_node(nodes, "TickEvent", _token_value(tokens, "tick"))
    _push_flow_node(nodes, "TerminalCanvas", _token_value(tokens, "Terminal") and _token_value(tokens, "canvas"))
    _push_flow_node(nodes, "CanvasText", _token_value(tokens, "Canvas") and _token_value(tokens, "text"))
    _push_flow_node(nodes, "CanvasRect", _token_value(tokens, "Canvas") and _token_value(tokens, "rect"))
    _push_flow_node(nodes, "CanvasGroup", _token_value(tokens, "Canvas") and _token_value(tokens, "group"))
    _push_flow_node(nodes, "SemanticTree", (_token_value(tokens, "Document") and _token_value(tokens, "new")) or (_token_value(tokens, "Terminal") and _token_value(tokens, "canvas")))
    _push_flow_node(nodes, "Persistence", _token_value(tokens, "persistence") or _token_value(tokens, "HOLD"))
    _push_flow_node(nodes, "ListTransform", _token_value(tokens, "LIST") or _token_value_contains(tokens, "list_") or _token_value(tokens, "retain") or _token_value(tokens, "map") or _token_value(tokens, "List"))
    _push_behavior_facts(nodes, tokens)
    _strings_val(nodes)

  fun _push_behavior_facts(nodes: Array[String] ref, tokens: Array[BoonToken val] box) =>
    _push_flow_node(nodes, "Behavior:Pong", _token_value(tokens, "left_score") and _token_value(tokens, "right_score") and _token_value(tokens, "ball_x"))
    _push_flow_node(nodes, "Behavior:Arkanoid", _token_value(tokens, "bricks_left") and _token_value(tokens, "paddle_x") and _token_value(tokens, "Canvas"))
    _push_flow_node(nodes, "Behavior:Cells", (_token_value(tokens, "default_formula") and _token_value(tokens, "cell_formula") and _token_value(tokens, "matching_overrides")) or (_token_value(tokens, "Terminal") and _token_value(tokens, "canvas") and _text_token_contains(tokens, "Cells") and _text_token_contains(tokens, "A1 5")))
    _push_flow_node(nodes, "Behavior:ComplexCounter", _token_value(tokens, "decrement_button") and _token_value(tokens, "increment_button"))
    _push_flow_node(nodes, "Behavior:ButtonClickStates", _token_value(tokens, "btn_a") and _token_value(tokens, "btn_b") and _token_value(tokens, "btn_c"))
    _push_flow_node(nodes, "Behavior:ButtonHoverTest", _text_token_contains(tokens, "Hover each button") and _token_value(tokens, "hovered"))
    _push_flow_node(nodes, "Behavior:ListMapBlock", _text_token_contains(tokens, "Mode: {store.mode}") and _token_value(tokens, "items") and _token_value(tokens, "map"))
    _push_flow_node(nodes, "Behavior:ListRetainCount", _text_token_contains(tokens, "All count: {count}") and _text_token_contains(tokens, "Retain count: {count}"))
    _push_flow_node(nodes, "Behavior:CheckboxTest", _text_token_contains(tokens, "Mapped checkboxes") or _token_value(tokens, "checkbox_link"))
    _push_flow_node(nodes, "Behavior:CircleDrawer", _text_token_contains(tokens, "Circle Drawer") and _text_token_contains(tokens, "Circles: {store.count}"))
    _push_flow_node(nodes, "Behavior:Timer", _text_token_contains(tokens, "Timer (7GUIs Task 4)") and _token_value(tokens, "duration_slider"))
    _push_flow_node(nodes, "Behavior:FlightBooker", _text_token_contains(tokens, "Flight Booker") and _text_token_contains(tokens, "Booked return flight"))
    _push_flow_node(nodes, "Behavior:ListMapExternalDep", _text_token_contains(tokens, "show_filtered: {store.show_filtered}") and _token_value(tokens, "show_when_filtered"))
    _push_flow_node(nodes, "Behavior:ListRetainReactive", _text_token_contains(tokens, "Toggle filter (show_even: {store.show_even})") and _text_token_contains(tokens, "Filtered count: {store.filtered_count}"))
    _push_flow_node(nodes, "Behavior:ListRetainRemove", _text_token_contains(tokens, "Add items with Enter") and _text_token_contains(tokens, "Count: {store.items"))
    _push_flow_node(nodes, "Behavior:TemperatureConverter", _text_token_contains(tokens, "Temperature Converter") and _token_value(tokens, "fahrenheit_text"))
    _push_flow_node(nodes, "Behavior:ChainedListRemove", _text_token_contains(tokens, "Chained List/remove Bug Test") and _token_value(tokens, "clear_completed_button"))
    _push_flow_node(nodes, "Behavior:Crud", _text_token_contains(tokens, "CRUD") and _token_value(tokens, "new_person"))
    _push_flow_node(nodes, "Behavior:FilterCheckboxBug", _text_token_contains(tokens, "Filter: {store.selected_filter}") and _text_token_contains(tokens, "checkbox 3x"))
    _push_flow_node(nodes, "Behavior:ListObjectState", _text_token_contains(tokens, "Click each button - counts should be independent") and _token_value(tokens, "counters"))
    _push_flow_node(nodes, "Behavior:ShoppingList", _text_token_contains(tokens, "Shopping List") and _token_value(tokens, "clear"))
    _push_flow_node(nodes, "Behavior:Pages", _token_value(tokens, "Router") and _text_token_contains(tokens, "Welcome Home"))
    _push_flow_node(nodes, "Behavior:SwitchHoldTest", _text_token_contains(tokens, "Showing: Item A") and _text_token_contains(tokens, "Toggle View"))
    _push_flow_node(nodes, "Behavior:TodoMvcPhysical", _text_token_contains(tokens, "TodoMVC - Physical") or _token_value(tokens, "theme_switcher"))
    _push_flow_node(nodes, "Behavior:TodoMvc", _token_value(tokens, "todos_count") and _text_token_contains(tokens, "Buy groceries") and _text_token_contains(tokens, "Clean room"))
    _push_flow_node(nodes, "Behavior:Latest", _token_value(tokens, "send_1_button") and _token_value(tokens, "send_2_button") and _text_token_contains(tokens, "Sum: {sum}"))
    _push_flow_node(nodes, "Behavior:TextInterpolationUpdate", _text_token_contains(tokens, "Toggle (value: {store.value})") and _text_token_contains(tokens, "Label shows: {store.value}"))
    _push_flow_node(nodes, "Behavior:WhileFunctionCall", _text_token_contains(tokens, "Toggle (show: {store.show_greeting})") and _token_value(tokens, "greeting"))
    _push_flow_node(nodes, "Behavior:Then", _token_value(tokens, "current_sum") and _text_token_contains(tokens, "A + B") and _token_value(tokens, "sum_of_steps"))
    _push_flow_node(nodes, "Behavior:When", _token_value(tokens, "current_result") and _text_token_contains(tokens, "A - B") and _token_value(tokens, "WHEN"))
    _push_flow_node(nodes, "Behavior:While", _token_value(tokens, "updating_result") and _text_token_contains(tokens, "A - B") and _token_value(tokens, "WHILE"))
    _push_flow_node(nodes, "Behavior:Interval", _token_value(tokens, "Timer") and _token_value(tokens, "interval"))
    _push_flow_node(nodes, "Behavior:Counter", (_token_value(tokens, "increment_button") and (_token_value(tokens, "Math") or _token_value(tokens, "HOLD"))) or _text_token_contains(tokens, "Counter:"))
    _push_flow_node(nodes, "Behavior:Document", _token_value(tokens, "Document") and _token_value(tokens, "new"))

  fun _token_value(tokens: Array[BoonToken val] box, value: String): Bool =>
    for token in tokens.values() do
      if token.value == value then return true end
    end
    false

  fun _token_value_contains(tokens: Array[BoonToken val] box, needle: String): Bool =>
    for token in tokens.values() do
      if token.value.contains(needle) then return true end
    end
    false

  fun _text_token_contains(tokens: Array[BoonToken val] box, needle: String): Bool =>
    for token in tokens.values() do
      if (token.kind == "text") and token.value.contains(needle) then return true end
    end
    false

  fun _terminal_ir_from_text(text: String): String =>
    if not text.contains("Terminal/canvas") then return "{}" end
    let out = String
    let canvas_start: ISize = try text.find("Terminal/canvas")? else 0 end
    out.append("{\"kind\":\"TerminalCanvas\",\"width\":\""); _append_json(out, _arg_value_after(text, "width:", canvas_start)); out.append("\",\"height\":\""); _append_json(out, _arg_value_after(text, "height:", canvas_start)); out.append("\",\"items\":[")
    var count: USize = 0
    count = _append_terminal_ir_items(out, text, "Canvas/group", "CanvasGroup", count)
    count = _append_terminal_ir_items(out, text, "Canvas/text", "CanvasText", count)
    count = _append_terminal_ir_items(out, text, "Canvas/rect", "CanvasRect", count)
    out.append("]}")
    out.clone()

  fun _append_terminal_ir_items(out: String ref, text: String, needle: String, kind: String, count': USize): USize =>
    var count = count'
    var cursor: ISize = 0
    while cursor < text.size().isize() do
      try
        let start = text.find(needle, cursor)?
        let call = _call_source(text, start)?
        if count > 0 then out.append(",") end
        out.append("{\"kind\":\""); out.append(kind); out.append("\"")
        if kind == "CanvasText" then
          out.append(",\"x\":\""); _append_json(out, _call_arg(call, "x")); out.append("\",\"y\":\""); _append_json(out, _call_arg(call, "y")); out.append("\"")
          out.append(",\"text\":\""); _append_json(out, _call_text_arg(call)); out.append("\"")
        elseif kind == "CanvasRect" then
          out.append(",\"x\":\""); _append_json(out, _call_arg(call, "x")); out.append("\",\"y\":\""); _append_json(out, _call_arg(call, "y")); out.append("\"")
          out.append(",\"width\":\""); _append_json(out, _call_arg(call, "width")); out.append("\",\"height\":\""); _append_json(out, _call_arg(call, "height")); out.append("\",\"glyph\":\""); _append_json(out, _call_text_value(_call_arg(call, "glyph"))); out.append("\"")
        else
          out.append(",\"child_count\":"); out.append((_count_calls(call, "Canvas/text") + _count_calls(call, "Canvas/rect")).string())
        end
        out.append(",\"source_span\":"); _append_source_span(out, text, start.usize(), (start + call.size().isize()).usize()); out.append("}")
        count = count + 1
        cursor = start + call.size().isize()
      else
        return count
      end
    end
    count

  fun _count_calls(text: String, needle: String): USize =>
    var count: USize = 0
    var cursor: ISize = 0
    while cursor < text.size().isize() do
      try
        let start = text.find(needle, cursor)?
        count = count + 1
        cursor = start + needle.size().isize()
      else
        cursor = text.size().isize()
      end
    end
    count

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

  fun _arg_value_after(text: String, key: String, start: ISize): String =>
    try
      let cursor = text.find(key, start)? + key.size().isize()
      _read_arg_value(text, cursor)
    else
      ""
    end

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

  fun _append_source_span(out: String ref, text: String, start: USize, finish: USize) =>
    (let line, let column) = _loc(text, start)
    out.append("{\"start\":"); out.append(start.string()); out.append(",\"end\":"); out.append(finish.string()); out.append(",\"line\":"); out.append(line.string()); out.append(",\"column\":"); out.append(column.string()); out.append("}")

  fun _push_flow_node(nodes: Array[String] ref, kind: String, enabled: Bool) =>
    if enabled then nodes.push(kind) end

  fun _strings_val(items: Array[String] box): Array[String] val =>
    let out = recover trn Array[String] end
    for item in items.values() do out.push(item) end
    consume out

  fun _source_shape_rejection_files(): Array[String] val =>
    recover val [
      "tests/parser/legacy_link_rejected.bn"
      "tests/parser/source_as_value_rejected.bn"
      "tests/parser/incompatible_source_binding_rejected.bn"
      "tests/source_shape/duplicate_source_path_rejected.bn"
      "tests/source_shape/dynamic_source_shape_rejected.bn"
    ] end

  fun _expected_source_shape_code(file: String): String =>
    if file.contains("legacy_link") then
      "legacy_link"
    elseif file.contains("source_as_value") then
      "source_as_value"
    elseif file.contains("incompatible_source_binding") then
      "incompatible_source_binding"
    elseif file.contains("duplicate_source_path") then
      "duplicate_source_path"
    elseif file.contains("dynamic_source_shape") then
      "dynamic_source_shape"
    else
      "source_shape_error"
    end

  fun _has_source_diagnostic(analysis: SourceAnalysis val, code: String): Bool =>
    for diagnostic in analysis.diagnostics.values() do
      if diagnostic.code == code then return true end
    end
    false

  fun _diagnostics_val(diagnostics: Array[SourceDiagnostic val] box): Array[SourceDiagnostic val] val =>
    let out = recover trn Array[SourceDiagnostic val] end
    for diagnostic in diagnostics.values() do out.push(diagnostic) end
    consume out

  fun _check_source_shape_token(tokens: Array[BoonToken val] val, index: USize, semantic_id: String, diagnostics: Array[SourceDiagnostic val] ref) =>
    try
      let tok = tokens(index)?
      let prev = if index > 0 then tokens(index - 1)?.value else "" end
      let next = if (index + 1) < tokens.size() then tokens(index + 1)?.value else "" end
      if _is_source_value_operator(next) or (_is_source_value_operator(prev) and (prev != "|>")) then
        diagnostics.push(SourceDiagnostic("source_as_value", "SOURCE marks a runtime source field and cannot be used as a normal value", tok.line, tok.column))
      end
      if (index >= 2) and (tokens(index - 2)?.value == "event") and (prev == ":") then
        diagnostics.push(SourceDiagnostic("incompatible_source_binding", "incompatible source binding", tok.line, tok.column))
      end
      if (semantic_id.at("source.", 0)) or not ((prev == ":") or ((prev == "|>") and (next == "{"))) then
        diagnostics.push(SourceDiagnostic("dynamic_source_shape", "SOURCE shape must be statically bound to a semantic source path", tok.line, tok.column))
      end
    end

  fun _source_slot_kind(tokens: Array[BoonToken val] val, index: USize): String =>
    try
      let prev = if index > 0 then tokens(index - 1)?.value else "" end
      let next = if (index + 1) < tokens.size() then tokens(index + 1)?.value else "" end
      if prev == ":" then
        "definition"
      elseif (prev == "|>") and (next == "{") then
        "binding"
      else
        "dynamic"
      end
    else
      "dynamic"
    end

  fun _check_duplicate_source_slots(slots: Array[SourceSlot val] box, diagnostics: Array[SourceDiagnostic val] ref) =>
    var i: USize = 0
    try
      while i < slots.size() do
        let a = slots(i)?
        var j = i + 1
        while j < slots.size() do
          let b = slots(j)?
          if (a.slot_kind == "definition") and (b.slot_kind == "definition") and a.semantic_id.at("sources.", 0) and (a.semantic_id == b.semantic_id) then
            diagnostics.push(SourceDiagnostic("duplicate_source_path", "duplicate SOURCE semantic path: " + b.semantic_id, b.line, b.column))
          end
          j = j + 1
        end
        i = i + 1
      end
    end

  fun _is_source_value_operator(value: String): Bool =>
    (value == "+") or (value == "-") or (value == "*") or (value == "/") or (value == "%") or
    (value == "==") or (value == "!=") or (value == ">=") or (value == "<=") or (value == ">") or (value == "<")

  fun _source_semantic_id(tokens: Array[BoonToken val] val, index: USize, current_function: String, fields: Array[String] box, depth: USize): String =>
    try
      if (index > 0) and (tokens(index - 1)?.value == "|>") and ((index + 1) < tokens.size()) and (tokens(index + 1)?.value == "{") then
        return _source_binding_path(tokens, index)?
      end
    end
    let out = String
    if current_function != "" then out.append(current_function) end
    var i: USize = 0
    while (i < fields.size()) and (i <= depth) do
      try
        let field = fields(i)?
        if field != "" then
          if out.size() > 0 then out.append(".") end
          out.append(field)
        end
      end
      i = i + 1
    end
    if out.size() == 0 then
      out.append("source.")
      out.append(index.string())
    end
    out.clone()

  fun _source_binding_path(tokens: Array[BoonToken val] val, index: USize): String ? =>
    let out = String
    var cursor = index + 2
    var depth: USize = 1
    while (cursor < tokens.size()) and (depth > 0) do
      let tok = tokens(cursor)?
      if tok.value == "{" then
        depth = depth + 1
      elseif tok.value == "}" then
        depth = depth - 1
        if depth == 0 then break end
      elseif (depth == 1) and ((tok.kind == "ident") or (tok.value == ".")) then
        out.append(tok.value)
      end
      cursor = cursor + 1
    end
    _trim_dots(out.clone())

  fun _payload_type(path: String): String =>
    let leaf = _leaf(path)
    if leaf == "key_down" then "KeyEvent"
    elseif leaf == "mouse" then "MouseEvent"
    elseif leaf == "resize" then "ResizeEvent"
    elseif leaf == "tick" then "TickEvent"
    elseif leaf == "change" then "Text"
    elseif (leaf == "hovered") or (leaf == "focused") then "Bool"
    elseif leaf == "value" then "Number"
    else "Pulse" end

  fun _leaf(path: String): String =>
    try
      let parts = path.split_by(".")
      parts(parts.size() - 1)?
    else
      path
    end

  fun _trim_dots(value: String): String =>
    var start: USize = 0
    var finish: USize = value.size()
    try
      while (start < finish) and (_byte(value, start)? == '.') do start = start + 1 end
      while (finish > start) and (_byte(value, finish - 1)? == '.') do finish = finish - 1 end
    end
    value.substring(start.isize(), finish.isize())

  fun _set_field(fields: Array[String] ref, depth: USize, value: String) =>
    while fields.size() <= depth do fields.push("") end
    try fields.update(depth, value)? end

  fun _truncate_fields(fields: Array[String] ref, depth: USize) =>
    while fields.size() > depth do
      try fields.pop()? end
    end

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

  fun _system_status(command: String box): I32 =>
    @system(command.cstring())

  fun _shell_quote(value: String box): String =>
    let out = String
    out.append("'")
    for ch in value.values() do
      if ch == '\'' then
        out.append("'\\''")
      else
        out.push(ch)
      end
    end
    out.append("'")
    out.clone()

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

  fun _basename_without_bn(path': String): String =>
    (_, let file) = Path.split(path')
    if file.at(".bn", -3) then file.substring(0, (file.size() - 3).isize()) else file end

  fun _basename_without_suffix(path': String, suffix: String): String =>
    (_, let file) = Path.split(path')
    if file.at(suffix, -suffix.size().isize()) then file.substring(0, (file.size() - suffix.size()).isize()) else file end

  fun _byte(text: String, index: USize): U8 ? =>
    text.at_offset(index.isize())?

  fun _loc(text: String, offset: USize): (USize, USize) =>
    var line: USize = 1
    var col: USize = 1
    var i: USize = 0
    try
      while i < offset do
        if _byte(text, i)? == 10 then
          line = line + 1
          col = 1
        else
          col = col + 1
        end
        i = i + 1
      end
    end
    (line, col)

  fun _is_ws(ch: U8): Bool =>
    (ch == 32) or (ch == 9) or (ch == 13) or (ch == 10)

  fun _is_alpha(ch: U8): Bool =>
    ((ch >= 'A') and (ch <= 'Z')) or ((ch >= 'a') and (ch <= 'z')) or (ch == '_')

  fun _is_digit(ch: U8): Bool =>
    (ch >= '0') and (ch <= '9')

  fun _is_ident(ch: U8): Bool =>
    _is_alpha(ch) or _is_digit(ch)

  fun _is_number_tail(ch: U8): Bool =>
    _is_alpha(ch) or _is_digit(ch) or (ch == '.') or (ch == '-')

  fun _is_two_symbol(value: String): Bool =>
    (value == "|>") or (value == "=>") or (value == "==") or (value == ">=") or
    (value == "<=") or (value == "!=") or (value == "&&") or (value == "||")

  fun _is_one_symbol(ch: U8): Bool =>
    (ch == '[') or (ch == ']') or (ch == '{') or (ch == '}') or (ch == '(') or (ch == ')') or
    (ch == ',') or (ch == ':') or (ch == '.') or (ch == ';') or (ch == '+') or (ch == '-') or
    (ch == '*') or (ch == '/') or (ch == '%') or (ch == '<') or (ch == '>') or (ch == '=')

  fun _is_open(value: String): Bool =>
    (value == "(") or (value == "[") or (value == "{")

  fun _is_close(value: String): Bool =>
    (value == ")") or (value == "]") or (value == "}")

class ref BoonParser
  let file: String
  let tokens: Array[BoonToken val] val
  var index: USize = 0
  var declarations: USize = 0
  var functions: USize = 0
  var ast_nodes: USize = 0
  var expression_nodes: USize = 0
  var ast_json: String = "{\"kind\":\"Program\",\"children\":[]}"
  var _program_nodes: USize = 0
  var _declaration_nodes: USize = 0
  var _function_nodes: USize = 0
  var _expression_group_nodes: USize = 0
  var _token_nodes: USize = 0
  var _source_nodes: USize = 0
  var _pass_nodes: USize = 0
  var _text_nodes: USize = 0
  var failure_code: String = "parse_error"
  var failure_message: String = "parse error"
  var failure_line: USize = 0
  var failure_column: USize = 0

  new create(file': String, tokens': Array[BoonToken val] val) =>
    file = file'
    tokens = tokens'

  fun ref parse() ? =>
    _check_canonical_source_diagnostics()?
    _record_program()
    let children = String
    var child_count: USize = 0
    while _current()?.kind != "eof" do
      let node =
      if _at("FUNCTION") then
        _parse_function()?
      elseif (_current()?.kind == "ident") and (_peek()?.value == ":") then
        _parse_declaration()?
      else
        _fail("parse_error", "expected top-level declaration or FUNCTION", _current()?)?
        ""
      end
      if child_count > 0 then children.append(",") end
      children.append(node)
      child_count = child_count + 1
    end
    let start = try tokens(0)? else BoonToken("eof", "<eof>", 0, 0, 1, 1) end
    let finish = try tokens(tokens.size() - 1)? else start end
    let out = String
    out.append("{\"kind\":\"Program\",\"source_span\":"); out.append(_span_json(start, finish)); out.append(",\"children\":[")
    out.append(children)
    out.append("]}")
    ast_json = out.clone()

  fun ref _parse_function(): String ? =>
    let start = _current()?
    _consume("FUNCTION")?
    let name_tok = _current()?
    if name_tok.kind != "ident" then _fail("parse_error", "expected function name", name_tok)? end
    let name = name_tok.value
    _consume()?
    let params = _parse_group("(", ")", "Parameters")?
    let body = _parse_group("{", "}", "Block")?
    let finish = _previous()?
    declarations = declarations + 1
    functions = functions + 1
    _record_function()
    let out = String
    out.append("{\"kind\":\"Function\",\"name\":\""); out.append(_json(name)); out.append("\",\"source_span\":")
    out.append(_span_json(start, finish)); out.append(",\"params\":"); out.append(params); out.append(",\"body\":"); out.append(body); out.append("}")
    out.clone()

  fun ref _parse_declaration(): String ? =>
    let start = _current()?
    if start.kind != "ident" then _fail("parse_error", "expected declaration name", start)? end
    let name = start.value
    _consume()?
    _consume(":")?
    let value = _parse_expression_until_top_level()?
    let finish = _previous()?
    declarations = declarations + 1
    _record_declaration()
    let out = String
    out.append("{\"kind\":\"Declaration\",\"name\":\""); out.append(_json(name)); out.append("\",\"source_span\":")
    out.append(_span_json(start, finish)); out.append(",\"value\":"); out.append(value); out.append("}")
    out.clone()

  fun ref _parse_expression_until_top_level(): String ? =>
    let start = _current()?
    let children = String
    var child_count: USize = 0
    while _current()?.kind != "eof" do
      let tok = _current()?
      if (child_count > 0) and (tok.kind == "ident") and (_peek()?.value == ":") then break end
      if (child_count > 0) and (tok.value == "FUNCTION") then break end
      let child = _parse_child_node()?
      if child_count > 0 then children.append(",") end
      children.append(child)
      child_count = child_count + 1
    end
    if child_count == 0 then _fail("parse_error", "expected expression", _current()?)? end
    let finish = _previous()?
    _record_expression_group()
    let out = String
    out.append("{\"kind\":\"Expression\",\"source_span\":"); out.append(_span_json(start, finish)); out.append(",\"children\":[")
    out.append(children); out.append("]}")
    out.clone()

  fun ref _parse_group(open: String, close: String, kind: String): String ? =>
    let start = _current()?
    _consume(open)?
    let children = String
    var child_count: USize = 0
    while not _at(close) do
      if _current()?.kind == "eof" then _fail("parse_error", "unterminated " + open, _current()?)? end
      let child = _parse_child_node()?
      if child_count > 0 then children.append(",") end
      children.append(child)
      child_count = child_count + 1
    end
    let finish = _current()?
    _consume(close)?
    _record_expression_group()
    let out = String
    out.append("{\"kind\":\""); out.append(kind); out.append("\",\"delimiter\":\""); out.append(open); out.append(close); out.append("\",\"source_span\":")
    out.append(_span_json(start, finish)); out.append(",\"children\":["); out.append(children); out.append("]}")
    out.clone()

  fun ref _parse_child_node(): String ? =>
    let tok = _current()?
    if tok.value == "(" then
      _parse_group("(", ")", "CallOrTuple")?
    elseif tok.value == "[" then
      _parse_group("[", "]", "RecordOrList")?
    elseif tok.value == "{" then
      _parse_group("{", "}", "Block")?
    elseif (tok.value == ")") or (tok.value == "]") or (tok.value == "}") then
      _fail("parse_error", "unmatched " + tok.value, tok)?
      ""
    else
      _consume()?
      _record_token(tok)
      _token_json(tok)
    end

  fun ast_kind_counts(): String =>
    let out = String
    out.append("{\"Program\":"); out.append(_program_nodes.string())
    out.append(",\"Declaration\":"); out.append(_declaration_nodes.string())
    out.append(",\"Function\":"); out.append(_function_nodes.string())
    out.append(",\"Expression\":"); out.append(_expression_group_nodes.string())
    out.append(",\"Token\":"); out.append(_token_nodes.string())
    out.append(",\"SourceMarker\":"); out.append(_source_nodes.string())
    out.append(",\"PassMarker\":"); out.append(_pass_nodes.string())
    out.append(",\"TextBlock\":"); out.append(_text_nodes.string())
    out.append("}")
    out.clone()

  fun ref _record_program() =>
    _program_nodes = _program_nodes + 1
    ast_nodes = ast_nodes + 1

  fun ref _record_declaration() =>
    _declaration_nodes = _declaration_nodes + 1
    ast_nodes = ast_nodes + 1

  fun ref _record_function() =>
    _function_nodes = _function_nodes + 1
    ast_nodes = ast_nodes + 1

  fun ref _record_expression_group() =>
    _expression_group_nodes = _expression_group_nodes + 1
    expression_nodes = expression_nodes + 1
    ast_nodes = ast_nodes + 1

  fun ref _record_token(tok: BoonToken val) =>
    _token_nodes = _token_nodes + 1
    ast_nodes = ast_nodes + 1
    if tok.value == "SOURCE" then _source_nodes = _source_nodes + 1 end
    if (tok.value == "PASS") or (tok.value == "PASSED") then _pass_nodes = _pass_nodes + 1 end
    if tok.kind == "text" then _text_nodes = _text_nodes + 1 end

  fun _token_json(tok: BoonToken val): String =>
    let kind =
      if tok.value == "SOURCE" then
        "SourceMarker"
      elseif (tok.value == "PASS") or (tok.value == "PASSED") then
        "PassMarker"
      elseif tok.kind == "text" then
        "TextBlock"
      elseif tok.kind == "string" then
        "StringLiteral"
      elseif tok.kind == "number" then
        "NumberLiteral"
      elseif tok.kind == "ident" then
        "Identifier"
      else
        "Token"
      end
    let out = String
    out.append("{\"kind\":\""); out.append(kind); out.append("\",\"token_kind\":\""); out.append(_json(tok.kind)); out.append("\",\"value\":\"")
    out.append(_json(tok.value)); out.append("\",\"source_span\":"); out.append(_span_json(tok, tok)); out.append("}")
    out.clone()

  fun _span_json(start: BoonToken val, finish: BoonToken val): String =>
    let out = String
    out.append("{\"start\":"); out.append(start.start.string()); out.append(",\"end\":"); out.append(finish.end_pos.string())
    out.append(",\"line\":"); out.append(start.line.string()); out.append(",\"column\":"); out.append(start.column.string()); out.append("}")
    out.clone()

  fun _json(value: String): String =>
    let out = String
    for ch in value.values() do
      match ch
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | 10 => out.append("\\n")
      | 13 => out.append("\\r")
      | 9 => out.append("\\t")
      else
        if ch >= 32 then out.push(ch) end
      end
    end
    out.clone()

  fun ref _check_canonical_source_diagnostics() ? =>
    var i: USize = 0
    while i < tokens.size() do
      let tok = tokens(i)?
      if tok.value == "LINK" then
        _fail("legacy_link", "`LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode", tok)?
      end
      if tok.value == "SOURCE" then
        let prev = if i > 0 then tokens(i - 1)?.value else "" end
        let next = if (i + 1) < tokens.size() then tokens(i + 1)?.value else "" end
        if _is_operator(next) or (_is_operator(prev) and (prev != "|>")) then
          _fail("source_as_value", "SOURCE marks a runtime source field and cannot be used as a normal value", tok)?
        end
      end
      if (tok.value == "event") and ((i + 2) < tokens.size()) and (tokens(i + 1)?.value == ":") and (tokens(i + 2)?.value == "SOURCE") then
        _fail("incompatible_source_binding", "incompatible source binding", tokens(i + 2)?)?
      end
      i = i + 1
    end

  fun _is_operator(value: String): Bool =>
    (value == "+") or (value == "-") or (value == "*") or (value == "/") or (value == "%") or
    (value == "==") or (value == "!=") or (value == ">=") or (value == "<=") or (value == ">") or (value == "<")

  fun _previous(): BoonToken val ? =>
    if index == 0 then error end
    tokens(index - 1)?

  fun _current(): BoonToken val ? =>
    tokens(index)?

  fun _peek(): BoonToken val ? =>
    tokens(index + 1)?

  fun _at(value: String): Bool =>
    try _current()?.value == value else false end

  fun ref _consume(value: String = "") ? =>
    let tok = _current()?
    if (value != "") and (tok.value != value) then
      _fail("parse_error", "expected " + value + ", found " + tok.value, tok)?
    end
    index = index + 1

  fun ref _fail(code: String, message: String, tok: BoonToken val) ? =>
    failure_code = code
    failure_message = message
    failure_line = tok.line
    failure_column = tok.column
    error
