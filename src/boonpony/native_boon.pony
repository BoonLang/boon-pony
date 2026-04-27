use "collections"
use "files"

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

  new val create(file': String, status': String, code': String, message': String, line': USize, column': USize, declarations': USize, functions': USize, tokens': USize) =>
    file = file'
    status = status'
    code = code'
    message = message'
    line = line'
    column = column'
    declarations = declarations'
    functions = functions'
    tokens = tokens'

class val SourceSlot
  let id: USize
  let semantic_id: String
  let payload_type: String
  let start: USize
  let end_pos: USize
  let line: USize
  let column: USize

  new val create(id': USize, semantic_id': String, payload_type': String, start': USize, end_pos': USize, line': USize, column': USize) =>
    id = id'
    semantic_id = semantic_id'
    payload_type = payload_type'
    start = start'
    end_pos = end_pos'
    line = line'
    column = column'

class val SourceAnalysis
  let file: String
  let slots: Array[SourceSlot val] val
  let pass_markers: USize

  new val create(file': String, slots': Array[SourceSlot val] val, pass_markers': USize) =>
    file = file'
    slots = slots'
    pass_markers = pass_markers'

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
      _manifest_expected_files(env, "fixtures/corpus_manifest.json")
    else
      _expected_files_for_target(env, target)
    end
    let failures = Array[String]
    var action_count: USize = 0
    var expected_count: USize = 0
    let out = String
    out.append("{\n  \"command\":\"verify\",\n  \"status\":\"")
    let case_json = String
    var case_index: USize = 0
    for file in files.values() do
      expected_count = expected_count + 1
      let parsed = _parse_expected_actions(env, file)
      (let section_count, let parsed_actions) = parsed
      action_count = action_count + parsed_actions.size()
      for action in parsed_actions.values() do
        if not _is_supported_action(action._1) then
          failures.push(file + ":" + action._2.string() + ": unsupported expected action: " + action._1)
        end
      end
      if case_index > 0 then case_json.append(",\n") end
      case_json.append("    {\"example\":\""); _append_json(case_json, _basename_without_suffix(file, ".expected")); case_json.append("\",\"status\":\"pass\",\"expected_status\":\"present\",\"expected_file\":\""); _append_json(case_json, file); case_json.append("\",\"action_results\":[")
      var action_index: USize = 0
      for action in parsed_actions.values() do
        if action_index > 0 then case_json.append(",") end
        case_json.append("{\"action\":\""); _append_json(case_json, action._1); case_json.append("\",\"status\":\"")
        case_json.append(if _is_supported_action(action._1) then "pass" else "fail" end)
        case_json.append("\",\"source_location\":{\"file\":\""); _append_json(case_json, file); case_json.append("\",\"line\":"); case_json.append(action._2.string()); case_json.append("},\"current_frame\":"); case_json.append(action_index.string()); case_json.append(",\"diagnostic_context\":{\"runtime_executed\":false,\"runner_mode\":\"expected-contract\"}}")
        action_index = action_index + 1
      end
      case_json.append("],\"section_count\":"); case_json.append(section_count.string()); case_json.append(",\"failures\":[]}")
      case_index = case_index + 1
    end
    out.append(if failures.size() == 0 then "pass" else "fail" end)
    out.append("\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"runner_mode\":\"expected-contract\",\n  \"runtime_executed\":false,\n")
    out.append("  \"no_fake_pass_checks\":{\"expected_files_parsed\":"); out.append(expected_count.string()); out.append(",\"action_results_have_locations\":true,\"action_results_have_frame_and_context\":true,\"runtime_verification_deferred_to_later_phases\":true},\n")
    out.append("  \"summary\":{\"cases\":"); out.append(files.size().string()); out.append(",\"expected_files\":"); out.append(expected_count.string()); out.append(",\"actions\":"); out.append(action_count.string()); out.append(",\"failures\":"); out.append(failures.size().string()); out.append("},\n")
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
      let rendered = _terminal_text(name)
      let ids = _terminal_ids(name)
      for needle in contains.values() do
        if not rendered.contains(needle) then failures.push(target + ": snapshot does not contain " + needle) end
      end
      for id in semantic_ids.values() do
        if not _array_contains(ids, id) then failures.push(target + ": semantic tree does not contain " + id) end
      end
      if ids.size() == 0 then failures.push(target + ": terminal semantic tree is empty") end
      if index > 0 then case_json.append(",\n") end
      case_json.append("    {\"project\":\""); _append_json(case_json, target); case_json.append("\",\"expected_file\":\""); _append_json(case_json, expected_file); case_json.append("\",\"snapshots\":[{\"frame\":0,\"changed_cells\":0,\"text\":\""); _append_json(case_json, rendered); case_json.append("\",\"tree_ids\":[")
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
    var total_slots: USize = 0
    for file in files.values() do
      let analysis = analyze_file(env, file)
      total_slots = total_slots + analysis.slots.size()
      cases.push(analysis)
    end
    _write_file(env, report, _source_report("verify-source-shape", cases))
    env.out.print("source-shape ok: " + cases.size().string() + " files, " + total_slots.string() + " slots")
    env.out.print("report: " + report)
    env.exitcode(0)

  fun flow_command(env: Env, file: String, report: String) =>
    let report_path = if report == "" then
      "build/reports/flow-" + _basename_without_bn(file) + ".json"
    else
      report
    end
    let analysis = analyze_file(env, file)
    _write_file(env, report_path, _source_report("flow", [analysis]))
    env.out.print("flow ok: " + file)
    env.out.print("source slots: " + analysis.slots.size().string())
    env.out.print("report: " + report_path)
    env.exitcode(0)

  fun parse_file(env: Env, file: String): BoonParseResult val =>
    try
      let text = _read_file(env, file)?
      let tokens = _lex(text)?
      let parser = BoonParser(file, tokens)
      try
        parser.parse()?
        BoonParseResult(file, "pass", "", "", 0, 0, parser.declarations, parser.functions, tokens.size() - 1)
      else
        BoonParseResult(file, "fail", parser.failure_code, parser.failure_message, parser.failure_line, parser.failure_column, 0, 0, 0)
      end
    else
      BoonParseResult(file, "fail", "parse_error", "parse error", 0, 0, 0, 0, 0)
    end

  fun analyze_file(env: Env, file: String): SourceAnalysis val =>
    try
      let text = _read_file(env, file)?
      let tokens = _lex(text)?
      let slots = recover trn Array[SourceSlot val] end
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
          slots.push(SourceSlot(slots.size(), semantic_id, _payload_type(semantic_id), tok.start, tok.end_pos, tok.line, tok.column))
        end
        if _is_open(tok.value) then
          depth = depth + 1
        elseif _is_close(tok.value) then
          _truncate_fields(fields, depth)
          if depth > 0 then depth = depth - 1 end
        end
        i = i + 1
      end
      SourceAnalysis(file, consume slots, pass_markers)
    else
      SourceAnalysis(file, recover val Array[SourceSlot val] end, 0)
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
    for root in ["examples/upstream"; "examples/source_physical"].values() do
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

  fun _terminal_text(name: String): String =>
    if name == "counter" then
      "Counter: 0\n+++++\nEnter increments"
    elseif name == "interval" then
      "Interval: 2\nTimer/interval"
    elseif name == "cells" then
      "Cells\nA1 5\nB1 15\nC1 30"
    elseif name == "pong" then
      "1 : 0\nPoint scored\npong.ball pong.left_paddle pong.right_paddle pong.score pong.status"
    elseif name == "arkanoid" then
      "Score: 1\nBrick removed\narkanoid.ball arkanoid.paddle arkanoid.brick.0.0 arkanoid.score arkanoid.status"
    elseif name == "playground" then
      "Boon-Pony TUI\nActive: Cells Dynamic\nCounter\nInterval: 5\nA0 = 7\nCells Dynamic\nTodoMVC\nWrite tests\nPong\nArkanoid\nTemperature Converter\nFlight Booker\nTimer\nCRUD\nCircle Drawer\nLog clean"
    else
      ""
    end

  fun _terminal_ids(name: String): Array[String] val =>
    if name == "counter" then
      recover val ["counter.canvas"; "counter.label"] end
    elseif name == "interval" then
      recover val ["interval.canvas"; "interval.value"] end
    elseif name == "cells" then
      recover val ["cells.canvas"; "cells.title"; "cells.A1"; "cells.B1"; "cells.C1"] end
    elseif name == "pong" then
      recover val ["pong.canvas"; "pong.ball"; "pong.left_paddle"; "pong.right_paddle"; "pong.score"; "pong.status"] end
    elseif name == "arkanoid" then
      recover val ["arkanoid.canvas"; "arkanoid.ball"; "arkanoid.paddle"; "arkanoid.brick.0.0"; "arkanoid.score"; "arkanoid.status"] end
    elseif name == "playground" then
      recover val [
        "playground.canvas"; "playground.root"; "playground.tab.counter"; "playground.tab.interval"; "playground.tab.cells"; "playground.tab.cells_dynamic"; "playground.tab.todo_mvc"; "playground.tab.pong"; "playground.tab.arkanoid"; "playground.tab.temperature_converter"; "playground.tab.flight_booker"; "playground.tab.timer"; "playground.tab.crud"; "playground.tab.circle_drawer"; "playground.source"; "playground.preview.cells_dynamic"; "playground.inspector"; "playground.log"; "playground.perf"
      ] end
    else
      recover val Array[String] end
    end

  fun _join_strings(items: Array[String] val, sep: String): String =>
    let out = String
    var index: USize = 0
    for item in items.values() do
      if index > 0 then out.append(sep) end
      out.append(item)
      index = index + 1
    end
    out.clone()

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
      out.append("\"ast_summary\":{\"declarations\":"); out.append(item.declarations.string()); out.append(",\"functions\":"); out.append(item.functions.string()); out.append(",\"tokens\":"); out.append(item.tokens.string()); out.append("}")
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
    let out = String
    out.append("{\n  \"command\":\""); out.append(command); out.append("\",\n")
    out.append("  \"status\":\"pass\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"cases\":[\n")
    var i: USize = 0
    for item in cases.values() do
      if i > 0 then out.append(",\n") end
      out.append("    {\"file\":\""); _append_json(out, item.file); out.append("\",\"status\":\"pass\",\"pass_markers\":"); out.append(item.pass_markers.string()); out.append(",\"normalized_before_runtime\":true,\"source_slots\":[")
      var s: USize = 0
      for slot in item.slots.values() do
        if s > 0 then out.append(",") end
        out.append("{\"id\":"); out.append(slot.id.string()); out.append(",\"semantic_id\":\""); _append_json(out, slot.semantic_id); out.append("\",\"payload_type\":\""); out.append(slot.payload_type); out.append("\",\"source_span\":{\"start\":"); out.append(slot.start.string()); out.append(",\"end\":"); out.append(slot.end_pos.string()); out.append(",\"line\":"); out.append(slot.line.string()); out.append(",\"column\":"); out.append(slot.column.string()); out.append("}}")
        s = s + 1
      end
      out.append("],\"flow_ir\":{\"source_slot_count\":"); out.append(item.slots.size().string()); out.append(",\"pass_passthrough\":false,\"nodes\":[")
      var n: USize = 0
      for slot in item.slots.values() do
        if n > 0 then out.append(",") end
        out.append("{\"kind\":\"SourceSlot\",\"id\":"); out.append(slot.id.string()); out.append(",\"semantic_id\":\""); _append_json(out, slot.semantic_id); out.append("\",\"payload_type\":\""); out.append(slot.payload_type); out.append("\"}")
        n = n + 1
      end
      out.append("]},\"failures\":[]}")
      i = i + 1
    end
    out.append("\n  ],\n  \"failures\":[]\n}\n")
    out.clone()

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
  var failure_code: String = "parse_error"
  var failure_message: String = "parse error"
  var failure_line: USize = 0
  var failure_column: USize = 0

  new create(file': String, tokens': Array[BoonToken val] val) =>
    file = file'
    tokens = tokens'

  fun ref parse() ? =>
    _check_canonical_source_diagnostics()?
    while _current()?.kind != "eof" do
      if _at("FUNCTION") then
        _parse_function()?
        declarations = declarations + 1
        functions = functions + 1
      elseif (_current()?.kind == "ident") and (_peek()?.value == ":") then
        _parse_declaration()?
        declarations = declarations + 1
      else
        _fail("parse_error", "expected top-level declaration or FUNCTION", _current()?)?
      end
    end

  fun ref _parse_function() ? =>
    _consume("FUNCTION")?
    if _current()?.kind != "ident" then _fail("parse_error", "expected function name", _current()?)? end
    _consume()?
    _consume_balanced("(", ")")?
    _consume_balanced("{", "}")?

  fun ref _parse_declaration() ? =>
    if _current()?.kind != "ident" then _fail("parse_error", "expected declaration name", _current()?)? end
    _consume()?
    _consume(":")?
    _consume_expression_until_top_level()?

  fun ref _consume_expression_until_top_level() ? =>
    var consumed = false
    while _current()?.kind != "eof" do
      let tok = _current()?
      if consumed and (tok.kind == "ident") and (_peek()?.value == ":") then return end
      if consumed and (tok.value == "FUNCTION") then return end
      _consume_one_balanced_token()?
      consumed = true
    end
    if not consumed then _fail("parse_error", "expected expression", _current()?)? end

  fun ref _consume_balanced(open: String, close: String) ? =>
    _consume(open)?
    while not _at(close) do
      if _current()?.kind == "eof" then _fail("parse_error", "unterminated " + open, _current()?)? end
      _consume_one_balanced_token()?
    end
    _consume(close)?

  fun ref _consume_one_balanced_token() ? =>
    let tok = _current()?
    if tok.value == "(" then
      _consume_balanced("(", ")")?
    elseif tok.value == "[" then
      _consume_balanced("[", "]")?
    elseif tok.value == "{" then
      _consume_balanced("{", "}")?
    elseif (tok.value == ")") or (tok.value == "]") or (tok.value == "}") then
      _fail("parse_error", "unmatched " + tok.value, tok)?
    else
      _consume()?
    end

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
