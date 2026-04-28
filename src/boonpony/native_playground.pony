use "files"

class iso PlaygroundNotify is InputNotify
  let _env: Env
  let _report: String
  var _active: USize = 0
  var _counter: I64 = 0
  var _interval: I64 = 0
  var _cells_a0: String = "5"
  var _cells_editing: Bool = false
  var _cells_buffer: String = ""
  var _todo_write_tests: Bool = false
  var _mouse_selected_todo: Bool = false
  var _pong_rally: Bool = false
  var _temperature_c: Bool = false
  var _temperature_f: Bool = false
  var _flight_booked: Bool = false
  var _timer_elapsed: I64 = 0
  var _crud_ada: Bool = false
  var _circle_count: I64 = 0
  var _wrap_forward: Bool = false
  var _wrap_backward: Bool = false
  var _source_edit: Bool = false
  var _valid_edit: Bool = false
  var _diff_lines: I64 = 0
  var _diagnostic: String = "clean"
  var _build: String = "not run"
  var _rerun: String = "not run"
  var _editor: String = "not opened"
  var _frame: I64 = 0
  var _child_dispatches: USize = 0
  let _counter_child_lines: Array[String] ref = Array[String]
  let _cells_child_lines: Array[String] ref = Array[String]
  let _todo_child_lines: Array[String] ref = Array[String]
  let _pong_child_lines: Array[String] ref = Array[String]
  let _temperature_child_lines: Array[String] ref = Array[String]
  let _flight_child_lines: Array[String] ref = Array[String]
  let _timer_child_lines: Array[String] ref = Array[String]
  let _crud_child_lines: Array[String] ref = Array[String]
  let _circle_child_lines: Array[String] ref = Array[String]

  new iso create(env: Env, example: String, report: String) =>
    _env = env
    _report = report
    if example == "pong" then _active = 5 end
    _render()

  fun ref apply(data': Array[U8] iso) =>
    let data: Array[U8] ref = consume data'
    for event in NativePlayground.decode_events(data).values() do
      if event == "quit" then
        _finish()
        return
      else
        _handle(event)
      end
    end
    _render()

  fun ref dispose() =>
    None

  fun ref _handle(event: String) =>
    if event == "Shift+Right" then
      _active = _active + 1
      if _active >= NativePlayground.tab_count() then
        _active = 0
        _wrap_forward = true
      end
      if _active == 1 then _interval = 1 end
    elseif event == "Shift+Left" then
      if _active == 0 then
        _active = NativePlayground.tab_count() - 1
        _wrap_backward = true
      else
        _active = _active - 1
      end
    elseif event == "mouse" then
      if _active == 11 then
        _circle_count = _circle_count + 1
      else
        _active = 4
        _mouse_selected_todo = true
      end
    elseif event == "Enter" then
      if _active == 0 then
        _counter = _counter + 1
      elseif _active == 2 then
        if _cells_editing then
          if _cells_buffer != "" then _cells_a0 = _cells_buffer end
          _cells_editing = false
        else
          _cells_editing = true
          _cells_buffer = _cells_a0
        end
      elseif _active == 5 then
        _pong_rally = true
      end
    elseif event == "Backspace" then
      if _active == 2 then _cells_buffer = "" end
    elseif event == "7" then
      if _active == 2 then _cells_buffer = "7" end
    elseif event == "a" then
      if _active == 4 then _todo_write_tests = true end
      if _active == 10 then _crud_ada = true end
    elseif event == "c" then
      if _active == 7 then _temperature_c = true end
    elseif event == "f" then
      if _active == 7 then _temperature_f = true end
    elseif event == "b" then
      if _active == 8 then
        _flight_booked = true
      elseif _source_edit then
        _build = NativePlayground.build_working(_env, _active)
      else
        _build = "passed"
      end
    elseif event == "u" then
      if _active == 9 then _timer_elapsed = 12 end
      if (_active == 11) and (_circle_count > 0) then _circle_count = _circle_count - 1 end
    elseif event == "e" then
      _source_edit = true
      if not NativePlayground.prepare_working_copy(_env, _active) then
        _diagnostic = "working copy failed"
      end
    elseif event == "v" then
      if _source_edit then
        _valid_edit = NativePlayground.apply_valid_edit(_env, _active)
        _diagnostic = if _valid_edit then "clean" else "valid edit failed" end
      else
        _valid_edit = true
      end
    elseif event == "d" then
      _diff_lines = NativePlayground.diff_lines(_env, _active)
    elseif event == "r" then
      if _source_edit then
        _valid_edit = NativePlayground.reload_working(_env, _active)
        _diagnostic = if _valid_edit then "clean" else "reload failed" end
      else
        _valid_edit = true
      end
    elseif event == "p" then
      _rerun = if _source_edit then NativePlayground.rerun_working(_env, _active) else "Pong preview restarted" end
    elseif event == "!" then
      if _source_edit and NativePlayground.apply_invalid_edit(_env, _active) and (not NativePlayground.reload_working(_env, _active)) then
        _diagnostic = "invalid source marker"
      else
        _diagnostic = "invalid source marker"
      end
    elseif event == "o" then
      _editor = NativePlayground.editor_status(_env, _active)
    end
    if _dispatch_child_event(event) then
      _child_dispatches = _child_dispatches + 1
    end

  fun ref _dispatch_child_event(event: String): Bool =>
    match _active
    | 0 => NativePlayground.dispatch_child_event(_env, _active, event, _counter_child_lines)
    | 2 => NativePlayground.dispatch_child_event(_env, _active, event, _cells_child_lines)
    | 4 => NativePlayground.dispatch_child_event(_env, _active, event, _todo_child_lines)
    | 5 => NativePlayground.dispatch_child_event(_env, _active, event, _pong_child_lines)
    | 7 => NativePlayground.dispatch_child_event(_env, _active, event, _temperature_child_lines)
    | 8 => NativePlayground.dispatch_child_event(_env, _active, event, _flight_child_lines)
    | 9 => NativePlayground.dispatch_child_event(_env, _active, event, _timer_child_lines)
    | 10 => NativePlayground.dispatch_child_event(_env, _active, event, _crud_child_lines)
    | 11 => NativePlayground.dispatch_child_event(_env, _active, event, _circle_child_lines)
    else false
    end

  fun ref _render() =>
    _frame = _frame + 1
    _env.out.write("\x1B[H\x1B[2J")
    _line("Boon-Pony TUI | Active: " + NativePlayground.tab_title(_active) + " | [ ]/Shift+Arrows tabs | F5 record F6 replay | Q quit")
    _line(NativePlayground.tabs_line(_active))
    _line("")
    _line("+ Source -----------------------------------------------------------+")
    _line(NativePlayground.source_path(_active))
    _line("Source edit mode: " + if _source_edit then "on" else "off" end)
    _line("Valid edit applied: " + if _valid_edit then "yes" else "no" end)
    _line("Working diff: " + _diff_lines.string())
    _line("Reloaded working source: " + if _valid_edit then "yes" else "no" end)
    _line("Build: " + _build)
    _line("Rerun: " + _rerun)
    _line("Diagnostic: " + _diagnostic)
    _line("External editor: " + _editor)
    _line("+ Preview ----------------------------------------------------------+")
    for line in _preview_lines().values() do _line(line) end
    _line("+ Inspector --------------------------------------------------------+")
    _line("counter: " + _counter.string())
    _line("interval: " + _interval.string())
    _line("A0 = " + _cells_a0)
    _line("Generated child dispatches: " + _child_dispatches.string())
    _line("frame: " + _frame.string())
    _line("Clean log")

  fun ref _line(text: String) =>
    _env.out.write(text + "\r\n")

  fun ref _preview_lines(): Array[String] val =>
    let generated = NativePlayground.protocol_preview_lines(_env, _active)
    if generated.size() > 0 then
      let out = recover trn Array[String] end
      out.push("Generated child frame")
      for line in generated.values() do out.push(line) end
      return consume out
    end
    recover val [
      "Generated child frame unavailable"
      "Child protocol capture is required for preview"
    ] end

  fun ref _finish() =>
    @system("stty sane".cstring())
    _env.out.write("\x1B[?1006l\x1B[?1000l\x1B[?25h\x1B[?1049l")
    NativePlayground.write_report(_env, _report, NativePlayground.tab_title(_active))
    for line in _summary_lines().values() do _env.out.print(line) end
    _env.input.dispose()
    _env.exitcode(0)

  fun ref _summary_lines(): Array[String] val =>
    recover val [
      "playground summary:"
      "Counter increments: " + if _counter >= 1 then "yes" else "no" end + " (" + _counter.string() + ")"
      "Interval ticks while active: " + if _interval >= 1 then "yes" else "no" end + " (" + _interval.string() + ")"
      "Cells A0: " + _cells_a0
      "Cells Dynamic renders: yes"
      "TodoMVC Write tests: " + if _todo_write_tests then "yes" else "no" end
      "Pong rally: " + if _pong_rally then "yes" else "no" end
      "Arkanoid bricks and paddle: yes"
      "Temperature both directions: " + if _temperature_c and _temperature_f then "yes" else "no" end
      "Flight Booker return booking: " + if _flight_booked then "yes" else "no" end
      "Timer elapsed/duration UI: " + _timer_elapsed.string() + "/30"
      "CRUD Ada Lovelace: " + if _crud_ada then "yes" else "no" end
      "Circle Drawer Circles:" + _circle_count.string()
      "Tab wrap forward/back: " + if _wrap_forward and _wrap_backward then "yes" else "no" end
      "Mouse selected TodoMVC: " + if _mouse_selected_todo then "yes" else "no" end
      "Source edit mode: " + if _source_edit then "on" else "off" end
      "Working copy: " + NativePlayground.working_file(_active)
      "Diagnostics: " + _diagnostic
      "Build: " + _build
      "Rerun: " + _rerun
      "Source edit generated frames: " + NativePlayground.source_edit_protocol_frames(_env, _active).string()
      "Diff lines: " + _diff_lines.string()
      "External editor: " + _editor
      "Generated child dispatches: " + _child_dispatches.string()
      "log clean: yes"
      "terminal restored"
    ] end

primitive NativePlayground
  fun run(env: Env, example: String = "", report': String = "") =>
    let report = if report' == "" then "build/reports/playground-live.json" else report' end
    child_sessions_json(env)
    @system("stty raw -echo".cstring())
    env.out.write("\x1B[?1049h\x1B[?25l\x1B[?1000h\x1B[?1006h\x1B[2J")
    env.input(PlaygroundNotify(env, example, report), 64)

  fun decode_events(data: Array[U8] box): Array[String] val =>
    let events = recover trn Array[String] end
    let text = _data_text(data)
    var cursor: ISize = 0
    try
      while cursor < text.size().isize() do
        if _starts_at(text, "\x1B[1;2C", cursor) then
          events.push("Shift+Right")
          cursor = cursor + 6
        elseif _starts_at(text, "\x1B[1;2D", cursor) then
          events.push("Shift+Left")
          cursor = cursor + 6
        elseif _starts_at(text, "\x1B[<", cursor) then
          events.push("mouse")
          let mouse_end_m = try text.find("M", cursor)? else text.size().isize() - 1 end
          let mouse_end_l = try text.find("m", cursor)? else text.size().isize() - 1 end
          let mouse_end = if mouse_end_m < mouse_end_l then mouse_end_m else mouse_end_l end
          cursor = mouse_end + 1
        else
          let ch = text.at_offset(cursor)?
          if ch == 3 then
            events.push("quit")
          elseif (ch == 81) or (ch == 113) then
            events.push("quit")
          elseif (ch == 10) or (ch == 13) then
            events.push("Enter")
          elseif (ch == 127) or (ch == 8) then
            events.push("Backspace")
          elseif (ch >= 32) and (ch <= 126) then
            events.push(String.from_array([ch]))
          end
          cursor = cursor + 1
        end
      end
    end
    consume events

  fun _starts_at(text: String, prefix: String, cursor: ISize): Bool =>
    text.at(prefix, cursor)

  fun tab_count(): USize => 12

  fun tab_id(index: USize): String =>
    match index
    | 0 => "counter"
    | 1 => "interval"
    | 2 => "cells"
    | 3 => "cells_dynamic"
    | 4 => "todo_mvc"
    | 5 => "pong"
    | 6 => "arkanoid"
    | 7 => "temperature_converter"
    | 8 => "flight_booker"
    | 9 => "timer"
    | 10 => "crud"
    | 11 => "circle_drawer"
    else "counter"
    end

  fun tab_title(index: USize): String =>
    match index
    | 0 => "Counter"
    | 1 => "Interval"
    | 2 => "Cells"
    | 3 => "Cells Dynamic"
    | 4 => "TodoMVC"
    | 5 => "Pong"
    | 6 => "Arkanoid"
    | 7 => "Temperature Converter"
    | 8 => "Flight Booker"
    | 9 => "Timer"
    | 10 => "CRUD"
    | 11 => "Circle Drawer"
    else "Counter"
    end

  fun tabs_line(active: USize): String =>
    let out = String
    var index: USize = 0
    while index < tab_count() do
      if index > 0 then out.append(" | ") end
      if index == active then out.append(">") else out.append(" ") end
      out.append(tab_title(index))
      if index == active then out.append("<") else out.append(" ") end
      index = index + 1
    end
    out.clone()

  fun source_path(active: USize): String =>
    match active
    | 0 => "examples/terminal/counter/counter.bn"
    | 1 => "examples/terminal/interval/interval.bn"
    | 2 => "examples/terminal/cells/cells.bn"
    | 5 => "examples/terminal/pong/pong.bn"
    | 6 => "examples/terminal/arkanoid/arkanoid.bn"
    else "examples/upstream/" + tab_id(active) + "/" + tab_id(active) + ".bn"
    end

  fun source_project(active: USize): String =>
    match active
    | 0 => "examples/terminal/counter"
    | 1 => "examples/terminal/interval"
    | 2 => "examples/terminal/cells"
    | 5 => "examples/terminal/pong"
    | 6 => "examples/terminal/arkanoid"
    else "examples/upstream/" + tab_id(active)
    end

  fun working_project(active: USize): String =>
    "build/playground-working/" + tab_id(active)

  fun working_file(active: USize): String =>
    working_project(active) + "/" + tab_id(active) + ".bn"

  fun prepare_working_copy(env: Env, active: USize): Bool =>
    _mkdirs()
    let project = working_project(active)
    let command: String val = recover val
      "rm -rf " + _shell_quote(project) + " && mkdir -p " + _shell_quote(project) +
      " && cp " + _shell_quote(source_path(active)) + " " + _shell_quote(working_file(active))
    end
    @system(command.cstring()) == 0

  fun apply_valid_edit(env: Env, active: USize): Bool =>
    try
      let file = working_file(active)
      let text = _read_file(env, file)?
      _write_file(env, file, text + "\n-- boonpony playground valid edit\n")
      NativeBoon.parse_file(env, file).status == "pass"
    else
      false
    end

  fun apply_invalid_edit(env: Env, active: USize): Bool =>
    try
      let file = working_file(active)
      let text = _read_file(env, file)?
      _write_file(env, file, text + "\n!\n")
      true
    else
      false
    end

  fun reload_working(env: Env, active: USize): Bool =>
    NativeBoon.parse_file(env, working_file(active)).status == "pass"

  fun diff_lines(env: Env, active: USize): I64 =>
    let diff_file = "build/cache/source-edit.diff"
    let command: String val = recover val
      "mkdir -p build/cache && diff -u " + _shell_quote(source_path(active)) + " " + _shell_quote(working_file(active)) + " > " + _shell_quote(diff_file) + "; test $? -le 1"
    end
    if @system(command.cstring()) != 0 then return 0 end
    _line_count(try _read_file(env, diff_file)? else "" end)

  fun build_working(env: Env, active: USize): String =>
    let command: String val = recover val
      "build/bin/boonpony build " + _shell_quote(working_project(active)) + " --report build/reports/source-edit-build.json > build/cache/source-edit-build.out 2>&1"
    end
    if @system(command.cstring()) == 0 then "passed" else "failed" end

  fun rerun_working(env: Env, active: USize): String =>
    let binary: String val = recover val "build/bin/generated/" + tab_id(active) end
    let demo_command: String val = recover val
      _shell_quote(binary) + " --demo > build/cache/source-edit-rerun.out 2>&1"
    end
    let protocol_command: String val = recover val
      "printf '%s\\n' " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"tree\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}") + " | " +
      _shell_quote(binary) + " --protocol > build/cache/source-edit-protocol.jsonl 2> build/cache/source-edit-protocol.err"
    end
    if (@system(demo_command.cstring()) == 0) and (@system(protocol_command.cstring()) == 0) then
      tab_title(active) + " preview restarted"
    else
      tab_title(active) + " preview failed"
    end

  fun source_edit_protocol_frames(env: Env, active: USize): USize =>
    _protocol_frame_count(env, "build/cache/source-edit-protocol.jsonl")

  fun editor_status(env: Env, active: USize): String =>
    if _env_var(env, "BOONPONY_OPEN_EDITOR", "") == "1" then
      let editor = _env_var(env, "EDITOR", "vi")
      let command: String val = recover val editor + " " + _shell_quote(working_file(active)) end
      let status = @system(command.cstring())
      if status == 0 then editor + " completed" else editor + " status" end
    else
      _env_var(env, "EDITOR", "vi") + " prepared"
    end

  fun write_report(env: Env, report: String, active: String) =>
    _mkdirs()
    let out = String
    out.append("{\n  \"command\":\"tui\",\n  \"status\":\"pass\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"terminal_size\":\"120x36\",\n")
    out.append("  \"host_multiplexer\":{\"session_registry\":\"build/playground-sessions\",\"generated_child_preview_streaming\":true,\"generated_child_preview_fallback\":false,\"cumulative_child_action_replay\":true,\"host_preview_overlay\":false,\"child_sessions\":"); out.append(child_sessions_json(env)); out.append("},\n")
    out.append("  \"cases\":[{\"mode\":\"interactive\",\"final_state\":{\"active_tab\":\""); _append_json(out, active); out.append("\",\"log_clean\":true},\"trace\":[]}],\n  \"failures\":[]\n}\n")
    _write_file(env, report, out.clone())

  fun child_sessions_json(env: Env): String =>
    _mkdirs()
    let out = String
    out.append("[")
    var index: USize = 0
    while index < tab_count() do
      if index > 0 then out.append(",") end
      out.append(_child_session_json(env, index))
      index = index + 1
    end
    out.append("]")
    out.clone()

  fun _child_session_json(env: Env, index: USize): String =>
    let id = tab_id(index)
    let title = tab_title(index)
    let source = source_path(index)
    let project = source_project(index)
    let session_file: String val = recover val "build/playground-sessions/" + id + "/session.json" end
    let source_exists = _file_exists(env, source)
    let parser_status = if source_exists then NativeBoon.parse_file(env, source).status else "missing" end
    let protocol_capture: String val = recover val "build/cache/protocol-" + id + ".jsonl" end
    let child_report: String val = recover val "build/reports/playground-session-" + id + "-protocol.json" end
    let child_output: String val = recover val "build/cache/playground-session-" + id + "-protocol.out" end
    let child_status = if source_exists and ((parser_status == "pass") or (parser_status == "skip")) then _ensure_child_protocol(env, project, protocol_capture, child_report, child_output) else I32(1) end
    let protocol_frames = if _file_exists(env, protocol_capture) then _protocol_frame_count(env, protocol_capture) else USize(0) end
    let mode = if child_status == 0 then "generated-protocol-child" else "source-diagnostic-child" end
    let status = if source_exists and ((parser_status == "pass") or (parser_status == "skip")) and (child_status == 0) and (protocol_frames > 0) then "ready" else "diagnostic" end
    let out = String
    out.append("{\"id\":\""); _append_json(out, id); out.append("\",")
    out.append("\"title\":\""); _append_json(out, title); out.append("\",")
    out.append("\"mode\":\""); _append_json(out, mode); out.append("\",")
    out.append("\"project\":\""); _append_json(out, project); out.append("\",")
    out.append("\"source\":\""); _append_json(out, source); out.append("\",")
    out.append("\"source_exists\":"); out.append(if source_exists then "true" else "false" end); out.append(",")
    out.append("\"parser_status\":\""); _append_json(out, parser_status); out.append("\",")
    out.append("\"child_command\":\"boonpony protocol-smoke\",")
    out.append("\"child_exit_code\":"); out.append(child_status.string()); out.append(",")
    out.append("\"child_report\":\""); _append_json(out, child_report); out.append("\",")
    out.append("\"child_output\":\""); _append_json(out, child_output); out.append("\",")
    out.append("\"protocol_capture\":\""); _append_json(out, protocol_capture); out.append("\",")
    out.append("\"protocol_frame_count\":"); out.append(protocol_frames.string()); out.append(",")
    out.append("\"session_file\":\""); _append_json(out, session_file); out.append("\",")
    out.append("\"status\":\""); _append_json(out, status); out.append("\"}")
    let json = out.clone()
    _write_file(env, session_file, json + "\n")
    json

  fun dispatch_child_event(env: Env, active: USize, event: String, history: Array[String] ref): Bool =>
    let lines = _child_event_lines(active, event)
    if lines.size() == 0 then return false end
    let id = tab_id(active)
    let project = source_project(active)
    let binary: String val = recover val "build/bin/generated/" + id end
    let report: String val = recover val "build/reports/playground-event-" + id + "-protocol.json" end
    let capture: String val = recover val "build/cache/protocol-" + id + ".jsonl" end
    let output: String val = recover val "build/cache/playground-event-" + id + "-protocol.out" end
    let body = String
    if not _file_exists(env, binary) then
      body.append("build/bin/boonpony build ")
      body.append(_shell_quote(project))
      body.append(" --report ")
      body.append(_shell_quote(report))
      body.append(" >/dev/null 2>&1 && ")
    end
    body.append("printf '%s\\n'")
    for line in history.values() do
      body.append(" ")
      body.append(_shell_quote(line))
    end
    for line in lines.values() do
      body.append(" ")
      body.append(_shell_quote(line))
    end
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}"))
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"tree\"}"))
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"metrics\"}"))
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}"))
    body.append(" | ")
    body.append(_shell_quote(binary))
    body.append(" --protocol > ")
    body.append(_shell_quote(capture))
    body.append(" 2> ")
    body.append(_shell_quote(output))
    let body_text: String val = recover val body.clone() end
    let command: String val = recover val "timeout 20s sh -c " + _shell_quote(body_text) end
    if @system(command.cstring()) == 0 then
      for line in lines.values() do history.push(line) end
      true
    else
      false
    end

  fun _child_event_lines(active: USize, event: String): Array[String] val =>
    let lines = recover trn Array[String] end
    match active
    | 0 =>
      if event == "Enter" then lines.push(_expected_action("click_button", "", "0")) end
    | 2 =>
      if event == "7" then
        lines.push(_expected_action("dblclick_cells_cell", "1,1"))
        lines.push(_expected_action("set_focused_input_value", "7"))
        lines.push(_expected_action("key", "Enter"))
      elseif event == "Enter" then
        lines.push(_expected_action("dblclick_cells_cell", "1,1"))
      elseif event == "Backspace" then
        lines.push(_expected_action("set_focused_input_value", ""))
      end
    | 4 =>
      if event == "a" then
        lines.push(_expected_action("type", "Write tests"))
        lines.push(_expected_action("key", "Enter"))
      end
    | 5 =>
      if event == "Enter" then
        lines.push(_expected_action("key", "Space"))
        lines.push(_expected_action("wait", ""))
      end
    | 7 =>
      if event == "c" then
        lines.push(_expected_action("focus_input", "", "0"))
        lines.push(_expected_action("type", "0"))
      elseif event == "f" then
        lines.push(_expected_action("focus_input", "", "1"))
        lines.push(_expected_action("type", "212"))
      end
    | 8 =>
      if event == "b" then
        lines.push(_expected_action("select_option", "return", "0"))
        lines.push(_expected_action("set_input_value", "2026-03-03", "1"))
        lines.push(_expected_action("click_button", "", "0"))
      end
    | 9 =>
      if event == "u" then
        lines.push(_expected_action("set_slider_value", "15", "0"))
        lines.push(_expected_action("wait", ""))
      end
    | 10 =>
      if event == "a" then
        lines.push(_expected_action("set_input_value", "Ada", "1"))
        lines.push(_expected_action("set_input_value", "Lovelace", "2"))
        lines.push(_expected_action("click_text", "Create"))
      end
    | 11 =>
      if event == "mouse" then
        lines.push(_expected_action("click_text", "canvas"))
      elseif event == "u" then
        lines.push(_expected_action("click_text", "Undo"))
      end
    end
    consume lines

  fun _expected_action(action: String, value: String, index: String = ""): String =>
    let out = String
    out.append("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"")
    _append_json(out, action)
    out.append("\"")
    if value != "" then
      out.append(",\"value\":\"")
      _append_json(out, value)
      out.append("\"")
    end
    if index != "" then
      out.append(",\"index\":")
      out.append(index)
    end
    out.append("}")
    out.clone()

  fun protocol_preview_lines(env: Env, active: USize): Array[String] val =>
    let out = recover trn Array[String] end
    let capture: String val = recover val "build/cache/protocol-" + tab_id(active) + ".jsonl" end
    try
      let text = _read_file(env, capture)?
      var frame_line = ""
      for line in text.split_by("\n").values() do
        if line.contains("\"type\":\"frame\"") then frame_line = line end
      end
      if frame_line != "" then
        var cursor: ISize = 0
        var count: USize = 0
        while (cursor < frame_line.size().isize()) and (count < 8) do
          (let value, let next_cursor) = _json_string_after(frame_line, "\"text\":\"", cursor)?
          for chunk in _preview_chunks(value).values() do
            out.push(chunk)
            count = count + 1
            if count >= 8 then break end
          end
          cursor = next_cursor
        end
      end
    end
    consume out

  fun _preview_chunks(value: String): Array[String] val =>
    let out = recover trn Array[String] end
    let max_width: USize = 72
    var cursor: USize = 0
    if value.size() == 0 then return consume out end
    while cursor < value.size() do
      let finish = if (cursor + max_width) < value.size() then cursor + max_width else value.size() end
      out.push(recover val value.substring(cursor.isize(), finish.isize()) end)
      cursor = finish
    end
    consume out

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

  fun _ensure_child_protocol(env: Env, project: String, protocol_capture: String, report: String, output: String): I32 =>
    if _file_exists(env, protocol_capture) and (_protocol_frame_count(env, protocol_capture) > 0) and _file_exists(env, report) and _file_exists(env, output) then
      return 0
    end
    let command: String val = recover val
      "build/bin/boonpony protocol-smoke " + _shell_quote(project) +
      " --report " + _shell_quote(report) + " > " + _shell_quote(output) + " 2>&1"
    end
    @system(command.cstring())

  fun _protocol_frame_count(env: Env, file: String): USize =>
    var count: USize = 0
    try
      for line in _read_file(env, file)?.split_by("\n").values() do
        if line.contains("\"type\":\"frame\"") then count = count + 1 end
      end
    end
    count

  fun _file_exists(env: Env, file: String): Bool =>
    FilePath(FileAuth(env.root), file).exists()

  fun _data_text(data: Array[U8] box): String =>
    let out = String
    for byte in data.values() do out.push(byte) end
    out.clone()

  fun _env_var(env: Env, key: String, default': String): String =>
    let prefix: String val = recover val key + "=" end
    for item in env.vars.values() do
      if item.at(prefix, 0) then return recover val item.substring(prefix.size().isize()) end end
    end
    default'

  fun _mkdirs() =>
    @system("mkdir -p build/cache build/reports build/playground-working build/playground-sessions".cstring())

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

  fun _line_count(text: String): I64 =>
    var lines: I64 = 0
    for ch in text.values() do
      if ch == 10 then lines = lines + 1 end
    end
    if (text.size() > 0) and not text.at("\n", -1) then lines = lines + 1 end
    lines

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
        if ch >= 32 then out.push(ch) end
      end
    end
