use "files"

primitive NativePty
  fun verify_command(env: Env, report': String = "") =>
    let report = if report' == "" then "build/reports/verify-pty.json" else report' end
    _mkdirs()
    let cases = Array[(String, String, Array[String] val)]
    cases.push(_run_pong(env))
    cases.push(_run_arkanoid(env))
    cases.push(_run_playground(env))
    cases.push(_run_source_edit(env))
    let failures = Array[String]
    for item in cases.values() do
      if item._2 != "pass" then failures.push(item._1 + " failed") end
    end
    _write_file(env, report, _report(cases, failures))
    if failures.size() == 0 then
      env.out.print("pty ok: pong, arkanoid, playground, and source-edit proofs passed")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun _run_pong(env: Env): (String, String, Array[String] val) =>
    let out = "build/cache/pty-pong.out"
    let session = "boonpony_native_pty_pong"
    let command = _pty_prefix(session, "100", "32", "build/bin/boonpony play examples/terminal/pong") +
      _wait(session, "Press Space to start") +
      _send_key(session, "Space") + _wait(session, "Point scored") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "pong", consume command, out, recover val ["terminal restored"; "final score 1 : 0"; "__EXIT:0"] end)

  fun _run_arkanoid(env: Env): (String, String, Array[String] val) =>
    let out = "build/cache/pty-arkanoid.out"
    let session = "boonpony_native_pty_arkanoid"
    let command = _pty_prefix(session, "100", "34", "build/bin/boonpony play examples/terminal/arkanoid") +
      _wait(session, "Playing") +
      _send_key(session, "Space") + _wait(session, "Brick removed") +
      _send_key(session, "L") + _wait(session, "Lost") +
      _send_key(session, "Space") + _wait(session, "Playing") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "arkanoid", consume command, out, recover val ["final status Playing"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground(env: Env): (String, String, Array[String] val) =>
    let out = "build/cache/pty-playground.out"
    let session = "boonpony_native_pty_playground"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui") +
      _wait(session, "Counter: 0") +
      _send_key(session, "Enter") +
      _send_key(session, "S-Right") +
      _send_key(session, "S-Right") +
      _send_key(session, "Enter") + _send_key(session, "BSpace") + _send_literal(session, "7") + _send_key(session, "Enter") +
      _send_key(session, "S-Right") +
      _send_mouse(session, "44", "1") + _send_literal(session, "a") +
      _send_key(session, "S-Right") + _send_key(session, "Enter") +
      _send_key(session, "S-Right") +
      _send_key(session, "S-Right") + _send_literal(session, "c") + _send_literal(session, "f") +
      _send_key(session, "S-Right") + _send_literal(session, "b") +
      _send_key(session, "S-Right") + _send_literal(session, "u") +
      _send_key(session, "S-Right") + _send_literal(session, "a") +
      _send_key(session, "S-Right") + _send_mouse(session, "50", "12") + _send_mouse(session, "54", "14") + _send_literal(session, "u") +
      _send_key(session, "S-Right") + _send_key(session, "S-Left") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "playground", consume command, out, recover val ["Counter increments: yes"; "Cells A0: 7"; "TodoMVC Write tests: yes"; "Pong rally: yes"; "Temperature both directions: yes"; "Flight Booker return booking: yes"; "CRUD Ada Lovelace: yes"; "Circle Drawer Circles:1"; "Tab wrap forward/back: yes"; "Mouse selected TodoMVC: yes"; "log clean: yes"; "terminal restored"; "__EXIT:0"] end)

  fun _run_source_edit(env: Env): (String, String, Array[String] val) =>
    let out = "build/cache/pty-source-edit.out"
    let session = "boonpony_native_pty_source"
    let command = _pty_prefix(session, "132", "40", "export EDITOR=true; export BOONPONY_OPEN_EDITOR=1; build/bin/boonpony tui --example pong") +
      _wait(session, "Active: Pong") +
      _send_literal(session, "e") + _send_literal(session, "v") + _send_literal(session, "d") + _send_literal(session, "r") +
      _send_literal(session, "b") + _send_literal(session, "p") + _send_literal(session, "!") + _send_literal(session, "o") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "source-edit", consume command, out, recover val ["Source edit mode: on"; "Diagnostics: invalid source marker"; "Build: passed"; "Rerun: Pong preview restarted"; "External editor: true completed"; "terminal restored"; "__EXIT:0"] end)

  fun _run_case(env: Env, name: String, command: String box, output_file: String, needles: Array[String] val): (String, String, Array[String] val) =>
    let status = _system_status(command)
    let output = _clean(try _read_file(env, output_file)? else "" end)
    let missing = recover trn Array[String] end
    if status != 0 then missing.push("shell exit " + status.string()) end
    for needle in needles.values() do
      if not output.contains(needle) then missing.push(needle) end
    end
    let final_status = if missing.size() == 0 then "pass" else "fail" end
    (name, final_status, consume missing)

  fun _pty_prefix(session: String, width: String, height: String, inner: String): String =>
    "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true; " +
    "tmux new-session -d -s " + _shell_quote(session) + " -x " + width + " -y " + height + " " +
    _shell_quote("bash -lc 'export PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH; " + inner + "; code=$?; echo __EXIT:$code; sleep 1'") + "; "

  fun _wait(session: String, needle: String): String =>
    "for i in $(seq 1 100); do tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q " + _shell_quote(needle) + " && break; sleep 0.05; done; "

  fun _send_key(session: String, key: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " " + _shell_quote(key) + "; sleep 0.12; "

  fun _send_literal(session: String, text: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " -l " + _shell_quote(text) + "; sleep 0.12; "

  fun _send_mouse(session: String, x: String, y: String): String =>
    "printf '\\033[<0;" + x + ";" + y + "M' | tmux load-buffer -; tmux paste-buffer -t " + _shell_quote(session) + "; sleep 0.12; "

  fun _capture(session: String, output_file: String): String =>
    "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(output_file) + "; " +
    "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true"

  fun _report(cases: Array[(String, String, Array[String] val)] box, failures: Array[String] box): String =>
    let out = String
    out.append("{\n  \"command\":\"verify-pty\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"cases\":[")
    var index: USize = 0
    for item in cases.values() do
      if index > 0 then out.append(",") end
      out.append("{\"name\":\""); _append_json(out, item._1); out.append("\",\"status\":\""); out.append(item._2); out.append("\",\"missing\":"); out.append(_strings_json(item._3)); out.append("}")
      index = index + 1
    end
    out.append("],\n  \"failures\":"); out.append(_strings_json(failures)); out.append("\n}\n")
    out.clone()

  fun _strings_json(items: Array[String] box): String =>
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

  fun _clean(text: String): String =>
    let out = String
    var escaping = false
    for ch in text.values() do
      if escaping then
        if ((ch >= 'A') and (ch <= 'Z')) or ((ch >= 'a') and (ch <= 'z')) then escaping = false end
      elseif ch == 27 then
        escaping = true
      elseif (ch == 10) or (ch == 13) or (ch == 9) or (ch >= 32) then
        out.push(ch)
      end
    end
    out.clone()

  fun _mkdirs() =>
    @system("mkdir -p build/reports build/cache".cstring())

  fun _system_status(command: String box): I32 =>
    let status = @system(command.cstring())
    if status > 255 then status / 256 else status end

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
        if ch >= 32 then out.push(ch) end
      end
    end

  fun _shell_quote(value: String box): String =>
    let out = String
    out.append("'")
    for ch in value.values() do
      if ch == 39 then out.append("'\\''") else out.push(ch) end
    end
    out.append("'")
    out.clone()
