class val Color
  let name: String

  new val create(name': String) =>
    name = name'

class val Style
  let fg: Color val
  let bg: Color val
  let bold: Bool
  let italic: Bool
  let underline: Bool
  let inverse: Bool

  new val create(
    fg': Color val,
    bg': Color val,
    bold': Bool = false,
    italic': Bool = false,
    underline': Bool = false,
    inverse': Bool = false)
  =>
    fg = fg'
    bg = bg'
    bold = bold'
    italic = italic'
    underline = underline'
    inverse = inverse'

class val Cell
  let glyph: String
  let fg: Color val
  let bg: Color val
  let bold: Bool
  let italic: Bool
  let underline: Bool
  let inverse: Bool

  new val create(glyph': String, style: Style val) =>
    glyph = glyph'
    fg = style.fg
    bg = style.bg
    bold = style.bold
    italic = style.italic
    underline = style.underline
    inverse = style.inverse

class ref CellGrid
  let width: USize
  let height: USize
  var _cells: Array[Cell val] ref

  new create(width': USize, height': USize, fill: Cell val) =>
    width = width'
    height = height'
    _cells = Array[Cell val](width * height)
    var index: USize = 0
    while index < (width * height) do
      _cells.push(fill)
      index = index + 1
    end

  fun ref put(x: I64, y: I64, cell: Cell val) =>
    try
      _cells.update(_index(x, y)?, cell)?
    end

  fun ref text(x: I64, y: I64, text': String, style: Style val) =>
    put(x, y, Cell(text', style))

  fun ref rect(x: I64, y: I64, width': I64, height': I64, glyph: String, style: Style val) =>
    var row: I64 = 0
    while row < height' do
      var col: I64 = 0
      while col < width' do
        put(x + col, y + row, Cell(glyph, style))
        col = col + 1
      end
      row = row + 1
    end

  fun ref clear(cell: Cell val) =>
    var index: USize = 0
    while index < _cells.size() do
      try
        _cells.update(index, cell)?
      end
      index = index + 1
    end

  fun apply(x: I64, y: I64): Cell val ? =>
    _cells(_index(x, y)?)?

  fun render_text(): String =>
    let out = String
    var y: USize = 0
    while y < height do
      if y > 0 then out.append("\n") end
      var x: USize = 0
      while x < width do
        try
          out.append(_cells((y * width) + x)?.glyph)
        end
        x = x + 1
      end
      y = y + 1
    end
    out.clone()

  fun changed_cells(previous: CellGrid box): USize =>
    if (previous.width != width) or (previous.height != height) then
      return width * height
    end
    var changed: USize = 0
    var index: USize = 0
    while index < _cells.size() do
      try
        let current = _cells(index)?
        let old = previous._cells(index)?
        if (current.glyph != old.glyph) or
          (current.fg.name != old.fg.name) or
          (current.bg.name != old.bg.name) or
          (current.bold != old.bold) or
          (current.italic != old.italic) or
          (current.underline != old.underline) or
          (current.inverse != old.inverse)
        then
          changed = changed + 1
        end
      end
      index = index + 1
    end
    changed

  fun _index(x: I64, y: I64): USize ? =>
    if (x < 0) or (y < 0) then error end
    let ux = x.usize()
    let uy = y.usize()
    if (ux >= width) or (uy >= height) then error end
    (uy * width) + ux

primitive AnsiRenderer
  fun full(grid: CellGrid box): String =>
    let out = String
    out.append("\x1B[H\x1B[2J")
    var y: USize = 0
    while y < grid.height do
      var x: USize = 0
      while x < grid.width do
        try
          let cell = grid(x.i64(), y.i64())?
          out.append(_cursor(x, y))
          out.append(_style(cell))
          out.append(cell.glyph)
        end
        x = x + 1
      end
      y = y + 1
    end
    out.append("\x1B[0m")
    out.clone()

  fun diff(previous: CellGrid box, current: CellGrid box): String =>
    if (previous.width != current.width) or (previous.height != current.height) then
      return full(current)
    end
    let out = String
    var y: USize = 0
    while y < current.height do
      var x: USize = 0
      while x < current.width do
        try
          let old = previous(x.i64(), y.i64())?
          let cell = current(x.i64(), y.i64())?
          if _changed(old, cell) then
            out.append(_cursor(x, y))
            out.append(_style(cell))
            out.append(cell.glyph)
          end
        end
        x = x + 1
      end
      y = y + 1
    end
    if out.size() > 0 then out.append("\x1B[0m") end
    out.clone()

  fun _changed(old: Cell val, cell: Cell val): Bool =>
    (old.glyph != cell.glyph) or
      (old.fg.name != cell.fg.name) or
      (old.bg.name != cell.bg.name) or
      (old.bold != cell.bold) or
      (old.italic != cell.italic) or
      (old.underline != cell.underline) or
      (old.inverse != cell.inverse)

  fun _cursor(x: USize, y: USize): String =>
    "\x1B[" + (y + 1).string() + ";" + (x + 1).string() + "H"

  fun _style(cell: Cell val): String =>
    let out = String
    out.append("\x1B[0")
    if cell.bold then out.append(";1") end
    if cell.italic then out.append(";3") end
    if cell.underline then out.append(";4") end
    if cell.inverse then out.append(";7") end
    out.append(";")
    out.append(_fg_code(cell.fg.name))
    out.append(";")
    out.append(_bg_code(cell.bg.name))
    out.append("m")
    out.clone()

  fun _fg_code(name: String): String =>
    match name
    | "black" => "30"
    | "red" => "31"
    | "green" => "32"
    | "yellow" => "33"
    | "blue" => "34"
    | "magenta" => "35"
    | "cyan" => "36"
    else
      "37"
    end

  fun _bg_code(name: String): String =>
    match name
    | "black" => "40"
    | "red" => "41"
    | "green" => "42"
    | "yellow" => "43"
    | "blue" => "44"
    | "magenta" => "45"
    | "cyan" => "46"
    else
      "40"
    end
