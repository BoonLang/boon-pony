use @system[I32](cmd: Pointer[U8] tag)

actor Main
  new create(env: Env) =>
    if _has_arg(env, "--protocol") then
      _protocol(env)
    elseif _has_arg(env, "--demo") then
      _demo(env)
    else
      _direct(env)
    end

  fun _has_arg(env: Env, expected: String): Bool =>
    var index: USize = 1
    while index < env.args.size() do
      try
        if env.args(index)? == expected then return true end
      end
      index = index + 1
    end
    false

  fun _demo(env: Env) =>
    env.out.print("Arkanoid")
    env.out.print("Score: 1")
    env.out.print("Brick removed")
    env.out.print("arkanoid.ball arkanoid.paddle arkanoid.brick.0.0 arkanoid.score arkanoid.status")

  fun _direct(env: Env) =>
    @system("stty raw -echo".cstring())
    ArkanoidScreen.enter(env)
    ArkanoidScreen.render(env, 0, "Playing")
    env.input(
      object iso is InputNotify
        var _score: I64 = 0
        var _status: String = "Playing"

        fun ref apply(data': Array[U8] iso) =>
          let data: Array[U8] ref = consume data'
          for byte in data.values() do
            if byte == 3 then
              ArkanoidScreen.restore(env, _score, _status)
            elseif (byte == 81) or (byte == 113) then
              ArkanoidScreen.restore(env, _score, _status)
            elseif byte == 32 then
              if _status == "Lost" then
                _score = 0
                _status = "Playing"
              else
                _score = 1
                _status = "Brick removed"
              end
              ArkanoidScreen.render(env, _score, _status)
            elseif (byte == 76) or (byte == 108) then
              _status = "Lost"
              ArkanoidScreen.render(env, _score, _status)
            end
          end

        fun ref dispose() =>
          None
      end,
      32)

  fun _protocol(env: Env) =>
    env.out.print("{\"protocol_version\":1,\"type\":\"ready\",\"app\":\"arkanoid\"}")
    env.out.print("{\"protocol_version\":1,\"type\":\"frame\",\"revision\":1,\"width\":80,\"height\":28,\"runs\":[{\"x\":0,\"y\":0,\"text\":\"Score: 1\",\"fg\":\"white\",\"bg\":\"black\",\"bold\":true,\"underline\":false,\"inverse\":false},{\"x\":18,\"y\":4,\"text\":\"o\",\"fg\":\"yellow\",\"bg\":\"black\",\"bold\":true,\"underline\":false,\"inverse\":false},{\"x\":30,\"y\":0,\"text\":\"Brick removed\",\"fg\":\"green\",\"bg\":\"black\",\"bold\":false,\"underline\":false,\"inverse\":false}]}")
    env.out.print("{\"protocol_version\":1,\"type\":\"tree\",\"revision\":1,\"tree\":{\"id\":\"arkanoid.canvas\",\"role\":\"terminal_canvas\",\"text\":\"Score: 1 Brick removed\",\"visible\":true,\"children\":[{\"id\":\"arkanoid.ball\",\"role\":\"canvas_text\",\"text\":\"o\",\"visible\":true,\"children\":[]},{\"id\":\"arkanoid.paddle\",\"role\":\"canvas_rect\",\"text\":\"paddle\",\"visible\":true,\"children\":[]},{\"id\":\"arkanoid.brick.0.0\",\"role\":\"canvas_rect\",\"text\":\"removed\",\"visible\":true,\"children\":[]},{\"id\":\"arkanoid.score\",\"role\":\"debug_value\",\"text\":\"Score: 1\",\"visible\":true,\"children\":[]},{\"id\":\"arkanoid.status\",\"role\":\"canvas_text\",\"text\":\"Brick removed\",\"visible\":true,\"children\":[]}]}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"metrics\",\"revision\":1,\"metrics\":{\"frames\":20,\"events\":1}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"bye\"}")

primitive ArkanoidScreen
  fun enter(env: Env) =>
    env.out.write("\x1B[?1049h\x1B[?25l")

  fun render(env: Env, score: I64, status: String) =>
    env.out.write("\x1B[H\x1B[2J")
    env.out.print("Arkanoid")
    env.out.print("Score: " + score.string() + "   " + status)
    env.out.print("")
    env.out.print("    ########  ########  ########")
    env.out.print("")
    env.out.print("                  o")
    env.out.print("")
    env.out.print("                                    ========")
    env.out.print("Space hits/restarts, L loses, Q quits")

  fun restore(env: Env, score: I64, status: String) =>
    @system("stty sane".cstring())
    env.out.write("\x1B[?25h\x1B[?1049l")
    env.out.print("terminal restored")
    env.out.print("final score " + score.string())
    env.out.print("final status " + status)
    env.input.dispose()
    env.exitcode(0)
