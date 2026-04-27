use "files"

class ref NativeCodegenResult
  let project: String
  let app: String
  let generated_dir: String
  let binary: String
  var metadata: String = "{}"
  var stdout: String = ""
  let failures: Array[String] ref = Array[String]

  new create(project': String) =>
    project = project'
    app = NativeCodegen.project_name(project')
    generated_dir = "build/generated/" + app
    binary = "build/bin/generated/" + app

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
      let command: String val = recover val _shell_quote(result.binary) + " --protocol > " + _shell_quote(capture) + " 2>&1" end
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
    if not _implemented_app(result.app) then result.failures.push("codegen for " + project + " is not implemented yet") end
    let files = _source_files(env, project)
    if files.size() == 0 then result.failures.push("project has no .bn source files: " + project) end
    for file in files.values() do
      try
        let text = _read_file(env, file)?
        if text.contains("LINK") then result.failures.push("forbidden legacy LINK spelling in " + file) end
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
        let template = _read_file(env, "src/codegen/templates/" + result.app + "/main.pony")?
        let runtime = _read_file(env, "src/runtime/boon_runtime/runtime.pony")?
        result.metadata = _metadata_json(env, result, files)
        _write_file(env, result.generated_dir + "/main.pony", template)
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
    for typ in ["ready"; "frame"; "tree"; "metrics"; "bye"].values() do
      if not out.contains("\"type\":\"" + typ + "\"") then
        result.failures.push("missing protocol message: " + typ)
      end
    end
    if out.contains("\"protocol_version\":2") or not out.contains("\"protocol_version\":1") then
      result.failures.push("bad protocol version")
    end
    let frame = _line_for_type(out, "frame")
    if (frame == "") or (not frame.contains("\"runs\"")) or frame.contains("\"cells\"") then
      result.failures.push("bad frame encoding")
    end
    let tree = _line_for_type(out, "tree")
    if (tree == "") or (not tree.contains("\"children\":[{")) then
      result.failures.push("empty semantic tree")
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

  fun _metadata_json(env: Env, result: NativeCodegenResult, files: Array[String] val): String =>
    let out = String
    out.append("{\"app\":\""); _append_json(out, result.app); out.append("\",")
    out.append("\"project\":\""); _append_json(out, result.project); out.append("\",")
    out.append("\"source_files\":"); out.append(_strings_json(files)); out.append(",")
    out.append("\"source_hash\":\""); out.append(_source_hash(env, files)); out.append("\",")
    out.append("\"generated_at\":\"native-pony\",")
    out.append("\"protocol_version\":1,")
    out.append("\"runtime_actor\":\"GeneratedApp\",")
    out.append("\"source_slots_normalized\":true}")
    out.clone()

  fun _message_types_json(stdout: String): String =>
    let types = recover trn Array[String] end
    for typ in ["ready"; "frame"; "tree"; "metrics"; "bye"].values() do
      let needle: String val = recover val "\"type\":\"" + typ + "\"" end
      if stdout.contains(needle) then types.push(typ) end
    end
    _strings_json(consume types)

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
    (app == "counter") or (app == "pong") or (app == "arkanoid")

  fun _mkdirs() =>
    @system("mkdir -p build/reports build/cache build/bin/generated".cstring())

  fun _acquire_lock(app: String): Bool =>
    _mkdirs()
    let lock: String val = recover val "build/cache/codegen-" + app + ".lock" end
    let command: String val = recover val "start=$(date +%s); while ! mkdir " + _shell_quote(lock) + " 2>/dev/null; do now=$(date +%s); if [ $((now - start)) -gt 15 ]; then exit 1; fi; sleep 0.05; done" end
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
