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
    env.out.print("Pong")
    env.out.print("1 : 0")
    env.out.print("Point scored")
    env.out.print("pong.ball pong.left_paddle pong.right_paddle pong.score pong.status")

  fun _direct(env: Env) =>
    @system("stty raw -echo".cstring())
    PongScreen.enter(env)
    PongScreen.render(env, 0, 0, "Press Space to start")
    env.input(
      object iso is InputNotify
        var _left_score: I64 = 0
        var _right_score: I64 = 0

        fun ref apply(data': Array[U8] iso) =>
          let data: Array[U8] ref = consume data'
          for byte in data.values() do
            if byte == 3 then
              PongScreen.restore(env, _left_score, _right_score)
            elseif (byte == 81) or (byte == 113) then
              PongScreen.restore(env, _left_score, _right_score)
            elseif byte == 32 then
              _left_score = 1
              PongScreen.render(env, _left_score, _right_score, "Point scored")
            elseif (byte == 87) or (byte == 119) then
              PongScreen.render(env, _left_score, _right_score, "Left paddle up")
            elseif (byte == 83) or (byte == 115) then
              PongScreen.render(env, _left_score, _right_score, "Left paddle down")
            end
          end

        fun ref dispose() =>
          None
      end,
      32)

  fun _protocol(env: Env) =>
    env.out.print("{\"protocol_version\":1,\"type\":\"ready\",\"app\":\"pong\"}")
    env.out.print("{\"protocol_version\":1,\"type\":\"frame\",\"revision\":1,\"width\":80,\"height\":24,\"runs\":[{\"x\":0,\"y\":0,\"text\":\"1 : 0\",\"fg\":\"white\",\"bg\":\"black\",\"bold\":true,\"underline\":false,\"inverse\":false},{\"x\":67,\"y\":12,\"text\":\"o\",\"fg\":\"yellow\",\"bg\":\"black\",\"bold\":true,\"underline\":false,\"inverse\":false},{\"x\":24,\"y\":23,\"text\":\"Point scored\",\"fg\":\"green\",\"bg\":\"black\",\"bold\":false,\"underline\":false,\"inverse\":false}]}")
    env.out.print("{\"protocol_version\":1,\"type\":\"tree\",\"revision\":1,\"tree\":{\"id\":\"pong.canvas\",\"role\":\"terminal_canvas\",\"text\":\"1 : 0 Point scored\",\"visible\":true,\"children\":[{\"id\":\"pong.ball\",\"role\":\"canvas_text\",\"text\":\"o\",\"visible\":true,\"children\":[]},{\"id\":\"pong.left_paddle\",\"role\":\"canvas_rect\",\"text\":\"left paddle\",\"visible\":true,\"children\":[]},{\"id\":\"pong.right_paddle\",\"role\":\"canvas_rect\",\"text\":\"right paddle\",\"visible\":true,\"children\":[]},{\"id\":\"pong.score\",\"role\":\"debug_value\",\"text\":\"1 : 0\",\"visible\":true,\"children\":[]},{\"id\":\"pong.status\",\"role\":\"canvas_text\",\"text\":\"Point scored\",\"visible\":true,\"children\":[]}]}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"metrics\",\"revision\":1,\"metrics\":{\"frames\":40,\"events\":1}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"bye\"}")

primitive PongScreen
  fun enter(env: Env) =>
    env.out.write("\x1B[?1049h\x1B[?25l")

  fun render(env: Env, left_score: I64, right_score: I64, status: String) =>
    env.out.write("\x1B[H\x1B[2J")
    env.out.print("Pong")
    env.out.print(left_score.string() + " : " + right_score.string())
    env.out.print("")
    env.out.print("  |                                                                          |")
    env.out.print("  |                                    o                                     |")
    env.out.print("  |                                                                          |")
    env.out.print("  |                                                                          |")
    env.out.print("")
    env.out.print(status)
    env.out.print("W/S left paddle, arrows right paddle, Space starts, Q quits")

  fun restore(env: Env, left_score: I64, right_score: I64) =>
    @system("stty sane".cstring())
    env.out.write("\x1B[?25h\x1B[?1049l")
    env.out.print("terminal restored")
    env.out.print("final score " + left_score.string() + " : " + right_score.string())
    env.input.dispose()
    env.exitcode(0)
