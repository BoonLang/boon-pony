use @system[I32](cmd: Pointer[U8] tag)

actor Main
  new create(env: Env) =>
    try
      let command = env.args(1)?
      match command
      | "--help" => Help.root(env)
      | "-h" => Help.root(env)
      | "tui" => _command_tui(env)
      | "play" => _command_play(env)
      | "manifest" => _command_manifest(env)
      | "import-upstream" => _command_import_upstream(env)
      | "parse" => _command_parse(env)
      | "verify-parser" => _command_verify_parser(env)
      | "verify-source-shape" => _command_verify_source_shape(env)
      | "flow" => _command_flow(env)
      | "compile" => _command_compile(env)
      | "build" => _command_build(env)
      | "verify" => _command_verify(env)
      | "verify-terminal" => _command_verify_terminal(env)
      | "verify-terminal-safety" => _command_verify_terminal_safety(env)
      | "verify-pty" => _command_verify_pty(env)
      | "snapshot" => _command_snapshot(env)
      | "protocol-smoke" => _command_protocol_smoke(env)
      | "bench" => _command_bench(env)
      else
        env.err.print("error: unknown command: " + command)
        Help.root(env)
        env.exitcode(2)
      end
    else
      Help.root(env)
    end

  fun _command_tui(env: Env) =>
    if _has_help(env) then
      Help.tui(env)
    else
      var script: String = ""
      var report: String = ""
      var keyboard_mode = false
      var example: String = ""
      var index: USize = 2
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--keyboard-test" then
            keyboard_mode = true
            index = index + 1
          elseif keyboard_mode then
            env.err.print("error: --keyboard-test cannot be combined with other tui options")
            Help.tui(env)
            env.exitcode(2)
            return
          elseif arg == "--script" then
            script = env.args(index + 1)?
            index = index + 2
          elseif arg == "--example" then
            if script != "" then
              env.err.print("error: --example cannot be combined with --script")
              Help.tui(env)
              env.exitcode(2)
              return
            end
            example = env.args(index + 1)?
            index = index + 2
          elseif arg == "--report" then
            report = env.args(index + 1)?
            index = index + 2
          else
            env.err.print("error: unknown tui option: " + arg)
            Help.tui(env)
            env.exitcode(2)
            return
          end
        else
          env.err.print("error: tui option is missing a value")
          Help.tui(env)
          env.exitcode(2)
          return
        end
      end
      if script != "" then
        if report == "" then
          report = "build/reports/playground-script.json"
        end
        NativeBoon.tui_script_command(env, script, report)
      elseif keyboard_mode then
        NativeSafety.keyboard_test_command(env)
      else
        NativePlayground.run(env, example, report)
      end
    end

  fun _command_play(env: Env) =>
    if _has_help(env) then
      Help.play(env)
    else
      try
        let project = env.args(2)?
        var report: String = ""
        var index: USize = 3
        while index < env.args.size() do
          try
            let arg = env.args(index)?
            if arg == "--report" then
              report = env.args(index + 1)?
              index = index + 2
            else
              env.err.print("error: unknown play option: " + arg)
              Help.play(env)
              env.exitcode(2)
              return
            end
          else
            env.err.print("error: play option is missing a value")
            Help.play(env)
            env.exitcode(2)
            return
          end
        end
        NativeCodegen.play_command(env, project, report)
      else
        env.err.print("error: play requires a project path")
        Help.play(env)
        env.exitcode(2)
      end
    end

  fun _command_manifest(env: Env) =>
    if _has_help(env) then
      Help.manifest(env)
    elseif _has_arg(env, "--check") then
      NativeBoon.manifest_check_command(env)
    else
      env.err.print("error: manifest currently requires --check")
      Help.manifest(env)
      env.exitcode(2)
    end

  fun _command_import_upstream(env: Env) =>
    if _has_help(env) then
      Help.import_upstream(env)
      return
    end

    var source: String = ""
    var commit: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--source" then
          source = env.args(index + 1)?
          index = index + 2
        elseif arg == "--commit" then
          commit = env.args(index + 1)?
          index = index + 2
        else
          env.err.print("error: unknown import-upstream option: " + arg)
          Help.import_upstream(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: import-upstream option is missing a value")
        Help.import_upstream(env)
        env.exitcode(2)
        return
      end
    end

    if (source == "") or (commit == "") then
      env.err.print("error: import-upstream requires --source and --commit")
      Help.import_upstream(env)
      env.exitcode(2)
      return
    end

    NativeImport.import_command(env, source, commit)

  fun _command_parse(env: Env) =>
    if _has_help(env) then
      Help.parse(env)
      return
    end

    try
      let file = env.args(2)?
      var report: String = ""
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--report" then
            report = env.args(index + 1)?
            index = index + 2
          else
            env.err.print("error: unknown parse option: " + arg)
            Help.parse(env)
            env.exitcode(2)
            return
          end
        else
          env.err.print("error: parse option is missing a value")
          Help.parse(env)
          env.exitcode(2)
          return
        end
      end
      NativeBoon.parse_command(env, file, report)
    else
      env.err.print("error: parse requires a file path")
      Help.parse(env)
      env.exitcode(2)
    end

  fun _command_verify_parser(env: Env) =>
    if _has_help(env) then
      Help.verify_parser(env)
      return
    end

    var corpus: String = ""
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--corpus" then
          corpus = env.args(index + 1)?
          index = index + 2
        elseif arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        else
          env.err.print("error: unknown verify-parser option: " + arg)
          Help.verify_parser(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify-parser option is missing a value")
        Help.verify_parser(env)
        env.exitcode(2)
        return
      end
    end

    if corpus == "" then
      env.err.print("error: verify-parser requires --corpus")
      Help.verify_parser(env)
      env.exitcode(2)
      return
    end

    if report == "" then
      report = "build/reports/verify-parser.json"
    end
    NativeBoon.verify_parser_command(env, corpus, report)

  fun _command_verify_source_shape(env: Env) =>
    if _has_help(env) then
      Help.verify_source_shape(env)
      return
    end

    var all = false
    var report: String = "build/reports/verify-source-shape.json"
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--all" then
          all = true
          index = index + 1
        elseif arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        else
          env.err.print("error: unknown verify-source-shape option: " + arg)
          Help.verify_source_shape(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify-source-shape option is missing a value")
        Help.verify_source_shape(env)
        env.exitcode(2)
        return
      end
    end
    if not all then
      env.err.print("error: verify-source-shape requires --all")
      Help.verify_source_shape(env)
      env.exitcode(2)
      return
    end
    NativeBoon.verify_source_shape_command(env, report)

  fun _command_flow(env: Env) =>
    if _has_help(env) then
      Help.flow(env)
      return
    end

    try
      let file = env.args(2)?
      var report: String = ""
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--report" then
            report = env.args(index + 1)?
            index = index + 2
          else
            env.err.print("error: unknown flow option: " + arg)
            Help.flow(env)
            env.exitcode(2)
            return
          end
        else
          env.err.print("error: flow option is missing a value")
          Help.flow(env)
          env.exitcode(2)
          return
        end
      end
      NativeBoon.flow_command(env, file, report)
    else
      env.err.print("error: flow requires a Boon source file")
      Help.flow(env)
      env.exitcode(2)
    end

  fun _command_compile(env: Env) =>
    _command_codegen_project(env, "compile")

  fun _command_build(env: Env) =>
    _command_codegen_project(env, "build")

  fun _command_protocol_smoke(env: Env) =>
    _command_codegen_project(env, "protocol-smoke")

  fun _command_codegen_project(env: Env, tool: String) =>
    if _has_help(env) then
      _codegen_help(env, tool)
      return
    end

    try
      let project = env.args(2)?
      var report: String = ""
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--report" then
            report = env.args(index + 1)?
            index = index + 2
          else
            env.err.print("error: unknown " + tool + " option: " + arg)
            _codegen_help(env, tool)
            env.exitcode(2)
            return
          end
        else
          env.err.print("error: " + tool + " option is missing a value")
          _codegen_help(env, tool)
          env.exitcode(2)
          return
        end
      end
      if tool == "compile" then
        NativeCodegen.compile_command(env, project, report)
      elseif tool == "build" then
        NativeCodegen.build_command(env, project, report)
      else
        NativeCodegen.protocol_smoke_command(env, project, report)
      end
    else
      env.err.print("error: " + tool + " requires an example project")
      _codegen_help(env, tool)
      env.exitcode(2)
    end

  fun _codegen_help(env: Env, tool: String) =>
    if tool == "compile" then
      Help.compile(env)
    elseif tool == "build" then
      Help.build(env)
    else
      Help.protocol_smoke(env)
    end

  fun _command_verify(env: Env) =>
    if _has_help(env) then
      Help.verify(env)
      return
    end

    var target: String = ""
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        elseif target == "" then
          target = arg
          index = index + 1
        else
          env.err.print("error: unknown verify option: " + arg)
          Help.verify(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify option is missing a value")
        Help.verify(env)
        env.exitcode(2)
        return
      end
    end

    if target == "" then
      env.err.print("error: verify requires --all, an example directory, or an expected file")
      Help.verify(env)
      env.exitcode(2)
      return
    end

    if report == "" then
      report = "build/reports/verify.json"
    end
    NativeBoon.verify_expected_command(env, target, report)

  fun _command_snapshot(env: Env) =>
    if _has_help(env) then
      Help.snapshot(env)
      return
    end

    try
      let project = env.args(2)?
      var size: String = "80x24"
      var frames: USize = 120
      var report: String = ""
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--size" then
            size = env.args(index + 1)?
            index = index + 2
          elseif arg == "--frames" then
            frames = env.args(index + 1)?.usize()?
            index = index + 2
          elseif arg == "--report" then
            report = env.args(index + 1)?
            index = index + 2
          else
            env.err.print("error: unknown snapshot option: " + arg)
            Help.snapshot(env)
            env.exitcode(2)
            return
          end
        else
          env.err.print("error: snapshot option is missing a value")
          Help.snapshot(env)
          env.exitcode(2)
          return
        end
      end
      NativeBoon.snapshot_command(env, project, size, frames, report)
    else
      env.err.print("error: snapshot requires an example project")
      Help.snapshot(env)
      env.exitcode(2)
    end

  fun _command_verify_terminal(env: Env) =>
    if _has_help(env) then
      Help.verify_terminal(env)
      return
    end

    var target: String = ""
    var filter: String = ""
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        elseif arg == "--filter" then
          filter = env.args(index + 1)?
          index = index + 2
        elseif target == "" then
          target = arg
          index = index + 1
        else
          env.err.print("error: unknown verify-terminal option: " + arg)
          Help.verify_terminal(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify-terminal option is missing a value")
        Help.verify_terminal(env)
        env.exitcode(2)
        return
      end
    end

    if (target == "") and (filter == "") then
      env.err.print("error: verify-terminal requires an example project, --all, or --filter <name>")
      Help.verify_terminal(env)
      env.exitcode(2)
      return
    end

    if report != "" then
      None
    else
      if target == "--all" then
        report = "build/reports/verify-terminal-all.json"
      end
    end
    NativeBoon.verify_terminal_command(env, target, filter, report)

  fun _command_verify_terminal_safety(env: Env) =>
    if _has_help(env) then
      Help.verify_terminal_safety(env)
      return
    end

    var pty = false
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--pty" then
          pty = true
          index = index + 1
        elseif arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        else
          env.err.print("error: unknown verify-terminal-safety option: " + arg)
          Help.verify_terminal_safety(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify-terminal-safety option is missing a value")
        Help.verify_terminal_safety(env)
        env.exitcode(2)
        return
      end
    end
    NativeSafety.verify_command(env, pty, report)

  fun _command_verify_pty(env: Env) =>
    if _has_help(env) then
      Help.verify_pty(env)
      return
    end
    var report: String = ""
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--report" then
          report = env.args(index + 1)?
          index = index + 2
        elseif arg == "--all" then
          index = index + 1
        else
          env.err.print("error: unknown verify-pty option: " + arg)
          Help.verify_pty(env)
          env.exitcode(2)
          return
        end
      else
        env.err.print("error: verify-pty option is missing a value")
        Help.verify_pty(env)
        env.exitcode(2)
        return
      end
    end
    NativePty.verify_command(env, report)

  fun _command_bench(env: Env) =>
    if _has_help(env) then
      Help.bench(env)
      return
    end
    NativeBoon.bench_command(env)

  fun _has_help(env: Env): Bool =>
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if (arg == "--help") or (arg == "-h") then
          return true
        end
      end
      index = index + 1
    end
    false

  fun _has_arg(env: Env, expected: String): Bool =>
    var index: USize = 2
    while index < env.args.size() do
      try
        if env.args(index)? == expected then
          return true
        end
      end
      index = index + 1
    end
    false

  fun _run_tool(env: Env, command: String box) =>
    let status = @system(command.cstring())
    if status == 0 then
      env.exitcode(0)
    elseif status > 255 then
      env.exitcode(status / 256)
    else
      env.exitcode(status)
    end

  fun _not_implemented(env: Env, command: String) =>
    env.err.print("error: command not implemented yet: " + command)
    env.err.print("The current implementation is complete through Phase 12; continue with BOON_PONY_TUI_PLAN.md final gate work.")
    env.exitcode(1)

primitive Help
  fun root(env: Env) =>
    env.out.print("boonpony - native Pony backend for Boon")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony --help")
    env.out.print("  boonpony tui [--help] [--example <name>] [--script <path>]")
    env.out.print("  boonpony play [--help] <project>")
    env.out.print("  boonpony manifest --check")
    env.out.print("  boonpony import-upstream --source <path-or-git-url> --commit <sha>")
    env.out.print("  boonpony parse <file>")
    env.out.print("  boonpony verify-parser --corpus fixtures/corpus_manifest.json")
    env.out.print("  boonpony verify-source-shape --all")
    env.out.print("  boonpony flow <file>")
    env.out.print("  boonpony compile <project>")
    env.out.print("  boonpony build <project>")
    env.out.print("  boonpony protocol-smoke <project>")
    env.out.print("  boonpony verify <project-or---all>")
    env.out.print("  boonpony verify-terminal <project-or---all> [--filter playground]")
    env.out.print("  boonpony verify-terminal-safety --pty")
    env.out.print("  boonpony verify-pty --all")
    env.out.print("  boonpony snapshot <project> --size 80x24 --frames 120")
    env.out.print("  boonpony bench <project-or---all>")
    env.out.print("")
    env.out.print("Source of truth:")
    env.out.print("  BOON_PONY_TUI_PLAN.md")

  fun tui(env: Env) =>
    env.out.print("boonpony tui - full-screen terminal playground")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony tui")
    env.out.print("  boonpony tui --keyboard-test")
    env.out.print("  boonpony tui --example pong")
    env.out.print("  boonpony tui --script tests/examples/terminal_playground_sequence.json")
    env.out.print("")
    env.out.print("Phase 12 status:")
    env.out.print("  The playground supports full-screen mode, scripted replay, PTY verification, and source editing.")
    env.out.print("  Source keys: e edit, v valid edit, ! invalid edit, r reload, b rebuild, p rerun, d diff, o editor.")

  fun play(env: Env) =>
    env.out.print("boonpony play - build and run a generated terminal app")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony play examples/terminal/pong")
    env.out.print("  boonpony play examples/terminal/arkanoid")

  fun manifest(env: Env) =>
    env.out.print("boonpony manifest - inspect generated corpus manifests")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony manifest --check")

  fun import_upstream(env: Env) =>
    env.out.print("boonpony import-upstream - import the pinned upstream Boon example corpus")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony import-upstream --source https://github.com/BoonLang/boon --commit <sha>")

  fun parse(env: Env) =>
    env.out.print("boonpony parse - parse one Boon source file")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony parse examples/source_physical/pong/pong.bn")
    env.out.print("  boonpony parse tests/parser/legacy_link_rejected.bn")

  fun verify_parser(env: Env) =>
    env.out.print("boonpony verify-parser - parse every source in a corpus manifest")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify-parser --corpus fixtures/corpus_manifest.json")

  fun verify_source_shape(env: Env) =>
    env.out.print("boonpony verify-source-shape - extract canonical SOURCE slots")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify-source-shape --all")

  fun flow(env: Env) =>
    env.out.print("boonpony flow - lower a Boon source file to source-shape Flow IR")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony flow examples/source_physical/counter/counter.bn")

  fun compile(env: Env) =>
    env.out.print("boonpony compile - generate Pony source for a Boon project")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony compile examples/terminal/counter")

  fun build(env: Env) =>
    env.out.print("boonpony build - compile generated Pony source to a native binary")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony build examples/terminal/counter")

  fun protocol_smoke(env: Env) =>
    env.out.print("boonpony protocol-smoke - verify generated JSONL protocol mode")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony protocol-smoke examples/terminal/counter")

  fun verify(env: Env) =>
    env.out.print("boonpony verify - run expected-file contract checks")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify --all --report build/reports/verify.json")
    env.out.print("  boonpony verify examples/upstream/counter")

  fun snapshot(env: Env) =>
    env.out.print("boonpony snapshot - render a headless terminal grid snapshot")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony snapshot examples/terminal/counter --size 80x24 --frames 3")

  fun verify_terminal(env: Env) =>
    env.out.print("boonpony verify-terminal - verify terminal grid fixtures")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify-terminal examples/terminal/counter")
    env.out.print("  boonpony verify-terminal --filter playground")
    env.out.print("  boonpony verify-terminal --all --report build/reports/verify-terminal.json")

  fun verify_terminal_safety(env: Env) =>
    env.out.print("boonpony verify-terminal-safety - verify raw input and terminal restoration")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify-terminal-safety --pty")

  fun verify_pty(env: Env) =>
    env.out.print("boonpony verify-pty - run real PTY smoke proofs")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony verify-pty --all --report build/reports/verify-pty.json")

  fun bench(env: Env) =>
    env.out.print("boonpony bench - run deterministic runtime benchmarks")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony bench examples/terminal/pong --scenario frame --frames 10000")
