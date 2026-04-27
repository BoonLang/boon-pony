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
      | "compile" => _not_implemented(env, "compile")
      | "build" => _not_implemented(env, "build")
      | "verify" => _not_implemented(env, "verify")
      | "verify-terminal" => _not_implemented(env, "verify-terminal")
      | "snapshot" => _not_implemented(env, "snapshot")
      | "bench" => _not_implemented(env, "bench")
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
      _not_implemented(env, "tui")
    end

  fun _command_play(env: Env) =>
    if _has_help(env) then
      Help.play(env)
    else
      try
        let project = env.args(2)?
        _not_implemented(env, "play " + project)
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
      _run_tool(env, "node tools/manifest_check.mjs")
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

      _run_tool(env, "node tools/import_upstream.mjs --source " + source + " --commit " + commit)

  fun _command_parse(env: Env) =>
    if _has_help(env) then
      Help.parse(env)
      return
    end

    try
      let file = env.args(2)?
      var command = "node tools/parse_boon.mjs parse " + file
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--report" then
            command = command + " --report " + env.args(index + 1)?
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
      _run_tool(env, consume command)
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

    var command = "node tools/parse_boon.mjs verify-parser --corpus " + corpus
    if report != "" then
      command = command + " --report " + report
    end
    _run_tool(env, consume command)

  fun _command_verify_source_shape(env: Env) =>
    if _has_help(env) then
      Help.verify_source_shape(env)
      return
    end

    var command = "node tools/source_shape.mjs verify-source-shape"
    var index: USize = 2
    while index < env.args.size() do
      try
        let arg = env.args(index)?
        if arg == "--all" then
          command = command + " --all"
          index = index + 1
        elseif arg == "--report" then
          command = command + " --report " + env.args(index + 1)?
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
    _run_tool(env, consume command)

  fun _command_flow(env: Env) =>
    if _has_help(env) then
      Help.flow(env)
      return
    end

    try
      let file = env.args(2)?
      var command = "node tools/source_shape.mjs flow " + file
      var index: USize = 3
      while index < env.args.size() do
        try
          let arg = env.args(index)?
          if arg == "--report" then
            command = command + " --report " + env.args(index + 1)?
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
      _run_tool(env, consume command)
    else
      env.err.print("error: flow requires a Boon source file")
      Help.flow(env)
      env.exitcode(2)
    end

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
    env.err.print("Phase 0 only provides the CLI bootstrap and help surface.")
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
    env.out.print("  boonpony verify <project-or---all>")
    env.out.print("  boonpony verify-terminal <project-or---all>")
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
    env.out.print("  boonpony tui --example pong")
    env.out.print("  boonpony tui --script tests/examples/terminal_playground_sequence.json")
    env.out.print("")
    env.out.print("Phase 0 status:")
    env.out.print("  Help is available; the interactive TUI is implemented in later phases.")

  fun play(env: Env) =>
    env.out.print("boonpony play - build and run a generated terminal app")
    env.out.print("")
    env.out.print("Usage:")
    env.out.print("  boonpony play examples/terminal/pong")
    env.out.print("  boonpony play examples/terminal/arkanoid")
    env.out.print("")
    env.out.print("Phase 0 status:")
    env.out.print("  Help is available; generated direct-play apps are implemented in later phases.")

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
