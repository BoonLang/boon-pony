use "files"

primitive NativePty
  fun verify_command(env: Env, report': String = "") =>
    let report = if report' == "" then "build/reports/verify-pty.json" else report' end
    _mkdirs()
    let cases = Array[(String, String, String, Array[String] val, Array[String] val)]
    cases.push(_run_counter_interval_protocol(env))
    cases.push(_run_counter_preview_parity(env))
    cases.push(_run_playground_counter_clicks(env))
    cases.push(_run_todo_protocol_scenarios(env))
    cases.push(_run_pong(env))
    cases.push(_run_arkanoid(env))
    cases.push(_run_playground(env))
    cases.push(_run_playground_source_scroll(env))
    cases.push(_run_playground_source_mouse_wheel(env))
    cases.push(_run_playground_interval_auto(env))
    cases.push(_run_playground_todo_many(env))
    cases.push(_run_playground_todo_mouse_edit_delete(env))
    cases.push(_run_playground_todo_scroll(env))
    cases.push(_run_playground_pong_hold(env))
    cases.push(_run_playground_host_guard(env))
    cases.push(_run_source_edit(env))
    let failures = Array[String]
    for item in cases.values() do
      if item._2 != "pass" then failures.push(item._1 + " failed") end
    end
    _write_file(env, report, _report(cases, failures))
    if failures.size() == 0 then
      env.out.print("pty ok: generated counter/interval, pong, arkanoid, playground, source scroll, and source-view action proofs passed")
      env.out.print("report: " + report)
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.err.print("report: " + report)
      env.exitcode(1)
    end

  fun _run_pong(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-pong.out"
    let session = "boonpony_native_pty_pong"
    let first = "build/cache/pty-pong-first.out"
    let second = "build/cache/pty-pong-second.out"
    let command = "build/bin/boonpony build examples/terminal/pong >/dev/null 2>&1 && " +
      _pty_prefix(session, "100", "32", "build/bin/generated/pong") +
      _wait(session, "Pong") +
      _sleep("0.4") +
      "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(first) + "; " +
      _sleep("0.8") +
      "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(second) + "; " +
      "if cmp -s " + _shell_quote(first) + " " + _shell_quote(second) + "; then echo 'pong auto animation failed' > " + _shell_quote(out) + "; exit 1; else echo 'pong auto animation observed' > " + _shell_quote(out) + "; fi; " +
      _send_repeat_key_fast(session, "Up", USize(8)) + _send_repeat_key_fast(session, "Down", USize(8)) + _send_repeat_key_fast(session, "w", USize(8)) + _send_repeat_key_fast(session, "s", USize(8)) + _wait(session, "Point scored") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "pong", consume command, out, recover val ["pong auto animation observed"; "terminal restored"; "final score 1 : 0"] end)

  fun _run_arkanoid(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-arkanoid.out"
    let session = "boonpony_native_pty_arkanoid"
    let first = "build/cache/pty-arkanoid-first.out"
    let second = "build/cache/pty-arkanoid-second.out"
    let command = "build/bin/boonpony build examples/terminal/arkanoid >/dev/null 2>&1 && " +
      _pty_prefix(session, "100", "34", "build/bin/generated/arkanoid") +
      _wait(session, "Playing") +
      _sleep("0.4") +
      "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(first) + "; " +
      _sleep("0.8") +
      "tmux capture-pane -p -t " + _shell_quote(session) + " > " + _shell_quote(second) + "; " +
      "if cmp -s " + _shell_quote(first) + " " + _shell_quote(second) + "; then echo 'arkanoid auto animation failed' > " + _shell_quote(out) + "; exit 1; else echo 'arkanoid auto animation observed' > " + _shell_quote(out) + "; fi; " +
      _send_key(session, "Left") + _send_key(session, "Right") + _wait(session, "Brick removed") +
      _send_key(session, "L") + _wait(session, "Lost") +
      _send_key(session, "Space") + _wait(session, "Playing") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "arkanoid", consume command, out, recover val ["arkanoid auto animation observed"; "final status Playing"; "terminal restored"] end)

  fun _run_counter_preview_parity(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-counter-preview-parity.out"
    let command: String val = recover val
      "build/bin/boonpony build examples/upstream/counter >/dev/null 2>&1 && " +
      "build/bin/boonpony build examples/upstream/counter_hold >/dev/null 2>&1 && " +
      "node tests/scripts/verify_counter_protocol.js > " + _shell_quote(out) + " 2>&1"
    end
    _run_case(env, "counter-preview-parity", command, out, recover val ["counter preview parity ok"; "counter initial=0+ click=1+"; "counter_hold initial=0+ click=1+"] end)

  fun _run_playground_counter_clicks(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-counter-clicks.out"
    let session = "boonpony_native_pty_playground_counter_clicks"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example counter") +
      _wait(session, "Boon-Pony TUI | Counter") +
      _wait(session, "| 0+") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_mouse(session, "76", "6") +
      _wait(session, "| 1+") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_key(session, "S-Right") +
      _wait(session, "Boon-Pony TUI | Counter HOLD") +
      _wait(session, "| 0+") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_mouse(session, "76", "6") +
      _wait(session, "| 1+") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-counter-clicks", consume command, out, recover val ["Boon-Pony TUI | Counter"; "Boon-Pony TUI | Counter HOLD"; "| 0+"; "| 1+"; "terminal restored"; "__EXIT:0"] end)

  fun _run_todo_protocol_scenarios(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-todo-protocol.out"
    let command: String val = recover val
      "build/bin/boonpony build examples/upstream/todo_mvc >/dev/null 2>&1 && " +
      "node tests/scripts/verify_todo_protocol.js > " + _shell_quote(out) + " 2>&1"
    end
    _run_case(env, "todo-protocol-scenarios", command, out, recover val ["todo protocol scenarios ok"; "initial/add/filter/toggle/toggle-all/clear/edit/delete/persistence covered"] end)

  fun _run_playground(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground.out"
    let session = "boonpony_native_pty_playground"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui") +
      _wait(session, "Boon-Pony TUI | Counter") +
      _send_mouse(session, "80", "7") +
      _sleep("1") +
      _send_key(session, "Enter") +
      _sleep("1") +
      _send_key(session, "S-Right") +
      _send_key(session, "Space") +
      _send_key(session, "S-Right") +
      _wait(session, "Boon-Pony TUI | Interval") +
      _wait(session, " | 2") +
      _send_key(session, "S-Right") +
      _wait(session, "Boon-Pony TUI | Interval HOLD") +
      _wait(session, " | 2") +
      _send_key(session, "S-Right") +
      _send_key(session, "Enter") + _send_key(session, "BSpace") + _send_literal(session, "7") + _send_key(session, "Enter") +
      _send_mouse(session, "55", "2") +
      _send_mouse(session, "20", "8") + _send_literal(session, "Write tests") + _send_key(session, "Enter") +
      _send_mouse(session, "20", "8") + _send_literal(session, "Ship demo") + _send_key(session, "Enter") +
      _send_mouse(session, "10", "10") +
      _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") +
      _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") + _send_key(session, "BSpace") +
      _send_literal(session, "Write tests well") + _send_key(session, "Enter") +
      _send_mouse(session, "30", "11") +
      _send_mouse(session, "3", "10") +
      _send_mouse(session, "26", "18") +
      _send_mouse(session, "36", "18") +
      _send_mouse(session, "4", "8") +
      _send_mouse(session, "48", "18") +
      _send_key(session, "S-Right") + _send_key(session, "Space") + _sleep("8") + _send_key(session, "Up") + _send_key(session, "Down") +
      _send_key(session, "S-Right") + _send_key(session, "Space") + _send_key(session, "Left") + _send_key(session, "Right") +
      _send_key(session, "S-Right") + _send_literal(session, "c") + _send_literal(session, "f") +
      _send_key(session, "S-Right") + _send_literal(session, "b") +
      _send_key(session, "S-Right") + _send_literal(session, "u") +
      _send_key(session, "S-Right") + _send_literal(session, "a") +
      _send_key(session, "S-Right") + _send_mouse(session, "50", "12") + _send_mouse(session, "54", "14") + _send_literal(session, "u") +
      _send_key(session, "S-Right") + _send_key(session, "S-Left") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "playground", consume command, out, recover val ["Generated child dispatches:"; "Generated child previews: yes"; "Host preview overlay: no"; "Boon source visible: yes"; "Tab wrap forward/back: yes"; "Mouse selected TodoMVC: yes"; "log clean: yes"; "terminal restored"; "__EXIT:0"] end)

  fun _run_counter_interval_protocol(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-counter-interval-protocol.out"
    let counter_script: String val = recover val
      "printf '%s\\n' " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"click_button\",\"index\":0}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"click_button\",\"index\":0}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}") +
      " | build/bin/generated/counter --protocol"
    end
    let counter_hold_script: String val = recover val
      "printf '%s\\n' " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"click_button\",\"index\":0}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}") +
      " | build/bin/generated/counter_hold --protocol"
    end
    let interval_script: String val = recover val
      "printf '%s\\n' " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}") +
      " | build/bin/generated/interval --protocol"
    end
    let interval_hold_script: String val = recover val
      "printf '%s\\n' " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"expected_action\",\"action\":\"wait\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"frame\"}") + " " +
      _shell_quote("{\"protocol_version\":1,\"type\":\"quit\"}") +
      " | build/bin/generated/interval_hold --protocol"
    end
    let command = String
    command.append("build/bin/boonpony build examples/upstream/counter >/dev/null 2>&1 && ")
    command.append("build/bin/boonpony build examples/upstream/counter_hold >/dev/null 2>&1 && ")
    command.append("build/bin/boonpony build examples/upstream/interval >/dev/null 2>&1 && ")
    command.append("build/bin/boonpony build examples/upstream/interval_hold >/dev/null 2>&1 && ")
    command.append("{ ")
    command.append(counter_script)
    command.append("; ")
    command.append(counter_hold_script)
    command.append("; ")
    command.append(interval_script)
    command.append("; ")
    command.append(interval_hold_script)
    command.append("; } > ")
    command.append(_shell_quote(out))
    command.append(" 2>&1")
    _run_case(env, "counter-interval-generated-protocol", command.clone(), out, recover val ["\"app\":\"counter\""; "\"text\":\"0+\""; "\"text\":\"1+\""; "\"text\":\"2+\""; "\"app\":\"counter_hold\""; "\"text\":\"0+\""; "\"text\":\"1+\""; "\"app\":\"interval\""; "\"text\":\"\""; "\"text\":\"1\""; "\"app\":\"interval_hold\""] end)

  fun _run_playground_source_scroll(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-source-scroll.out"
    let session = "boonpony_native_pty_playground_source_scroll"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example cells") +
      _wait(session, "Boon-Pony TUI | Cells") +
      _send_key(session, "NPage") +
      _wait(session, "examples/upstream/cells/cells.bn @ line 9") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-source-scroll", consume command, out, recover val ["Boon-Pony TUI | Cells"; "examples/upstream/cells/cells.bn @ line 9"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_interval_auto(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-interval-auto.out"
    let session = "boonpony_native_pty_playground_interval_auto"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example interval") +
      _wait(session, "Boon-Pony TUI | Interval") +
      _send_key(session, "NPage") +
      _wait(session, " | 3") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-interval-auto", consume command, out, recover val ["Boon-Pony TUI | Interval"; " | 3"; "examples/upstream/interval/interval.bn @ line 9"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_source_mouse_wheel(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-source-mouse-wheel.out"
    let session = "boonpony_native_pty_playground_source_mouse_wheel"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example cells") +
      _wait(session, "Boon-Pony TUI | Cells") +
      _send_wheel_down(session, "20", "8") +
      _wait(session, "examples/upstream/cells/cells.bn @ line 4") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_wheel_up(session, "20", "8") +
      _wait(session, "examples/upstream/cells/cells.bn @ line 1") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-source-mouse-wheel", consume command, out, recover val ["Boon-Pony TUI | Cells"; "examples/upstream/cells/cells.bn @ line 4"; "examples/upstream/cells/cells.bn @ line 1"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_todo_many(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-todo-many.out"
    let session = "boonpony_native_pty_playground_todo_many"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example todo_mvc") +
      _wait(session, "Boon-Pony TUI | TodoMVC") +
      _wait(session, "Input: |") +
      _send_literal(session, "One") + _send_key(session, "Enter") +
      _send_literal(session, "Two") + _send_key(session, "Enter") +
      _send_literal(session, "Three") + _send_key(session, "Enter") +
      _send_literal(session, "Four") + _send_key(session, "Enter") +
      _send_literal(session, "Five") + _send_key(session, "Enter") +
      _send_literal(session, "Six") + _send_key(session, "Enter") +
      _send_literal(session, "Seven") + _send_key(session, "Enter") +
      _wait(session, "Seven") +
      _wait(session, "Input: |") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-todo-many", consume command, out, recover val ["Input: |"; "Seven"; "Generated child dispatches:"; "Generated child previews: yes"; "Boon source visible: yes"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_todo_mouse_edit_delete(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-todo-mouse-edit-delete.out"
    let session = "boonpony_native_pty_playground_todo_mouse_edit_delete"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example todo_mvc") +
      _wait(session, "Input: |") +
      _send_literal(session, "One") +
      _wait(session, "Input: One|") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      _send_key(session, "Enter") +
      _wait(session, "One") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_mouse(session, "82", "10") +
      _wait(session, "edit] Buy groceries") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_mouse(session, "120", "10") +
      _wait(session, "Clean room") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      "if tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'Buy groceries.*\\[del\\]'; then echo 'todo delete failed' >> " + _shell_quote(out) + "; exit 1; fi; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-todo-mouse-edit-delete", consume command, out, recover val ["Input: One|"; "[ ] One"; "[edit] Buy groceries"; "[ ] Clean room"; "[del]"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_todo_scroll(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-todo-scroll.out"
    let session = "boonpony_native_pty_playground_todo_scroll"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example todo_mvc") +
      _wait(session, "Input: |") +
      _send_literal(session, "A01") + _send_key(session, "Enter") +
      _send_literal(session, "A02") + _send_key(session, "Enter") +
      _send_literal(session, "A03") + _send_key(session, "Enter") +
      _send_literal(session, "A04") + _send_key(session, "Enter") +
      _send_literal(session, "A05") + _send_key(session, "Enter") +
      _send_literal(session, "A06") + _send_key(session, "Enter") +
      _send_literal(session, "A07") + _send_key(session, "Enter") +
      _send_literal(session, "A08") + _send_key(session, "Enter") +
      _send_literal(session, "A09") + _send_key(session, "Enter") +
      _send_literal(session, "A10") + _send_key(session, "Enter") +
      _send_literal(session, "A11") + _send_key(session, "Enter") +
      _send_literal(session, "A12") + _send_key(session, "Enter") +
      _send_literal(session, "A13") + _send_key(session, "Enter") +
      _send_literal(session, "A14") + _send_key(session, "Enter") +
      _send_literal(session, "A15") + _send_key(session, "Enter") +
      _send_literal(session, "A16") + _send_key(session, "Enter") +
      _send_literal(session, "A17") + _send_key(session, "Enter") +
      _send_literal(session, "A18") + _send_key(session, "Enter") +
      _send_literal(session, "A19") + _send_key(session, "Enter") +
      _send_literal(session, "A20") + _send_key(session, "Enter") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(out) + "; " +
      "if tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'A20'; then echo 'todo scroll failed: A20 visible before scroll' >> " + _shell_quote(out) + "; exit 1; fi; " +
      _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") +
      _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") +
      _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") +
      _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") +
      _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") + _send_key(session, "Down") +
      "if ! tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'A20'; then echo 'todo scroll failed: Down did not reveal A20' >> " + _shell_quote(out) + "; exit 1; fi; " +
      "if ! tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'A08'; then echo 'todo scroll failed: Down did not clamp at expected bottom' >> " + _shell_quote(out) + "; exit 1; fi; " +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") +
      _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") +
      _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") +
      _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") +
      _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") + _send_key(session, "Up") +
      "if ! tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'Buy groceries'; then echo 'todo scroll failed: Up did not restore top' >> " + _shell_quote(out) + "; exit 1; fi; " +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") +
      _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") +
      _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") +
      _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") +
      _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") + _send_wheel_down(session, "82", "16") +
      "if ! tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'A20'; then echo 'todo scroll failed: wheel did not reveal A20' >> " + _shell_quote(out) + "; exit 1; fi; " +
      "if ! tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q 'A08'; then echo 'todo scroll failed: wheel overscrolled beyond expected bottom' >> " + _shell_quote(out) + "; exit 1; fi; " +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_wheel_down(session, "20", "10") +
      _wait(session, "@ line 4") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_shift_down(session) +
      _wait(session, "@ line 5") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_shift_up(session) +
      _wait(session, "@ line 4") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; " +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " >> " + _shell_quote(out) + "; "
    _run_case(env, "playground-todo-scroll", consume command, out, recover val ["A01"; "A08"; "A20"; "Buy groceries"; "@ line 4"; "@ line 5"; "#"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_pong_hold(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-playground-pong-hold.out"
    let session = "boonpony_native_pty_playground_pong_hold"
    let command = _pty_prefix(session, "120", "36", "build/bin/boonpony tui --example pong") +
      _wait(session, "Boon-Pony TUI | Pong") +
      _send_key(session, "Space") +
      _send_repeat_key_fast(session, "Up", USize(24)) + _send_repeat_key_fast(session, "Down", USize(24)) +
      _send_repeat_key_fast(session, "w", USize(24)) + _send_repeat_key_fast(session, "s", USize(24)) +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "playground-pong-hold", consume command, out, recover val ["Generated child dispatches:"; "Generated child previews: yes"; "Boon source visible: yes"; "terminal restored"; "__EXIT:0"] end)

  fun _run_source_edit(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let out = "build/cache/pty-source-view-actions.out"
    let session = "boonpony_native_pty_source_view_actions"
    let command = _pty_prefix(session, "132", "40", "build/bin/boonpony tui --example pong") +
      _wait(session, "Boon-Pony TUI | Pong") +
      _send_literal(session, "r") + _send_literal(session, "R") +
      _send_key(session, "Q") + _wait(session, "__EXIT:") +
      _capture(session, out)
    _run_case(env, "source-view-actions", consume command, out, recover val ["Boon source visible: yes"; "Run/Rerun: Pong cleared and rerun"; "Clear state and rerun: available"; "terminal restored"; "__EXIT:0"] end)

  fun _run_playground_host_guard(env: Env): (String, String, String, Array[String] val, Array[String] val) =>
    let file = "src/boonpony/native_playground.pony"
    let source = try _read_file(env, file)? else "" end
    let missing = recover trn Array[String] end
    for marker in [
      "_todo_"
      "_pong_"
      "_counter:"
      "_interval:"
      "render_pong_tick"
      "render_interval_tick"
      "advance_pong"
      "Pong - playable preview"
      "Live preview"
    ].values() do
      if source.contains(marker) then missing.push("host business marker " + marker) end
    end
    let status = if missing.size() == 0 then "pass" else "fail" end
    ("playground-host-guard", status, file, recover val ["no host business state"] end, consume missing)

  fun _run_case(env: Env, name: String, command: String box, output_file: String, needles: Array[String] val): (String, String, String, Array[String] val, Array[String] val) =>
    let status = _system_status(command)
    let output = _clean(try _read_file(env, output_file)? else "" end)
    let missing = recover trn Array[String] end
    if status != 0 then missing.push("shell exit " + status.string()) end
    for needle in needles.values() do
      if not output.contains(needle) then missing.push(needle) end
    end
    let final_status = if missing.size() == 0 then "pass" else "fail" end
    (name, final_status, output_file, needles, consume missing)

  fun _pty_prefix(session: String, width: String, height: String, inner: String): String =>
    "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true; " +
    "tmux new-session -d -s " + _shell_quote(session) + " -x " + width + " -y " + height + " " +
    _shell_quote("bash -lc '" + inner + "; code=$?; echo __EXIT:$code; sleep 1'") + "; "

  fun _wait(session: String, needle: String): String =>
    "for i in $(seq 1 200); do tmux capture-pane -p -t " + _shell_quote(session) + " | grep -q " + _shell_quote(needle) + " && break; sleep 0.05; done; "
    + "sleep 0.20; "

  fun _send_key(session: String, key: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " " + _shell_quote(key) + "; sleep 0.20; "

  fun _send_repeat_key_fast(session: String, key: String, count: USize): String =>
    let out = String
    var i: USize = 0
    while i < count do
      out.append("tmux send-keys -t ")
      out.append(_shell_quote(session))
      out.append(" ")
      out.append(_shell_quote(key))
      out.append("; ")
      i = i + 1
    end
    out.append("sleep 0.50; ")
    out.clone()

  fun _send_literal(session: String, text: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " -l " + _shell_quote(text) + "; sleep 0.20; "

  fun _send_mouse(session: String, x: String, y: String): String =>
    "printf '\\033[<0;" + x + ";" + y + "M\\033[<0;" + x + ";" + y + "m' | tmux load-buffer -; tmux paste-buffer -t " + _shell_quote(session) + "; sleep 0.20; "

  fun _send_wheel_down(session: String, x: String, y: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " \"$(printf '\\033[<65;" + x + ";" + y + "M')\"; sleep 0.20; "

  fun _send_wheel_up(session: String, x: String, y: String): String =>
    "tmux send-keys -t " + _shell_quote(session) + " \"$(printf '\\033[<64;" + x + ";" + y + "M')\"; sleep 0.20; "

  fun _send_shift_down(session: String): String =>
    "printf '\\033[1;2B' | tmux load-buffer -; tmux paste-buffer -t " + _shell_quote(session) + "; sleep 0.20; "

  fun _send_shift_up(session: String): String =>
    "printf '\\033[1;2A' | tmux load-buffer -; tmux paste-buffer -t " + _shell_quote(session) + "; sleep 0.20; "

  fun _sleep(seconds: String): String =>
    "sleep " + seconds + "; "

  fun _capture(session: String, output_file: String): String =>
    "tmux capture-pane -p -S -200 -t " + _shell_quote(session) + " > " + _shell_quote(output_file) + "; " +
    "tmux kill-session -t " + _shell_quote(session) + " 2>/dev/null || true"

  fun _report(cases: Array[(String, String, String, Array[String] val, Array[String] val)] box, failures: Array[String] box): String =>
    let out = String
    out.append("{\n  \"command\":\"verify-pty\",\n  \"status\":\""); out.append(if failures.size() == 0 then "pass" else "fail" end); out.append("\",\n")
    out.append("  \"started_at\":\"native-pony\",\n  \"finished_at\":\"native-pony\",\n  \"cases\":[")
    var index: USize = 0
    for item in cases.values() do
      if index > 0 then out.append(",") end
      out.append("{\"name\":\""); _append_json(out, item._1); out.append("\",\"status\":\""); out.append(item._2); out.append("\",")
      out.append("\"pty_backend\":\"tmux\",\"output_file\":\""); _append_json(out, item._3); out.append("\",")
      out.append("\"evidence_checked\":"); out.append(_strings_json(item._4)); out.append(",")
      out.append("\"terminal_restored_observed\":"); out.append(if _array_contains(item._4, "terminal restored") and (not _array_contains(item._5, "terminal restored")) then "true" else "false" end); out.append(",")
      out.append("\"missing\":"); out.append(_strings_json(item._5)); out.append("}")
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

  fun _array_contains(items: Array[String] box, value: String): Bool =>
    for item in items.values() do
      if item == value then return true end
    end
    false

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
