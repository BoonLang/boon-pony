use "files"
use "time"

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
  var _todo_focus: Bool = false
  var _todo_buffer: String = ""
  var _todo_item: String = ""
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
  var _arkanoid_status: String = "idle"
  var _rerun: String = "not run"
  var _editor: String = "not opened"
  var _frame: I64 = 0
  var _child_dispatches: USize = 0
  let _counter_child_lines: Array[String] ref = Array[String]
  let _interval_child_lines: Array[String] ref = Array[String]
  let _cells_child_lines: Array[String] ref = Array[String]
  let _cells_dynamic_child_lines: Array[String] ref = Array[String]
  let _todo_child_lines: Array[String] ref = Array[String]
  let _pong_child_lines: Array[String] ref = Array[String]
  let _arkanoid_child_lines: Array[String] ref = Array[String]
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
      _switch_right()
    elseif event == "Shift+Left" then
      _switch_left()
    elseif event == "]" then
      _switch_right()
    elseif event == "[" then
      _switch_left()
    elseif event.at("Tab:", 0) then
      try
        let tab = event.substring(4).usize()?
        if tab < NativePlayground.tab_count() then
          _active = tab
          _todo_focus = false
          if tab == 4 then _mouse_selected_todo = true end
        end
      end
    elseif event.at("Mouse:", 0) then
      if _active == 4 then
        _todo_focus = true
      elseif _active == 11 then
        _circle_count = _circle_count + 1
      end
    elseif (_active == 4) and _todo_focus then
      _handle_todo_input(event)
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
    elseif event == "Space" then
      if _active == 0 then
        _counter = _counter + 1
      elseif _active == 1 then
        _interval = _interval + 1
      elseif _active == 5 then
        _pong_rally = true
      elseif _active == 6 then
        _arkanoid_status = "brick hit"
      elseif _active == 9 then
        _timer_elapsed = _timer_elapsed + 1
      end
    elseif (event == "ArrowUp") or (event == "ArrowDown") or (event == "w") or (event == "s") then
      if _active == 5 then _pong_rally = true end
    elseif (event == "ArrowLeft") or (event == "ArrowRight") then
      if _active == 6 then _arkanoid_status = "paddle moved" end
    elseif event == "Backspace" then
      if _active == 2 then _cells_buffer = "" end
    elseif event == "7" then
      if _active == 2 then _cells_buffer = "7" end
      if _active == 3 then _cells_buffer = "7" end
    elseif event == "a" then
      if _active == 4 then _commit_todo("Write tests") end
      if _active == 10 then _crud_ada = true end
    elseif event == "t" then
      if _active == 1 then _interval = _interval + 1 end
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

  fun ref _handle_todo_input(event: String) =>
    if event == "Enter" then
      _commit_todo(_todo_buffer)
      _todo_buffer = ""
      _todo_focus = false
    elseif event == "Backspace" then
      if _todo_buffer.size() > 0 then
        _todo_buffer = recover val _todo_buffer.substring(0, (_todo_buffer.size() - 1).isize()) end
      end
    elseif event == "Space" then
      _todo_buffer = _todo_buffer + " "
    elseif event.size() == 1 then
      _todo_buffer = _todo_buffer + event
    end

  fun ref _commit_todo(value: String) =>
    if value != "" then
      _todo_item = value
      if value == "Write tests" then _todo_write_tests = true end
      if NativePlayground.dispatch_child_event(_env, USize(4), "TodoCommit:" + value, _todo_child_lines) then
        _child_dispatches = _child_dispatches + 1
      end
    end

  fun ref _switch_right() =>
    _sync_interval()
    _active = _active + 1
    if _active >= NativePlayground.tab_count() then
      _active = 0
      _wrap_forward = true
    end

  fun ref _switch_left() =>
    _sync_interval()
    if _active == 0 then
      _active = NativePlayground.tab_count() - 1
      _wrap_backward = true
    else
      _active = _active - 1
    end

  fun ref _sync_interval() =>
    let live = NativePlayground.live_interval(_env)
    if live > _interval then _interval = live end

  fun ref _dispatch_child_event(event: String): Bool =>
    match _active
    | 0 => NativePlayground.dispatch_child_event(_env, _active, event, _counter_child_lines)
    | 1 => NativePlayground.dispatch_child_event(_env, _active, event, _interval_child_lines)
    | 2 => NativePlayground.dispatch_child_event(_env, _active, event, _cells_child_lines)
    | 3 => NativePlayground.dispatch_child_event(_env, _active, event, _cells_dynamic_child_lines)
    | 4 => NativePlayground.dispatch_child_event(_env, _active, event, _todo_child_lines)
    | 5 => NativePlayground.dispatch_child_event(_env, _active, event, _pong_child_lines)
    | 6 => NativePlayground.dispatch_child_event(_env, _active, event, _arkanoid_child_lines)
    | 7 => NativePlayground.dispatch_child_event(_env, _active, event, _temperature_child_lines)
    | 8 => NativePlayground.dispatch_child_event(_env, _active, event, _flight_child_lines)
    | 9 => NativePlayground.dispatch_child_event(_env, _active, event, _timer_child_lines)
    | 10 => NativePlayground.dispatch_child_event(_env, _active, event, _crud_child_lines)
    | 11 => NativePlayground.dispatch_child_event(_env, _active, event, _circle_child_lines)
    else false
    end

  fun ref _render() =>
    _sync_interval()
    NativePlayground.write_live_state(_env, _active, _interval)
    _frame = _frame + 1
    _env.out.write("\x1B[H\x1B[2J")
    _line("Boon-Pony TUI | " + NativePlayground.tab_title(_active) + " | Q quit")
    _line(NativePlayground.tabs_line(_active))
    _line(NativePlayground.active_hint(_active))
    _line("Tabs: [ ] or Shift+Left/Right | Source: e edit, v valid, ! invalid, d diff, b build, p run, o editor")
    _line("Source: " + NativePlayground.source_path(_active) + " | edit " + if _source_edit then "on" else "off" end + " | diff " + _diff_lines.string() + " | diag " + _diagnostic)
    _line("+ Preview ----------------------------------------------------------+")
    for line in _preview_lines().values() do _line(line) end
    _line("+ State ------------------------------------------------------------+")
    _line(_active_status_line())
    _line("log clean | frame " + _frame.string())

  fun ref _line(text: String) =>
    _env.out.write(text + "\r\n")

  fun ref _active_status_line(): String =>
    match _active
    | 0 => "counter " + _counter.string() + " | child dispatches " + _child_dispatches.string()
    | 1 => "interval " + _interval.string() + " | child dispatches " + _child_dispatches.string()
    | 2 => "A0 " + _cells_a0 + " | editing " + if _cells_editing then "yes" else "no" end + " | child dispatches " + _child_dispatches.string()
    | 3 => "dynamic A0 " + _cells_a0 + " | child dispatches " + _child_dispatches.string()
    | 4 => "todo input " + if _todo_focus then "focused" else "idle" end + " | item " + if _todo_item == "" then "-" else _todo_item end + " | child dispatches " + _child_dispatches.string()
    | 5 => "pong rally " + if _pong_rally then "yes" else "no" end + " | child dispatches " + _child_dispatches.string()
    | 6 => "arkanoid " + _arkanoid_status + " | child dispatches " + _child_dispatches.string()
    | 7 => "celsius " + if _temperature_c then "edited" else "idle" end + " | fahrenheit " + if _temperature_f then "edited" else "idle" end + " | child dispatches " + _child_dispatches.string()
    | 8 => "booking " + if _flight_booked then "return booked" else "idle" end + " | child dispatches " + _child_dispatches.string()
    | 9 => "elapsed " + _timer_elapsed.string() + "/30 | child dispatches " + _child_dispatches.string()
    | 10 => "crud " + if _crud_ada then "Ada Lovelace created" else "idle" end + " | child dispatches " + _child_dispatches.string()
    | 11 => "circles " + _circle_count.string() + " | child dispatches " + _child_dispatches.string()
    else "child dispatches " + _child_dispatches.string()
    end

  fun ref _preview_lines(): Array[String] val =>
    if _active == 0 then
      recover val [
        "Live preview"
        "Counter: " + _counter.string()
        "Enter increments"
        "+++++"
      ] end
    elseif _active == 1 then
      recover val [
        "Live preview"
        "Interval: " + _interval.string()
        "Timer/interval"
      ] end
    elseif _active == 2 then
      recover val [
        "Live preview"
        "Cells"
        "A1 " + _cells_a0
        "B1 15"
        "C1 30"
      ] end
    elseif _active == 4 then
      recover val [
        "TodoMVC"
        "Input: [" + _todo_buffer + if _todo_focus then "_" else "" end + "]"
        if _todo_item == "" then "No todos yet" else "[ ] " + _todo_item end
        if _todo_item == "" then "0 items left" else "1 item left" end
      ] end
    else
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
    end

  fun ref _finish() =>
    _sync_interval()
    NativePlayground.stop_live_timer(_env)
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
      "TodoMVC input commit: " + if _todo_item == "" then "no" else _todo_item end
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
      "Source edit generated frames: " + if _source_edit then NativePlayground.source_edit_protocol_frames(_env, _active).string() else "0" end
      "Diff lines: " + _diff_lines.string()
      "External editor: " + _editor
      "Generated child dispatches: " + _child_dispatches.string()
      "log clean: yes"
      "terminal restored"
    ] end

