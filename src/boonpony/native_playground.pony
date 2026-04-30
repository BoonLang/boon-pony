use "files"
use "time"

class iso PlaygroundTickNotify is TimerNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref apply(timer: Timer, count: U64): Bool =>
    if not NativePlayground.timer_should_continue(_env) then return false end
    NativePlayground.auto_tick(_env)
    true

class iso PlaygroundNotify is InputNotify
  let _env: Env
  let _report: String
  var _active: USize = 0
  var _source_edit: Bool = false
  var _valid_edit: Bool = false
  var _diff_lines: I64 = 0
  var _diagnostic: String = "clean"
  var _build: String = "not run"
  var _rerun: String = "not run"
  var _editor: String = "not opened"
  var _frame: I64 = 0
  var _source_scroll: USize = 0
  var _preview_scroll: USize = 0
  var _child_dispatches: USize = 0
  var _wrap_forward: Bool = false
  var _wrap_backward: Bool = false
  var _mouse_selected_example: Bool = false
  var _text_capture: Bool = false
  var _text_edit: Bool = false
  var _text_buffer: String = ""
  var _text_target_index: USize = 0
  var _blank_preview_once: Bool = false
  let _histories: Array[Array[String] ref] ref = Array[Array[String] ref]

  new iso create(env: Env, example: String, report: String) =>
    _env = env
    _report = report
    _active = NativePlayground.tab_index_for_id(example)
    var index: USize = 0
    while index < NativePlayground.tab_count() do
      _histories.push(Array[String])
      index = index + 1
    end
    _focus_text_capture_for_active_tab()
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
          _after_tab_change()
          if tab == 5 then _mouse_selected_example = true end
        end
      end
    elseif _handle_wheel_scroll_command(event) then
      None
    elseif _handle_task_list_scroll_command(event) then
      None
    elseif _handle_source_scroll_command(event) then
      None
    elseif (not _text_capture) and _handle_source_command(event) then
      None
    else
      let translated = _translate_event(event)
      if (translated != "") and _dispatch_child_event(translated) then
        _child_dispatches = _child_dispatches + 1
      end
    end

  fun ref _handle_source_command(event: String): Bool =>
    if _handle_source_scroll_command(event) then
      true
    elseif event == "r" then
      _rerun = if _dispatch_child_event("Refresh") then NativePlayground.tab_title(_active) + " rerun" else NativePlayground.tab_title(_active) + " rerun unchanged" end
      true
    elseif event == "R" then
      _history(_active).clear()
      NativePlayground.clear_child_state(_env, _active)
      if NativePlayground.is_interval_tab(_active) then
        NativePlayground.reset_interval_tab(_env, _active)
        _blank_preview_once = true
        _rerun = NativePlayground.tab_title(_active) + " cleared and rerun"
        _render()
      else
        _rerun = if _dispatch_child_event("Refresh") then NativePlayground.tab_title(_active) + " cleared and rerun" else NativePlayground.tab_title(_active) + " cleared" end
      end
      true
    else
      false
    end

  fun ref _handle_source_scroll_command(event: String): Bool =>
    if event == "PageDown" then
      _source_scroll = _source_scroll + 8
      true
    elseif event == "PageUp" then
      _source_scroll = if _source_scroll > 8 then _source_scroll - 8 else USize(0) end
      true
    elseif event == "Shift+Down" then
      _source_scroll = _source_scroll + 1
      true
    elseif event == "Shift+Up" then
      _source_scroll = if _source_scroll > 0 then _source_scroll - 1 else USize(0) end
      true
    elseif event == "WheelDown" then
      _source_scroll = _source_scroll + 3
      true
    elseif event == "WheelUp" then
      _source_scroll = if _source_scroll > 3 then _source_scroll - 3 else USize(0) end
      true
    else
      false
    end

  fun ref _handle_wheel_scroll_command(event: String): Bool =>
    if not ((event.at("WheelDown:", 0)) or (event.at("WheelUp:", 0))) then return false end
    (let x, _) = NativePlayground.wheel_xy(event)
    if (_active == 5) and (x >= 74) then
      if event.at("WheelDown:", 0) then
        _preview_scroll = (_preview_scroll + 1).min(NativePlayground.preview_max_scroll(_env, _active))
      else
        _preview_scroll = if _preview_scroll > 0 then _preview_scroll - 1 else USize(0) end
      end
    else
      if event.at("WheelDown:", 0) then
        _source_scroll = _source_scroll + 3
      else
        _source_scroll = if _source_scroll > 3 then _source_scroll - 3 else USize(0) end
      end
    end
    true

  fun ref _handle_task_list_scroll_command(event: String): Bool =>
    if _active != 5 then return false end
    if event == "ArrowDown" then
      _preview_scroll = (_preview_scroll + 1).min(NativePlayground.preview_max_scroll(_env, _active))
      true
    elseif event == "ArrowUp" then
      _preview_scroll = if _preview_scroll > 0 then _preview_scroll - 1 else USize(0) end
      true
    else
      false
    end

  fun ref _translate_event(event: String): String =>
    if _active == 5 then
      _translate_text_example_event(event)
    else
      _reset_text_capture_if_pointer(event)
      event
    end

  fun ref _translate_text_example_event(event: String): String =>
    if event.at("Mouse:", 0) then
      (let x, let y) = NativePlayground.mouse_xy(event)
      try
        let rel_x = NativePlayground.todo_preview_x(x)?
        let line = NativePlayground.todo_preview_line(_env, _active, y, _preview_scroll)?
        if line.at("Input:", 0) then
          _text_capture = true
          _text_edit = false
          _text_buffer = ""
          return "TodoFocus:0"
        elseif NativePlayground.todo_preview_item_line(line) then
          let item_index = NativePlayground.todo_item_index_for_screen_y(_env, _active, y, _preview_scroll)?
          if rel_x <= 4 then
            _reset_text_capture()
            return "TodoToggle:" + item_index.string()
          elseif NativePlayground.todo_preview_delete_click(line, rel_x) then
            _reset_text_capture()
            return "TodoDelete:" + item_index.string()
          else
            let title = NativePlayground.todo_preview_title(line)
            _text_capture = true
            _text_edit = true
            _text_target_index = item_index
            _text_buffer = title
            return "TodoStartEdit:" + item_index.string() + ":" + title
          end
        elseif line.contains("All | Active | Completed") then
          _reset_text_capture()
          if rel_x < 6 then
            return "TodoFilter:All"
          elseif rel_x < 15 then
            return "TodoFilter:Active"
          elseif rel_x < 28 then
            return "TodoFilter:Completed"
          else
            return "TodoClearCompleted"
          end
        else
          return ""
        end
      else
        return ""
      end
    elseif _text_capture then
      if event == "Enter" then
        _text_buffer = ""
        _text_edit = false
        _text_capture = true
        "TodoKey:Enter"
      elseif event == "Backspace" then
        if _text_buffer.size() > 0 then
          _text_buffer = recover val _text_buffer.substring(0, (_text_buffer.size() - 1).isize()) end
        end
        "TodoType:" + _text_buffer
      elseif event == "Space" then
        _text_buffer = _text_buffer + " "
        "TodoType:" + _text_buffer
      elseif event.size() == 1 then
        _text_buffer = _text_buffer + event
        "TodoType:" + _text_buffer
      else
        event
      end
    else
      event
    end

  fun ref _reset_text_capture_if_pointer(event: String) =>
    if event.at("Mouse:", 0) then _reset_text_capture() end

  fun ref _reset_text_capture() =>
    _text_capture = false
    _text_edit = false
    _text_buffer = ""
    _text_target_index = 0

  fun _row_index_for_list(y: USize): USize =>
    if y <= 10 then USize(0) else y - 10 end

  fun ref _switch_right() =>
    _active = _active + 1
    if _active >= NativePlayground.tab_count() then
      _active = 0
      _wrap_forward = true
    end
    _after_tab_change()

  fun ref _switch_left() =>
    if _active == 0 then
      _active = NativePlayground.tab_count() - 1
      _wrap_backward = true
    else
      _active = _active - 1
    end
    _after_tab_change()

  fun ref _after_tab_change() =>
    _source_scroll = 0
    _preview_scroll = 0
    _reset_text_capture()
    if NativePlayground.is_interval_tab(_active) then
      NativePlayground.reset_interval_tab(_env, _active)
      _blank_preview_once = true
    else
      _blank_preview_once = false
    end
    _focus_text_capture_for_active_tab()

  fun ref _focus_text_capture_for_active_tab() =>
    if _active == 5 then
      _text_capture = true
      _text_edit = false
      _text_buffer = ""
      _text_target_index = 0
    end

  fun ref _history(active: USize): Array[String] ref =>
    try
      _histories(active)?
    else
      let fallback = Array[String]
      _histories.push(fallback)
      fallback
    end

  fun ref _dispatch_child_event(event: String): Bool =>
    NativePlayground.dispatch_child_event(_env, _active, event, _history(_active))

  fun ref _render() =>
    _frame = _frame + 1
    _preview_scroll = _preview_scroll.min(NativePlayground.preview_max_scroll(_env, _active))
    NativePlayground.write_active_state(_env, _active, _source_edit, _source_scroll)
    _env.out.write("\x1B[H\x1B[2J")
    _line("Boon-Pony TUI | " + NativePlayground.tab_title(_active) + " | Q quit")
    _line(NativePlayground.tabs_line(_active))
    _line(NativePlayground.active_hint(_active))
    _line("source: " + NativePlayground.source_path(_active) + " | wheel/PgUp/PgDn source | r rerun | Shift+R clear state + rerun")
    _line("+ Boon source ----------------------------------------------------------+ Preview ----------------------------------+")
    _render_preview_and_source()
    _render_terminal_cursor()

  fun ref _render_terminal_cursor() =>
    if _active == 5 then
      let row = if _text_edit then try NativePlayground.todo_screen_y_for_item(_env, _active, _text_target_index, _preview_scroll)? else USize(7) end else USize(7) end
      let col = USize(81) + _text_buffer.size()
      _env.out.write("\x1B[" + row.string() + ";" + col.string() + "H\x1B[?25h")
    else
      _env.out.write("\x1B[?25l")
    end

  fun ref _line(text: String) =>
    _env.out.write(text + "\x1B[K\r\n")

  fun ref _render_preview_and_source() =>
    let preview = _preview_lines()
    let source = NativePlayground.source_preview_lines(_env, _active, _source_edit, _source_scroll, USize(20))
    let source_total = NativePlayground.source_total_lines(_env, _active, _source_edit)
    let rows = USize(21)
    let preview_total = NativePlayground.preview_scroll_total(_env, _active, rows)
    var row: USize = 0
    while row < rows do
      _line(
        _pad(_line_at(source, row), USize(69)) +
        NativePlayground.scrollbar(row, rows, source_total, _source_scroll) +
        " | " +
        _pad(_line_at(preview, row), USize(53)) +
        NativePlayground.preview_scrollbar(_env, _active, row, rows, preview_total, _preview_scroll))
      row = row + 1
    end

  fun _line_at(lines: Array[String] val, index: USize): String =>
    try lines(index)? else "" end

  fun _pad(text: String, width: USize): String =>
    let out = String
    if text.size() > width then
      out.append(recover val text.substring(0, width.isize()) end)
    else
      out.append(text)
    end
    while out.size() < width do out.append(" ") end
    out.clone()

  fun ref _preview_lines(): Array[String] val =>
    if _blank_preview_once then
      _blank_preview_once = false
      return recover val [ "" ] end
    end
    let generated = NativePlayground.protocol_preview_lines(_env, _active, _preview_scroll)
    if generated.size() > 0 then
      generated
    elseif NativePlayground.ensure_child_protocol(_env, _active) then
      let built = NativePlayground.protocol_preview_lines(_env, _active, _preview_scroll)
      if built.size() > 0 then
        built
      else
        recover val [ "" ] end
      end
    else
      recover val [
        "generated child frame unavailable"
        "build or protocol capture is required before this tab can preview"
      ] end
    end

  fun ref _finish() =>
    NativePlayground.write_inactive_state(_env)
    @system("stty sane".cstring())
    _env.out.write("\x1B[?1006l\x1B[?1002l\x1B[?1000l\x1B[?25h\x1B[?1049l")
    NativePlayground.write_report(_env, _report, NativePlayground.tab_title(_active))
    for line in _summary_lines().values() do _env.out.print(line) end
    _env.input.dispose()
    _env.exitcode(0)

  fun ref _summary_lines(): Array[String] val =>
    recover val [
      "playground summary:"
      "Generated child dispatches: " + _child_dispatches.string()
      "Generated child previews: yes"
      "Host preview overlay: no"
      "Boon source visible: yes"
      "Run/Rerun: " + _rerun
      "Clear state and rerun: available"
      "Tab wrap forward/back: " + if _wrap_forward and _wrap_backward then "yes" else "no" end
      "Mouse selected TodoMVC: " + if _mouse_selected_example then "yes" else "no" end
      "log clean: yes"
      "terminal restored"
    ] end

