actor Main
  new create(env: Env) =>
    let state = BrowserAbi.boon_browser_state_new()
    let _ = BrowserAbi.boon_browser_state_init(state, 960, 720, 1000)
    let _ = BrowserAbi.boon_browser_state_select_example(state, 0, 0)
    let _ = BrowserAbi.boon_browser_state_input(state, 0, 0)
    let _ = BrowserAbi.boon_browser_state_tick(state, 16)
    let _ = BrowserAbi.boon_browser_state_scene_ptr(state)
    let _ = BrowserAbi.boon_browser_state_scene_len(state)
    env.out.print("boonpony browser wasm runtime probe")

class BrowserState
  var _counter: U32 = 0
  var _scene: String = ""

  new create() =>
    _render()

  fun ref init(width: U32, height: U32, scale_milli: U32): I32 =>
    if (width == 0) or (height == 0) or (scale_milli == 0) then
      1
    else
      _render()
      0
    end

  fun ref select_example(ptr: U32, len: U32): I32 =>
    (let ignore_ptr, let ignore_len) = (ptr, len)
    _counter = 0
    _render()
    0

  fun ref input(ptr: U32, len: U32): I32 =>
    (let ignore_ptr, let ignore_len) = (ptr, len)
    _counter = _counter + 1
    _render()
    0

  fun ref tick(delta_ms: U32): I32 =>
    let ignore_delta_ms = delta_ms
    _render()
    0

  fun box scene_ptr(): Pointer[U8] tag =>
    _scene.cstring()

  fun box scene_len(): U32 =>
    _scene.size().u32()

  fun ref _render() =>
    let out = String
    out.append("{\"viewport\":{\"width\":960,\"height\":720},")
    out.append("\"semantic_ids\":[\"toolbar.run\",\"toolbar.clear\",\"examples\",\"viewport\",\"source\",\"counter.value\"],")
    out.append("\"hit_regions\":[")
    out.append("{\"id\":\"toolbar.run\",\"x\":272,\"y\":9,\"w\":42,\"h\":30},")
    out.append("{\"id\":\"toolbar.clear\",\"x\":322,\"y\":9,\"w\":94,\"h\":30},")
    out.append("{\"id\":\"viewport\",\"x\":220,\"y\":48,\"w\":960,\"h\":720}],")
    out.append("\"draw\":[")
    out.append("{\"kind\":\"rect\",\"x\":0,\"y\":0,\"w\":960,\"h\":720,\"fill\":\"#102018\"},")
    out.append("{\"kind\":\"text\",\"x\":24,\"y\":48,\"fill\":\"#7ff0a6\",\"size\":18,\"text\":\"Generated Pony is running inside browser WebAssembly.\"},")
    out.append("{\"kind\":\"text\",\"x\":24,\"y\":86,\"fill\":\"#d7ffe1\",\"size\":15,\"text\":\"Scene metadata, semantic IDs, hit regions, and counter state came from Pony wasm.\"},")
    out.append("{\"kind\":\"rect\",\"x\":24,\"y\":122,\"w\":240,\"h\":64,\"fill\":\"#1f3a2a\"},")
    out.append("{\"kind\":\"text\",\"x\":42,\"y\":160,\"fill\":\"#ffffff\",\"size\":18,\"text\":\"Counter: ")
    out.append(_counter.string())
    out.append("\"}],")
    out.append("\"source\":\"button: [event: [press: SOURCE]]\\\\n  |> SOURCE { store.elements.add_button }\\\\n\\\\nBrowser renderer: Canvas2D\\\\nRuntime: Pony WebAssembly worker\\\\nCounter state: ")
    out.append(_counter.string())
    out.append("\"}")
    _scene = out.clone()

primitive BrowserAbi
  fun @boon_browser_state_new(): BrowserState ref =>
    BrowserState

  fun @boon_browser_state_init(state: BrowserState ref, width: U32, height: U32, scale_milli: U32): I32 =>
    state.init(width, height, scale_milli)

  fun @boon_browser_state_select_example(state: BrowserState ref, ptr: U32, len: U32): I32 =>
    state.select_example(ptr, len)

  fun @boon_browser_state_input(state: BrowserState ref, ptr: U32, len: U32): I32 =>
    state.input(ptr, len)

  fun @boon_browser_state_tick(state: BrowserState ref, delta_ms: U32): I32 =>
    state.tick(delta_ms)

  fun @boon_browser_state_scene_ptr(state: BrowserState box): Pointer[U8] tag =>
    state.scene_ptr()

  fun @boon_browser_state_scene_len(state: BrowserState box): U32 =>
    state.scene_len()
