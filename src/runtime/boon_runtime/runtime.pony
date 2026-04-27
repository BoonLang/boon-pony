class val RuntimeMetrics
  let revision: U64
  let frames: U64

  new val create(revision': U64, frames': U64) =>
    revision = revision'
    frames = frames'

class val TerminalRun
  let x: I64
  let y: I64
  let text: String
  let fg: String
  let bg: String
  let bold: Bool
  let underline: Bool
  let inverse: Bool

  new val create(
    x': I64,
    y': I64,
    text': String,
    fg': String = "white",
    bg': String = "black",
    bold': Bool = false,
    underline': Bool = false,
    inverse': Bool = false)
  =>
    x = x'
    y = y'
    text = text'
    fg = fg'
    bg = bg'
    bold = bold'
    underline = underline'
    inverse = inverse'

class val SemanticBounds
  let x: I64
  let y: I64
  let width: I64
  let height: I64

  new val create(x': I64, y': I64, width': I64, height': I64) =>
    x = x'
    y = y'
    width = width'
    height = height'
