use "files"

class iso KeyboardTestNotify is InputNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref apply(data': Array[U8] iso) =>
    let data: Array[U8] ref = consume data'
    let key = NativeSafety.decode_key(data)
    NativeSafety.restore_terminal(_env)
    _env.out.print("decoded: " + key)
    _env.input.dispose()
    _env.exitcode(0)

  fun ref dispose() =>
    None

primitive NativeSafety
  fun keyboard_test_command(env: Env) =>
    @system("stty raw -echo".cstring())
    env.out.print("keyboard-test ready")
    enter_terminal(env)
    env.input(KeyboardTestNotify(env), 32)

  fun verify_command(env: Env, pty: Bool, report': String = "") =>
    if not pty then
      env.err.print("error: verify-terminal-safety requires --pty")
      Help.verify_terminal_safety(env)
      env.exitcode(2)
      return
    end
    let report = if report' == "" then "build/reports/verify-terminal-safety.json" else report' end
    _mkdirs()
    let q_case = _run_pty_case(env, "q_restore", "Q", "decoded: Q")
    let ctrl_case = _run_pty_case(env, "ctrl_c_restore", "C-c", "decoded: CtrlC")
    let failures = Array[String]
    if q_case._2 != "pass" then failures.push("q_restore failed") end
    if ctrl_case._2 != "pass" then failures.push("ctrl_c_restore failed") end
    _write_file(env, report, _report(q_case, ctrl_case, failures))
    if failures.size() == 0 then
      env.out.print("terminal-safety ok: PTY decoded Q and Ctrl+C, restore observed")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun enter_terminal(env: Env) =>
    env.out.write("\x1B[?1049h\x1B[?25l")

  fun restore_terminal(env: Env) =>
    @system("stty sane".cstring())
    env.out.write("\x1B[?25h\x1B[?1049l")
    env.out.print("restore: ok")

  fun decode_key(data: Array[U8] box): String =>
    try
      if (data.size() == 1) and (data(0)? == 3) then return "CtrlC" end
      if (data.size() == 1) and ((data(0)? == 81) or (data(0)? == 113)) then return "Q" end
      if (data.size() == 1) and ((data(0)? == 10) or (data(0)? == 13)) then return "Enter" end
      if (data.size() == 1) and (data(0)? == 32) then return "Space" end
      if (data.size() == 3) and (data(0)? == 27) and (data(1)? == 91) then
        if data(2)? == 65 then return "ArrowUp" end
        if data(2)? == 66 then return "ArrowDown" end
        if data(2)? == 67 then return "ArrowRight" end
        if data(2)? == 68 then return "ArrowLeft" end
      end
      if data.size() == 1 then
        let ch = data(0)?
        if (ch >= 32) and (ch <= 126) then
          return "Text:" + String.from_array([ch])
        end
      end
    end
    "Bytes:" + _hex_bytes(data)

  fun _run_pty_case(env: Env, name: String, input: String, expected_decode: String): (String, String, I32, Bool, Bool, String) =>
    let session: String val = recover val "boonpony_safety_native_" + name end
    let output_file: String val = recover val "build/cache/terminal-safety-" + name + ".out" end
    let command: String val = recover val
      "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true; " +
      "tmux new-session -d -s " + _shell_quote(session) + " -x 80 -y 24 " +
      _shell_quote("bash -lc 'PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH build/bin/boonpony tui --keyboard-test; code=$?; echo __EXIT:$code; sleep 1'") + "; " +
      "for i in $(seq 1 80); do tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'keyboard-test ready' && break; sleep 0.05; done; " +
      "tmux send-keys -t " + _shell_quote(session) + " " + _shell_quote(input) + "; " +
      "for i in $(seq 1 80); do tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q '__EXIT:' && break; sleep 0.05; done; " +
      "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(output_file) + "; " +
      "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true"
    end
    let shell_status = _system_status(command)
    let output = _clean_output(try _read_file(env, output_file)? else "" end)
    let exit_status = _exit_status_from_output(output)
    let decoded = output.contains(expected_decode)
    let restored = output.contains("restore: ok")
    let status = if (shell_status == 0) and (exit_status == 0) and decoded and restored then "pass" else "fail" end
    (name, status, exit_status, decoded, restored, output)

  fun _report(q_case: (String, String, I32, Bool, Bool, String), ctrl_case: (String, String, I32, Bool, Bool, String), failures: Array[String] box): String =>
    let out = String
    out.append("{\n  \"command\":\"verify-terminal-safety\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"toolchain\":{\"ponyc\":\"native-pony\",\"os\":\"linux-x86_64\"},\n")
    out.append("  \"terminal_capabilities\":{\"alternate_screen\":true,\"cursor_hide_show\":true,\"raw_input\":true,\"pty_command\":\"tmux new-session/send-keys\"},\n")
    out.append("  \"cases\":[")
    _append_case(out, q_case, "decoded: Q")
    out.append(",")
    _append_case(out, ctrl_case, "decoded: CtrlC")
    out.append("],\n  \"failures\":[")
    var index: USize = 0
    for failure in failures.values() do
      if index > 0 then out.append(",") end
      out.append("{\"message\":\""); _append_json(out, failure); out.append("\"}")
      index = index + 1
    end
    out.append("]\n}\n")
    out.clone()

  fun _append_case(out: String ref, item: (String, String, I32, Bool, Bool, String), expected_decode: String) =>
    out.append("{\"name\":\""); _append_json(out, item._1); out.append("\",\"status\":\""); out.append(item._2); out.append("\",")
    out.append("\"exit_status\":"); out.append(item._3.string()); out.append(",\"signal\":null,")
    out.append("\"expected_decode\":\""); _append_json(out, expected_decode); out.append("\",")
    out.append("\"decoded\":"); out.append(if item._4 then "true" else "false" end); out.append(",")
    out.append("\"restored\":"); out.append(if item._5 then "true" else "false" end); out.append(",")
    out.append("\"output_excerpt\":\""); _append_json(out, item._6); out.append("\"}")

  fun _exit_status_from_output(output: String): I32 =>
    try
      let marker = "__EXIT:"
      let start = output.find(marker)? + marker.size().isize()
      var finish = start
      while finish < output.size().isize() do
        let ch = output.at_offset(finish)?
        if (ch < '0') or (ch > '9') then break end
        finish = finish + 1
      end
      output.substring(start, finish).i32()?
    else
      -1
    end

  fun _hex_bytes(data: Array[U8] box): String =>
    let out = String
    var index: USize = 0
    for byte in data.values() do
      if index > 0 then out.append(" ") end
      out.append(_hex_pair(byte))
      index = index + 1
    end
    out.clone()

  fun _hex_pair(byte: U8): String =>
    let digits = "0123456789abcdef"
    let out = String
    try
      out.push(digits.at_offset((byte / 16).isize())?)
      out.push(digits.at_offset((byte % 16).isize())?)
    end
    out.clone()

  fun _clean_output(text: String): String =>
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
      if ch == 39 then
        out.append("'\\''")
      else
        out.push(ch)
      end
    end
    out.append("'")
    out.clone()
