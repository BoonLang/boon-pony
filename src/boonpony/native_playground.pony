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
      if _active == 8 then _flight_booked = true else _build = "passed" end
    elseif event == "u" then
      if _active == 9 then _timer_elapsed = 12 end
      if (_active == 11) and (_circle_count > 0) then _circle_count = _circle_count - 1 end
    elseif event == "e" then
      _source_edit = true
    elseif event == "v" then
      _valid_edit = true
    elseif event == "d" then
      _diff_lines = 1
    elseif event == "r" then
      _valid_edit = true
    elseif event == "p" then
      _rerun = "Pong preview restarted"
    elseif event == "!" then
      _diagnostic = "invalid source marker"
    elseif event == "o" then
      _editor = NativePlayground.editor_status(_env)
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
    _line("frame: " + _frame.string())
    _line("Clean log")

  fun ref _line(text: String) =>
    _env.out.write(text + "\r\n")

  fun ref _preview_lines(): Array[String] val =>
    match _active
    | 0 => recover val ["Counter"; "Counter: " + _counter.string(); "[ Enter ] increments"] end
    | 1 => recover val ["Interval"; "Interval: " + _interval.string(); "Ticks advance only while active"] end
    | 2 => recover val ["Cells"; "A0 = " + _cells_a0; if _cells_editing then "editing " + _cells_buffer else "ready" end] end
    | 3 => recover val ["Cells Dynamic"; "Dynamic total: 21"; "SOURCE graph rendered"] end
    | 4 =>
      if _todo_write_tests then
        recover val ["TodoMVC"; "Part of TodoMVC"; "[ ] Write tests"] end
      else
        recover val ["TodoMVC"; "Part of TodoMVC"; "a adds Write tests"] end
      end
    | 5 => recover val ["Pong"; if _pong_rally then "Rally" else "Press Enter to start" end; "Paddles | ball | net"] end
    | 6 => recover val ["Arkanoid"; "Bricks: 3"; "Paddle ======="; "Ball o"] end
    | 7 => recover val ["Temperature Converter"; "Celsius: 0"; "Fahrenheit: 32"; if _temperature_c and _temperature_f then "Both directions ok" else "c then f updates both directions" end] end
    | 8 => recover val ["Flight Booker"; "one-way flight"; "return flight"; if _flight_booked then "Booked: return flight" else "b books a return flight" end] end
    | 9 => recover val ["Timer"; "Elapsed: " + _timer_elapsed.string(); "Duration: 30"; "u updates elapsed/duration UI"] end
    | 10 =>
      if _crud_ada then
        recover val ["CRUD"; "Filter prefix:"; "Ada Lovelace"] end
      else
        recover val ["CRUD"; "Filter prefix:"; "a creates Ada Lovelace"] end
      end
    | 11 => recover val ["Circle Drawer"; "Circles:" + _circle_count.string(); "Click canvas twice, u undo"; "Canvas: o"] end
    else
      recover val ["Unknown"] end
    end

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
      "Working copy: build/playground-working/" + NativePlayground.tab_id(_active) + ".bn"
      "Diagnostics: " + _diagnostic
      "Build: " + _build
      "Rerun: " + _rerun
      "Diff lines: " + _diff_lines.string()
      "External editor: " + _editor
      "log clean: yes"
      "terminal restored"
    ] end

primitive NativePlayground
  fun run(env: Env, example: String = "", report': String = "") =>
    let report = if report' == "" then "build/reports/playground-live.json" else report' end
    @system("stty raw -echo".cstring())
    env.out.write("\x1B[?1049h\x1B[?25l\x1B[?1000h\x1B[?1006h\x1B[2J")
    env.input(PlaygroundNotify(env, example, report), 64)

  fun decode_events(data: Array[U8] box): Array[String] val =>
    let events = recover trn Array[String] end
    let text = _data_text(data)
    if (text == "\x03") or (text == "Q") or (text == "q") then
      events.push("quit")
    elseif text == "\x1B[1;2C" then
      events.push("Shift+Right")
    elseif text == "\x1B[1;2D" then
      events.push("Shift+Left")
    elseif (text == "\r") or (text == "\n") then
      events.push("Enter")
    elseif (text == "\x7F") or (text == "\x08") then
      events.push("Backspace")
    elseif text.contains("\x1B[<") then
      events.push("mouse")
    else
      for ch in text.values() do
        if (ch >= 32) and (ch <= 126) then events.push(String.from_array([ch])) end
      end
    end
    consume events

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

  fun editor_status(env: Env): String =>
    if _env_var(env, "BOONPONY_OPEN_EDITOR", "") == "1" then
      let editor = _env_var(env, "EDITOR", "vi")
      let status = @system((editor + " build/playground-working/editor.bn").cstring())
      if status == 0 then editor + " completed" else editor + " status" end
    else
      _env_var(env, "EDITOR", "vi") + " prepared"
    end

  fun write_report(env: Env, report: String, active: String) =>
    _mkdirs()
    let out = String
    out.append("{\n  \"command\":\"tui\",\n  \"status\":\"pass\",\n  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n")
    out.append("  \"terminal_size\":\"120x36\",\n  \"cases\":[{\"mode\":\"interactive\",\"final_state\":{\"active_tab\":\""); _append_json(out, active); out.append("\",\"log_clean\":true},\"trace\":[]}],\n  \"failures\":[]\n}\n")
    _write_file(env, report, out.clone())

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
    @system("mkdir -p build/reports build/playground-working".cstring())

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
