actor Main
  new create(env: Env) =>
    if _has_arg(env, "--protocol") then
      _protocol(env)
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

  fun _direct(env: Env) =>
    env.out.print("Counter: 0")
    env.out.print("[Enter] increments")

  fun _protocol(env: Env) =>
    env.out.print("{\"protocol_version\":1,\"type\":\"ready\",\"app\":\"counter\"}")
    env.out.print("{\"protocol_version\":1,\"type\":\"frame\",\"revision\":0,\"width\":80,\"height\":24,\"runs\":[{\"x\":2,\"y\":2,\"text\":\"Counter: 0\",\"fg\":\"white\",\"bg\":\"black\",\"bold\":false,\"underline\":false,\"inverse\":false}]}")
    env.out.print("{\"protocol_version\":1,\"type\":\"tree\",\"revision\":0,\"tree\":{\"id\":\"counter.canvas\",\"role\":\"terminal_canvas\",\"text\":\"Counter: 0\",\"visible\":true,\"children\":[{\"id\":\"counter.label\",\"role\":\"canvas_text\",\"text\":\"Counter: 0\",\"visible\":true,\"children\":[]}]}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"metrics\",\"revision\":0,\"metrics\":{\"frames\":1,\"events\":0}}")
    env.out.print("{\"protocol_version\":1,\"type\":\"bye\"}")