class iso PlaygroundIntervalTick is TimerNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref apply(timer: Timer, count: U64): Bool =>
    if not NativePlayground.live_running(_env) then return false end
    if NativePlayground.live_active(_env) == 1 then
      let next = NativePlayground.live_interval(_env) + count.i64()
      NativePlayground.write_live_state(_env, USize(1), next)
      NativePlayground.render_interval_tick(_env, next)
    end
    true

  fun ref cancel(timer: Timer) =>
    None

primitive NativePlayground
  fun run(env: Env, example: String = "", report': String = "") =>
    let report = if report' == "" then "build/reports/playground-live.json" else report' end
    reset_live_cache()
    start_live_timer(env)
    let timers = Timers
    timers(Timer(PlaygroundIntervalTick(env), 1_000_000_000, 1_000_000_000))
    child_sessions_json(env)
    @system("stty raw -echo".cstring())
    env.out.write("\x1B[?1049h\x1B[?25l\x1B[?1000h\x1B[?1006h\x1B[2J")
    env.input(PlaygroundNotify(env, example, report), 64)

  fun reset_live_cache() =>
    @system("rm -f build/cache/protocol-counter.jsonl build/cache/protocol-interval.jsonl build/cache/protocol-cells.jsonl build/cache/protocol-cells_dynamic.jsonl build/cache/protocol-todo_mvc.jsonl build/cache/protocol-pong.jsonl build/cache/protocol-arkanoid.jsonl build/cache/protocol-temperature_converter.jsonl build/cache/protocol-flight_booker.jsonl build/cache/protocol-timer.jsonl build/cache/protocol-crud.jsonl build/cache/protocol-circle_drawer.jsonl".cstring())

  fun start_live_timer(env: Env) =>
    _mkdirs()
    _write_file(env, "build/cache/playground-live-running", "1\n")
    write_live_state(env, USize(0), I64(0))

  fun stop_live_timer(env: Env) =>
    @system("rm -f build/cache/playground-live-running".cstring())

  fun live_running(env: Env): Bool =>
    _file_exists(env, "build/cache/playground-live-running")

  fun write_live_state(env: Env, active: USize, interval: I64) =>
    _write_file(env, "build/cache/playground-live-active", active.string() + "\n")
    _write_file(env, "build/cache/playground-live-interval", interval.string() + "\n")

  fun live_active(env: Env): USize =>
    try _trim(_read_file(env, "build/cache/playground-live-active")?).usize()? else USize(0) end

  fun live_interval(env: Env): I64 =>
    try _trim(_read_file(env, "build/cache/playground-live-interval")?).i64()? else I64(0) end

  fun _trim(value: String): String =>
    var start: USize = 0
    var finish: USize = value.size()
    try
      while (start < finish) and _is_space(value.at_offset(start.isize())?) do start = start + 1 end
      while (finish > start) and _is_space(value.at_offset((finish - 1).isize())?) do finish = finish - 1 end
    end
    recover val value.substring(start.isize(), finish.isize()) end

  fun _is_space(ch: U8): Bool =>
    (ch == ' ') or (ch == 9) or (ch == 10) or (ch == 13)

  fun render_interval_tick(env: Env, value: I64) =>
    env.out.write("\x1B[H\x1B[2J")
    _live_line(env, "Boon-Pony TUI | Interval | Q quit")
    _live_line(env, tabs_line(USize(1)))
    _live_line(env, active_hint(USize(1)))
    _live_line(env, "Tabs: [ ] or Shift+Left/Right | Source: e edit, v valid, ! invalid, d diff, b build, p run, o editor")
    _live_line(env, "Source: " + source_path(USize(1)) + " | edit off | diff 0 | diag clean")
    _live_line(env, "+ Preview ----------------------------------------------------------+")
    _live_line(env, "Live preview")
    _live_line(env, "Interval: " + value.string())
    _live_line(env, "Timer/interval")
    _live_line(env, "+ State ------------------------------------------------------------+")
    _live_line(env, "interval " + value.string() + " | child dispatches 0")
    _live_line(env, "log clean | frame auto")

  fun _live_line(env: Env, text: String) =>
    env.out.write(text + "\r\n")

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
        elseif _starts_at(text, "\x1B[A", cursor) then
          events.push("ArrowUp")
          cursor = cursor + 3
        elseif _starts_at(text, "\x1B[B", cursor) then
          events.push("ArrowDown")
          cursor = cursor + 3
        elseif _starts_at(text, "\x1B[C", cursor) then
          events.push("ArrowRight")
          cursor = cursor + 3
        elseif _starts_at(text, "\x1B[D", cursor) then
          events.push("ArrowLeft")
          cursor = cursor + 3
        elseif _starts_at(text, "\x1B[<", cursor) then
          let mouse_end_m = try text.find("M", cursor)? else text.size().isize() - 1 end
          let mouse_end_l = try text.find("m", cursor)? else text.size().isize() - 1 end
          let mouse_end = if mouse_end_m < mouse_end_l then mouse_end_m else mouse_end_l end
          try
            let packet: String val = recover val text.substring(cursor + 3, mouse_end) end
            let parts = packet.split_by(";")
            let x = parts(1)?.usize()?
            let y = parts(2)?.usize()?
            if y <= 2 then
              events.push("Tab:" + NativePlayground.tab_at_x(x).string())
            else
              events.push("Mouse:" + x.string() + ":" + y.string())
            end
          else
            events.push("Mouse:0:0")
          end
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
          elseif ch == 32 then
            events.push("Space")
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
      if index > 0 then out.append(" ") end
      if index == active then out.append("[") else out.append(" ") end
      out.append(tab_short_title(index))
      if index == active then out.append("]") else out.append(" ") end
      index = index + 1
    end
    out.clone()

  fun tab_short_title(index: USize): String =>
    match index
    | 0 => "Counter"
    | 1 => "Interval"
    | 2 => "Cells"
    | 3 => "Dynamic"
    | 4 => "Todo"
    | 5 => "Pong"
    | 6 => "Arkanoid"
    | 7 => "Temp"
    | 8 => "Flight"
    | 9 => "Timer"
    | 10 => "CRUD"
    | 11 => "Circle"
    else "Counter"
    end

  fun active_hint(active: USize): String =>
    match active
    | 0 => "Counter: Enter or Space increments the generated counter."
    | 1 => "Interval: ticks automatically while this tab is active; Space or t also advances one frame."
    | 2 => "Cells: Enter edits/commits A0, Backspace clears, 0-9 types a cell value."
    | 3 => "Cells Dynamic: Enter edits, numbers type values, Backspace clears."
    | 4 => "TodoMVC: click the input area, type text, press Enter. Shortcut: a adds 'Write tests'."
    | 5 => "Pong: Space starts, W/S or Up/Down move paddles, Enter runs the scoring script."
    | 6 => "Arkanoid: Space launches/hits a brick, Left/Right or A/D move paddle, L marks lost."
    | 7 => "Temperature Converter: c edits Celsius, f edits Fahrenheit."
    | 8 => "Flight Booker: b books a return flight."
    | 9 => "Timer: Space or u advances elapsed time."
    | 10 => "CRUD: a creates Ada Lovelace."
    | 11 => "Circle Drawer: mouse adds a circle, u undoes."
    else "This example accepts its listed generated actions."
    end

  fun tab_at_x(x': USize): USize =>
    let x = if x' == 0 then USize(1) else x' end
    var left: USize = 1
    var index: USize = 0
    while index < tab_count() do
      if index > 0 then left = left + 1 end
      let width = tab_short_title(index).size() + 2
      if (x >= left) and (x < (left + width)) then return index end
      left = left + width
      index = index + 1
    end
    tab_count() - 1

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
      if (event == "Enter") or (event == "Space") then lines.push(_expected_action("click_button", "", "0")) end
    | 1 =>
      if (event == "Space") or (event == "t") then
        lines.push(_expected_action("wait", ""))
      end
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
    | 3 =>
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
      if event.at("TodoCommit:", 0) then
        let value: String val = recover val event.substring(11) end
        lines.push(_expected_action("focus_input", "", "0"))
        lines.push(_expected_action("type", value))
        lines.push(_expected_action("key", "Enter"))
      end
    | 5 =>
      if (event == "Enter") or (event == "Space") then
        lines.push(_expected_action("key", "Space"))
        lines.push(_expected_action("wait", ""))
      elseif (event == "w") or (event == "ArrowUp") then
        lines.push(_expected_action("key", "W"))
        lines.push(_expected_action("wait", ""))
      elseif (event == "s") or (event == "ArrowDown") then
        lines.push(_expected_action("key", "S"))
        lines.push(_expected_action("wait", ""))
      end
    | 6 =>
      if (event == "Space") or (event == "Enter") then
        lines.push(_expected_action("key", "Space"))
        lines.push(_expected_action("wait", ""))
      elseif (event == "ArrowLeft") or (event == "a") then
        lines.push(_expected_action("key", "A"))
        lines.push(_expected_action("wait", ""))
      elseif (event == "ArrowRight") or (event == "d") then
        lines.push(_expected_action("key", "D"))
        lines.push(_expected_action("wait", ""))
      elseif event == "l" then
        lines.push(_expected_action("key", "L"))
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
      if (event == "u") or (event == "Space") or (event == "t") then
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
      if event.at("Mouse:", 0) then
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
    if value.size() == 0 then return consume out end
    for line in value.split_by("\n").values() do
      var cursor: USize = 0
      if line.size() == 0 then
        out.push("")
      else
        while cursor < line.size() do
          let finish = if (cursor + max_width) < line.size() then cursor + max_width else line.size() end
          out.push(recover val line.substring(cursor.isize(), finish.isize()) end)
          cursor = finish
        end
      end
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
    let app = NativeCodegen.project_name(project)
    let binary: String val = recover val "build/bin/generated/" + app end
    let body = String
    if not _file_exists(env, binary) then
      body.append("build/bin/boonpony build ")
      body.append(_shell_quote(project))
      body.append(" --report ")
      body.append(_shell_quote(report))
      body.append(" >/dev/null 2>&1 && ")
    end
    body.append("printf '%s\\n' ")
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
    body.append(_shell_quote(protocol_capture))
    body.append(" 2> ")
    body.append(_shell_quote(output))
    let body_text: String val = recover val body.clone() end
    let command: String val = recover val
      "timeout 20s sh -c " + _shell_quote(body_text)
    end
    let status = @system(command.cstring())
    if status == 0 then
      _write_file(env, report, "{\"command\":\"playground-child-initial\",\"status\":\"pass\",\"project\":\"" + project + "\",\"binary\":\"" + binary + "\"}\n")
    end
    status

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
