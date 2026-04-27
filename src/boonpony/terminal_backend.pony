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

  fun _index(x: I64, y: I64): USize ? =>
    if (x < 0) or (y < 0) then error end
    let ux = x.usize()
    let uy = y.usize()
    if (ux >= width) or (uy >= height) then error end
    (uy * width) + ux