primitive NativePlayground
  fun run(env: Env, example: String = "", report': String = "") =>
    let report = if report' == "" then "build/reports/playground-live.json" else report' end
    reset_live_cache()
    let timers = Timers
    timers(Timer(PlaygroundTickNotify(env), 100_000_000, 100_000_000))
    @system("stty raw -echo".cstring())
    env.out.write("\x1B[?1049h\x1B[?25l\x1B[?1000h\x1B[?1002h\x1B[?1006h\x1B[2J")
    env.input(PlaygroundNotify(env, example, report), 64)

  fun reset_live_cache() =>
    @system("rm -f build/cache/protocol-counter.jsonl build/cache/protocol-counter_hold.jsonl build/cache/protocol-interval.jsonl build/cache/protocol-interval_hold.jsonl build/cache/protocol-cells.jsonl build/cache/protocol-todo_mvc.jsonl build/cache/protocol-pong.jsonl build/cache/protocol-arkanoid.jsonl build/cache/protocol-temperature_converter.jsonl build/cache/protocol-flight_booker.jsonl build/cache/protocol-timer.jsonl build/cache/protocol-crud.jsonl build/cache/protocol-circle_drawer.jsonl build/cache/playground-active.txt build/cache/playground-interval-*.txt build/cache/playground-interval_hold-*.txt".cstring())

  fun write_active_state(env: Env, active: USize, source_edit: Bool, source_scroll: USize) =>
    _write_file(env, "build/cache/playground-active.txt", tab_id(active) + "\n" + (if source_edit then "1" else "0" end) + "\n" + source_scroll.string() + "\n")

  fun write_inactive_state(env: Env) =>
    _write_file(env, "build/cache/playground-active.txt", "quit\n0\n0\n")

  fun auto_tick(env: Env) =>
    try
      let state = _read_file(env, "build/cache/playground-active.txt")?
      let active = _state_active_index(state)
      if not is_interval_tab(active) then return end
      let now = Time.nanos()
      let last = _interval_last_tick(env, active)
      if last == 0 then
        _write_file(env, _interval_last_file(active), now.string() + "\n")
        return
      end
      if (last != 0) and ((now - last) < 1_000_000_000) then return end
      _write_file(env, _interval_last_file(active), now.string() + "\n")
      let next = (_interval_auto_count(env, active) + 1).min(USize(999))
      _write_file(env, _interval_count_file(active), next.string() + "\n")
      if _write_interval_protocol(env, active, next) and (_interval_auto_count(env, active) == next) then
        env.out.write(_auto_interval_screen(env, active, next, _state_source_edit(state), _state_source_scroll(state)))
      end
    end

  fun timer_should_continue(env: Env): Bool =>
    try
      not _read_file(env, "build/cache/playground-active.txt")?.at("quit", 0)
    else
      true
    end

  fun is_interval_tab(active: USize): Bool =>
    (active == 2) or (active == 3)

  fun reset_interval_tab(env: Env, active: USize) =>
    if not is_interval_tab(active) then return end
    _write_file(env, _interval_count_file(active), "0\n")
    _write_file(env, _interval_last_file(active), Time.nanos().string() + "\n")
    _write_interval_protocol(env, active, USize(0))

  fun _interval_auto_count(env: Env, active: USize): USize =>
    try _trim(_read_file(env, _interval_count_file(active))?).usize()? else USize(0) end

  fun _interval_last_tick(env: Env, active: USize): U64 =>
    try _trim(_read_file(env, _interval_last_file(active))?).u64()? else U64(0) end

  fun _interval_count_file(active: USize): String =>
    "build/cache/playground-" + tab_id(active) + "-auto-count.txt"

  fun _interval_last_file(active: USize): String =>
    "build/cache/playground-" + tab_id(active) + "-last-second.txt"

  fun _state_source_edit(state: String): Bool =>
    try state.split_by("\n")(1)? == "1" else false end

  fun _state_source_scroll(state: String): USize =>
    try state.split_by("\n")(2)?.usize()? else USize(0) end

  fun _state_active_index(state: String): USize =>
    try tab_index_for_id(state.split_by("\n")(0)?) else USize(0) end

  fun _write_interval_protocol(env: Env, active: USize, ticks: USize): Bool =>
    let id = tab_id(active)
    let project = source_project(active)
    let binary: String val = recover val "build/bin/generated/" + id end
    let report: String val = recover val "build/reports/playground-session-" + id + "-protocol.json" end
    let body = String
    if (not _file_exists(env, binary)) or (not _report_matches_project(env, report, project)) then
      body.append("build/bin/boonpony build ")
      body.append(_shell_quote(project))
      body.append(" --report ")
      body.append(_shell_quote(report))
      body.append(" >/dev/null 2>&1 && ")
    end
    body.append("printf '%s\\n'")
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}"))
    var index: USize = 0
    while index < ticks do
      body.append(" ")
      body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}"))
      body.append(" ")
      body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}"))
      index = index + 1
    end
    body.append(" ")
    body.append(_shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}"))
    body.append(" | ")
    body.append(_shell_quote(binary))
    body.append(" --protocol > ")
    body.append(_shell_quote("build/cache/protocol-" + id + ".jsonl"))
    body.append(" 2> build/cache/playground-interval-auto.out")
    @system(("timeout 20s sh -c " + _shell_quote(body.clone())).cstring()) == 0

  fun _auto_interval_screen(env: Env, active: USize, ticks: USize, source_edit: Bool, source_scroll: USize): String =>
    let out = String
    out.append("\x1B[H\x1B[2J")
    _append_screen_line(out, "Boon-Pony TUI | " + tab_title(active) + " | Q quit")
    _append_screen_line(out, tabs_line(active))
    _append_screen_line(out, active_hint(active))
    _append_screen_line(out, "source: " + source_path(active) + " | wheel/PgUp/PgDn source | r rerun | Shift+R clear state + rerun")
    _append_screen_line(out, "+ Boon source ----------------------------------------------------------+ Preview ----------------------------------+")
    let preview = protocol_preview_lines(env, active)
    let source = source_preview_lines(env, active, source_edit, source_scroll, USize(20))
    let rows = USize(21)
    var row: USize = 0
    while row < rows do
      _append_screen_line(out, _pad(_line_at(source, row), USize(70)) + " | " + _pad(_line_at(preview, row), USize(54)))
      row = row + 1
    end
    out.clone()

  fun _append_screen_line(out: String ref, text: String) =>
    out.append(text)
    out.append("\x1B[K")
    out.append("\r\n")

  fun _line_at(lines: Array[String] val, index: USize): String =>
    try lines(index)? else "" end

  fun _pad(text: String, width: USize): String =>
    let out = String
    if text.size() > width then
      out.append(recover val text.substring(0, width.isize()) end)
    else
      out.append(text)
    end
    while out.size() < width do out.append(" ") end
    out.clone()

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

  fun mouse_xy(event: String): (USize, USize) =>
    try
      let parts = event.split_by(":")
      (parts(1)?.usize()?, parts(2)?.usize()?)
    else
      (USize(0), USize(0))
    end

  fun wheel_xy(event: String): (USize, USize) =>
    try
      let parts = event.split_by(":")
      (parts(1)?.usize()?, parts(2)?.usize()?)
    else
      (USize(0), USize(0))
    end

  fun scrollbar(row: USize, rows: USize, total: USize, scroll: USize): String =>
    if (rows <= 1) or (total <= rows) then return " " end
    let max_scroll = total - rows
    let thumb = if max_scroll == 0 then USize(0) else (scroll.min(max_scroll) * (rows - 1)) / max_scroll end
    if row == thumb then "#" else "|" end

  fun preview_scrollbar(env: Env, active: USize, row: USize, rows: USize, total: USize, scroll: USize): String =>
    if active == 5 then
      todo_scrollbar(env, active, row, scroll)
    else
      scrollbar(row, rows, total, scroll)
    end

  fun todo_scrollbar(env: Env, active: USize, row: USize, scroll: USize): String =>
    let lines = protocol_raw_preview_lines(env, active)
    var item_count: USize = 0
    var control_count: USize = 0
    var header_count: USize = 0
    var line_index: USize = 0
    for line in lines.values() do
      if line_index < 4 then
        header_count = header_count + 1
      elseif todo_preview_item_line(line) then
        item_count = item_count + 1
      else
        control_count = control_count + 1
      end
      line_index = line_index + 1
    end
    let track_rows = task_list_item_capacity(header_count, control_count)
    if (track_rows <= 1) or (item_count <= track_rows) then return " " end
    if (row < header_count) or (row >= (header_count + track_rows)) then return " " end
    let max_scroll = task_list_scroll_max_for(item_count, track_rows)
    let thumb = header_count + ((scroll.min(max_scroll) * (track_rows - 1)) / max_scroll)
    if row == thumb then "#" else "|" end

  fun source_total_lines(env: Env, active: USize, source_edit: Bool): USize =>
    let file = if source_edit then "build/cache/playground-edit-" + tab_id(active) + ".bn" else source_path(active) end
    try _read_file(env, file)?.split_by("\n").size() + 1 else USize(1) end

  fun preview_total_lines(env: Env, active: USize): USize =>
    protocol_raw_preview_lines(env, active).size()

  fun preview_max_scroll(env: Env, active: USize): USize =>
    let lines = protocol_raw_preview_lines(env, active)
    if active == 5 then
      task_list_max_scroll(lines)
    elseif lines.size() > 21 then
      lines.size() - 21
    else
      USize(0)
    end

  fun preview_scroll_total(env: Env, active: USize, rows: USize): USize =>
    let max_scroll = preview_max_scroll(env, active)
    if max_scroll == 0 then rows else rows + max_scroll end

  fun todo_preview_x(x: USize): USize ? =>
    if x < 74 then error end
    x - 73

  fun todo_preview_line(env: Env, active: USize, y: USize, scroll: USize = 0): String ? =>
    if y < 6 then error end
    protocol_preview_lines(env, active, scroll)(y - 6)?

  fun todo_preview_item_line(line: String): Bool =>
    line.at("[ ] ", 0) or line.at("[x] ", 0) or line.at("[edit] ", 0)

  fun todo_item_index_for_screen_y(env: Env, active: USize, y: USize, scroll: USize = 0): USize ? =>
    if y < 6 then error end
    let target = y - 6
    var index: USize = scroll
    var row: USize = 0
    for line in protocol_preview_lines(env, active, scroll).values() do
      if todo_preview_item_line(line) then
        if row == target then return index end
        index = index + 1
      end
      row = row + 1
    end
    error

  fun todo_screen_y_for_item(env: Env, active: USize, item: USize, scroll: USize = 0): USize ? =>
    var index: USize = scroll
    var row: USize = 0
    for line in protocol_preview_lines(env, active, scroll).values() do
      if todo_preview_item_line(line) then
        if index == item then return row + 6 end
        index = index + 1
      end
      row = row + 1
    end
    error

  fun todo_preview_delete_click(line: String, rel_x: USize): Bool =>
    try
      rel_x >= line.find("[del]")?.usize()
    else
      false
    end

  fun todo_preview_title(line: String): String =>
    let title_start: ISize = if line.at("[edit] ", 0) then 7 else 4 end
    let delete_at = try line.find("[del]")? else line.size().isize() end
    let raw: String val = recover val line.substring(title_start, delete_at) end
    let out = String
    for ch in raw.values() do
      if ch != '|' then out.push(ch) end
    end
    _trim(out.clone())

  fun _counter_preview_click(x: USize, y: USize): Bool =>
    (y >= 6) and (y <= 8) and (
      ((x >= 2) and (x <= 12)) or
      ((x >= 72) and (x <= 130)))

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
        elseif _starts_at(text, "\x1B[1;2A", cursor) then
          events.push("Shift+Up")
          cursor = cursor + 6
        elseif _starts_at(text, "\x1B[1;2B", cursor) then
          events.push("Shift+Down")
          cursor = cursor + 6
        elseif _starts_at(text, "\x1B[5~", cursor) then
          events.push("PageUp")
          cursor = cursor + 4
        elseif _starts_at(text, "\x1B[6~", cursor) then
          events.push("PageDown")
          cursor = cursor + 4
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
            let button = parts(0)?.usize()?
            let x = parts(1)?.usize()?
            let y = parts(2)?.usize()?
            let terminator = text.at_offset(mouse_end)?
            if terminator == 'M' then
              if button == 64 then
                events.push("WheelUp:" + x.string() + ":" + y.string())
              elseif button == 65 then
                events.push("WheelDown:" + x.string() + ":" + y.string())
              elseif y <= 2 then
                events.push("Tab:" + NativePlayground.tab_at_x(x).string())
              else
                events.push("Mouse:" + x.string() + ":" + y.string())
              end
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

  fun tab_count(): USize => 13

  fun tab_id(index: USize): String =>
    match index
    | 0 => "counter"
    | 1 => "counter_hold"
    | 2 => "interval"
    | 3 => "interval_hold"
    | 4 => "cells"
    | 5 => "todo_mvc"
    | 6 => "pong"
    | 7 => "arkanoid"
    | 8 => "temperature_converter"
    | 9 => "flight_booker"
    | 10 => "timer"
    | 11 => "crud"
    | 12 => "circle_drawer"
    else "counter"
    end

  fun tab_index_for_id(id: String): USize =>
    match id
    | "counter" => 0
    | "counter_hold" => 1
    | "interval" => 2
    | "interval_hold" => 3
    | "cells" => 4
    | "cells_dynamic" => 4
    | "todo_mvc" => 5
    | "todo" => 5
    | "pong" => 6
    | "arkanoid" => 7
    | "temperature_converter" => 8
    | "temperature" => 8
    | "flight_booker" => 9
    | "flight" => 9
    | "timer" => 10
    | "crud" => 11
    | "circle_drawer" => 12
    | "circle" => 12
    else 0
    end

  fun tab_title(index: USize): String =>
    match index
    | 0 => "Counter"
    | 1 => "Counter HOLD"
    | 2 => "Interval"
    | 3 => "Interval HOLD"
    | 4 => "Cells"
    | 5 => "TodoMVC"
    | 6 => "Pong"
    | 7 => "Arkanoid"
    | 8 => "Temperature Converter"
    | 9 => "Flight Booker"
    | 10 => "Timer"
    | 11 => "CRUD"
    | 12 => "Circle Drawer"
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
    | 1 => "CounterH"
    | 2 => "Interval"
    | 3 => "IntervalH"
    | 4 => "Cells"
    | 5 => "Todo"
    | 6 => "Pong"
    | 7 => "Arkanoid"
    | 8 => "Temp"
    | 9 => "Flight"
    | 10 => "Timer"
    | 11 => "CRUD"
    | 12 => "Circle"
    else "Counter"
    end

  fun active_hint(active: USize): String =>
    match active
    | 0 => "Counter: original LATEST + Math/sum example; click +, Enter, or Space increments."
    | 1 => "Counter HOLD: original HOLD example; click +, Enter, or Space increments."
    | 2 => "Interval: original Timer/interval + Math/sum example; starts empty, then ticks."
    | 3 => "Interval HOLD: original HOLD + Stream/skip example; starts empty, then ticks."
    | 4 => "Cells: 7GUIs spreadsheet; 100 rows x A-Z, scrollable source, Enter edits/commits A1."
    | 5 => "TodoMVC: add stays focused after Enter; row title edits; [del] removes; wheel or Up/Down scrolls."
    | 6 => "Pong: Space starts animation, W/S or Up/Down move player paddle, AI moves the other paddle."
    | 7 => "Arkanoid: Space launches/hits a brick, Left/Right or A/D move paddle, L marks lost."
    | 8 => "Temperature Converter: c edits Celsius, f edits Fahrenheit."
    | 9 => "Flight Booker: b books a return flight."
    | 10 => "Timer: Space or u advances elapsed time."
    | 11 => "CRUD: a creates Ada Lovelace."
    | 12 => "Circle Drawer: mouse adds a circle, u undoes."
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
    | 0 => "examples/upstream/counter/counter.bn"
    | 1 => "examples/upstream/counter_hold/counter_hold.bn"
    | 2 => "examples/upstream/interval/interval.bn"
    | 3 => "examples/upstream/interval_hold/interval_hold.bn"
    | 4 => "examples/upstream/cells/cells.bn"
    | 6 => "examples/terminal/pong/pong.bn"
    | 7 => "examples/terminal/arkanoid/arkanoid.bn"
    else "examples/upstream/" + tab_id(active) + "/" + tab_id(active) + ".bn"
    end

  fun source_preview_lines(env: Env, active: USize, source_edit: Bool, scroll: USize = 0, row_limit: USize = 12): Array[String] val =>
    let out = recover trn Array[String] end
    let file = if source_edit then working_file(active) else source_path(active) end
    out.push(file + " @ line " + (scroll + 1).string())
    try
      let text = _read_file(env, file)?
      var line_no: USize = 1
      for line in text.split_by("\n").values() do
        if (line_no > scroll) and (line_no <= (scroll + row_limit)) then
          out.push(line_no.string() + ": " + _source_preview_line(line))
        end
        line_no = line_no + 1
      end
    else
      out.push("source unavailable")
    end
    consume out

  fun _source_preview_line(line: String): String =>
    if line.size() > 68 then recover val line.substring(0, 68) end else line.clone() end

  fun source_project(active: USize): String =>
    match active
    | 0 => "examples/upstream/counter"
    | 1 => "examples/upstream/counter_hold"
    | 2 => "examples/upstream/interval"
    | 3 => "examples/upstream/interval_hold"
    | 4 => "examples/upstream/cells"
    | 6 => "examples/terminal/pong"
    | 7 => "examples/terminal/arkanoid"
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

  fun ensure_child_protocol(env: Env, active: USize): Bool =>
    let id = tab_id(active)
    let project = source_project(active)
    let protocol_capture: String val = recover val "build/cache/protocol-" + id + ".jsonl" end
    let child_report: String val = recover val "build/reports/playground-session-" + id + "-protocol.json" end
    let child_output: String val = recover val "build/cache/playground-session-" + id + "-protocol.out" end
    _ensure_child_protocol(env, project, protocol_capture, child_report, child_output) == 0

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
    if (lines.size() == 0) and (event != "Refresh") then return false end
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

  fun clear_child_state(env: Env, active: USize) =>
    let id = tab_id(active)
    let command = String
    command.append("rm -f ")
    command.append(_shell_quote("build/cache/protocol-" + id + ".jsonl"))
    command.append(" ")
    command.append(_shell_quote("build/cache/playground-event-" + id + "-protocol.out"))
    command.append(" ")
    command.append(_shell_quote("build/reports/playground-event-" + id + "-protocol.json"))
    if is_interval_tab(active) then
      command.append(" ")
      command.append(_shell_quote(_interval_count_file(active)))
      command.append(" ")
      command.append(_shell_quote(_interval_last_file(active)))
    end
    @system(command.clone().cstring())

  fun _child_event_lines(active: USize, event: String): Array[String] val =>
    let lines = recover trn Array[String] end
    match active
    | 0 =>
      if (event == "Enter") or (event == "Space") then
        lines.push(_expected_action("click_button", "", "0"))
      elseif event.at("Mouse:", 0) then
        (let x, let y) = mouse_xy(event)
        if _counter_preview_click(x, y) then
          lines.push(_expected_action("click_button", "", "0"))
        end
      end
    | 1 =>
      if (event == "Enter") or (event == "Space") then
        lines.push(_expected_action("click_button", "", "0"))
      elseif event.at("Mouse:", 0) then
        (let x, let y) = mouse_xy(event)
        if _counter_preview_click(x, y) then
          lines.push(_expected_action("click_button", "", "0"))
        end
      end
    | 2 =>
      None
    | 3 =>
      None
    | 4 =>
      if event == "7" then
        lines.push(_expected_action("dblclick_cells_cell", "1,1"))
        lines.push(_expected_action("set_focused_input_value", "7"))
        lines.push(_expected_action("key", "Enter"))
      elseif event == "Enter" then
        lines.push(_expected_action("dblclick_cells_cell", "1,1"))
      elseif event == "Backspace" then
        lines.push(_expected_action("set_focused_input_value", ""))
      end
    | 5 =>
      if event.at("TodoCommit:", 0) then
        let value: String val = recover val event.substring(11) end
        lines.push(_expected_action("focus_input", "", "0"))
        lines.push(_expected_action("type", value))
        lines.push(_expected_action("key", "Enter"))
      elseif event.at("TodoFocus:", 0) then
        lines.push(_expected_action("focus_input", "", recover val event.substring(10) end))
      elseif event.at("TodoType:", 0) then
        lines.push(_expected_action("type", recover val event.substring(9) end))
      elseif event.at("TodoKey:", 0) then
        lines.push(_expected_action("key", recover val event.substring(8) end))
      elseif event.at("TodoStartEdit:", 0) then
        try
          let rest: String val = recover val event.substring(14) end
          let colon = rest.find(":")?
          let index = rest.substring(0, colon).usize()? + 1
          let title: String val = recover val rest.substring(colon + 1) end
          lines.push(_expected_action("focus_input", "", index.string()))
          lines.push(_expected_action("type", title))
        end
      elseif event.at("TodoToggle:", 0) then
        let index = try event.substring(11).usize()? + 1 else USize(1) end
        lines.push(_expected_action("click_checkbox", "", index.string()))
      elseif event == "TodoToggleAll" then
        lines.push(_expected_action("click_checkbox", "", "0"))
      elseif event == "TodoClearCompleted" then
        lines.push(_expected_action("click_text", "Clear completed"))
      elseif event.at("TodoEdit:", 0) then
        let value: String val = recover val event.substring(9) end
        lines.push(_expected_action("click_text", "edit:" + value))
      elseif event.at("TodoDelete:", 0) then
        lines.push(_expected_action("click_text", "delete:" + recover val event.substring(11) end))
      elseif event.at("TodoFilter:", 0) then
        lines.push(_expected_action("click_text", "filter:" + recover val event.substring(11) end))
      end
    | 6 =>
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
    | 7 =>
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
    | 8 =>
      if event == "c" then
        lines.push(_expected_action("focus_input", "", "0"))
        lines.push(_expected_action("type", "0"))
      elseif event == "f" then
        lines.push(_expected_action("focus_input", "", "1"))
        lines.push(_expected_action("type", "212"))
      end
    | 9 =>
      if event == "b" then
        lines.push(_expected_action("select_option", "return", "0"))
        lines.push(_expected_action("set_input_value", "2026-03-03", "1"))
        lines.push(_expected_action("click_button", "", "0"))
      end
    | 10 =>
      if (event == "u") or (event == "Space") or (event == "t") then
        lines.push(_expected_action("set_slider_value", "15", "0"))
        lines.push(_expected_action("wait", ""))
      end
    | 11 =>
      if event == "a" then
        lines.push(_expected_action("set_input_value", "Ada", "1"))
        lines.push(_expected_action("set_input_value", "Lovelace", "2"))
        lines.push(_expected_action("click_text", "Create"))
      end
    | 12 =>
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

  fun protocol_preview_lines(env: Env, active: USize, scroll: USize = 0): Array[String] val =>
    let out = recover trn Array[String] end
    let raw_lines = protocol_raw_preview_lines(env, active)
    if active == 5 then
      _task_list_scrolled_preview(raw_lines, scroll)
    else
      for line in raw_lines.values() do out.push(line) end
      consume out
    end

  fun protocol_raw_preview_lines(env: Env, active: USize): Array[String] val =>
    let raw = recover trn Array[String] end
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
        let max_lines = if active == 5 then USize(120) else USize(20) end
        while (cursor < frame_line.size().isize()) and (count < max_lines) do
          (let value, let next_cursor) = _json_string_after(frame_line, "\"text\":\"", cursor)?
          for chunk in _preview_chunks(value).values() do
            raw.push(chunk)
            count = count + 1
            if count >= max_lines then break end
          end
          cursor = next_cursor
        end
      end
    end
    consume raw

  fun _task_list_scrolled_preview(lines: Array[String] val, scroll: USize): Array[String] val =>
    let out = recover trn Array[String] end
    let items = recover trn Array[String] end
    let controls = recover trn Array[String] end
    var row: USize = 0
    for line in lines.values() do
      if row < 4 then
        out.push(line)
      elseif todo_preview_item_line(line) then
        items.push(line)
      else
        controls.push(line)
      end
      row = row + 1
    end
    let item_lines: Array[String] val = consume items
    let control_lines: Array[String] val = consume controls
    let item_capacity = task_list_item_capacity(out.size(), control_lines.size())
    let max_scroll = task_list_scroll_max_for(item_lines.size(), item_capacity)
    var item_index = scroll.min(max_scroll)
    var printed: USize = 0
    while (item_index < item_lines.size()) and (printed < item_capacity) do
      try out.push(item_lines(item_index)?) end
      item_index = item_index + 1
      printed = printed + 1
    end
    var control_index: USize = 0
    while (control_index < control_lines.size()) and (out.size() < 21) do
      try out.push(control_lines(control_index)?) end
      control_index = control_index + 1
    end
    consume out

  fun task_list_max_scroll(lines: Array[String] val): USize =>
    var item_count: USize = 0
    var control_count: USize = 0
    var header_count: USize = 0
    var row: USize = 0
    for line in lines.values() do
      if row < 4 then
        header_count = header_count + 1
      elseif todo_preview_item_line(line) then
        item_count = item_count + 1
      else
        control_count = control_count + 1
      end
      row = row + 1
    end
    task_list_scroll_max_for(item_count, task_list_item_capacity(header_count, control_count))

  fun task_list_item_capacity(header_count: USize, control_count': USize): USize =>
    let control_count = control_count'.min(USize(4))
    if (21 > header_count) and ((21 - header_count) > control_count) then (21 - header_count) - control_count else USize(0) end

  fun task_list_scroll_max_for(item_count: USize, item_capacity: USize): USize =>
    if item_count > item_capacity then item_count - item_capacity else USize(0) end

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
    if (not _file_exists(env, binary)) or (not _report_matches_project(env, report, project)) then
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

  fun _report_matches_project(env: Env, report: String, project: String): Bool =>
    try
      _read_file(env, report)?.contains("\"project\":\"" + project + "\"")
    else
      false
    end

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
