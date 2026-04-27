#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const ROOT = process.cwd();

function usage() {
  console.error("Usage:");
  console.error("  node tools/parse_boon.mjs parse <file> [--report <path>]");
  console.error("  node tools/parse_boon.mjs verify-parser --corpus <manifest> [--report <path>]");
  process.exit(2);
}

function now() {
  return new Date().toISOString();
}

function toolchain() {
  let ponyc = "unknown";
  try {
    ponyc = execFileSync("ponyc", ["--version"], { encoding: "utf8" }).trim().split(/\n/)[0] ?? "unknown";
  } catch {
    try {
      ponyc = execFileSync("/home/martinkavik/.local/share/ponyup/bin/ponyc", ["--version"], { encoding: "utf8" }).trim().split(/\n/)[0] ?? "unknown";
    } catch {
      ponyc = "not found";
    }
  }
  return { ponyc, os: `${process.platform}-${process.arch}` };
}

function ensureParent(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function writeReport(file, report) {
  ensureParent(file);
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
}

class ParseError extends Error {
  constructor(message, token = null, code = "parse_error") {
    super(message);
    this.token = token;
    this.code = code;
  }
}

function locFor(text, offset) {
  let line = 1;
  let column = 1;
  for (let index = 0; index < offset; index += 1) {
    if (text.charCodeAt(index) === 10) {
      line += 1;
      column = 1;
    } else {
      column += 1;
    }
  }
  return { line, column, offset };
}

function token(type, value, start, end, text) {
  return { type, value, start, end, ...locFor(text, start) };
}

function isAlpha(ch) {
  return /[A-Za-z_]/.test(ch);
}

function isIdent(ch) {
  return /[A-Za-z0-9_]/.test(ch);
}

function lex(text) {
  const tokens = [];
  let index = 0;
  while (index < text.length) {
    const ch = text[index];
    const next = text[index + 1] ?? "";

    if (ch === " " || ch === "\t" || ch === "\r" || ch === "\n") {
      index += 1;
      continue;
    }
    if (ch === "-" && next === "-") {
      while (index < text.length && text[index] !== "\n") index += 1;
      continue;
    }
    if (isAlpha(ch)) {
      const start = index;
      index += 1;
      while (index < text.length && isIdent(text[index])) index += 1;
      const value = text.slice(start, index);
      tokens.push(token("ident", value, start, index, text));
      if (value === "TEXT") {
        index = lexTextLiteralIfPresent(text, index, tokens);
      }
      continue;
    }
    if (/[0-9]/.test(ch)) {
      const start = index;
      index += 1;
      while (index < text.length && /[A-Za-z0-9_.-]/.test(text[index])) index += 1;
      tokens.push(token("number", text.slice(start, index), start, index, text));
      continue;
    }

    const two = text.slice(index, index + 2);
    if (["|>", "=>", "==", ">=", "<=", "!=", "&&", "||"].includes(two)) {
      tokens.push(token("symbol", two, index, index + 2, text));
      index += 2;
      continue;
    }
    if ("[]{}(),:.;+-*/%<>=".includes(ch)) {
      tokens.push(token("symbol", ch, index, index + 1, text));
      index += 1;
      continue;
    }
    throw new ParseError(`unexpected character ${JSON.stringify(ch)}`, token("char", ch, index, index + 1, text));
  }
  tokens.push({ type: "eof", value: "<eof>", start: text.length, end: text.length, ...locFor(text, text.length) });
  return tokens;
}

function lexTextLiteralIfPresent(text, index, tokens) {
  let cursor = index;
  while (cursor < text.length && /[ \t\r\n]/.test(text[cursor])) cursor += 1;
  if (text[cursor] !== "{") return index;

  const openStart = cursor;
  tokens.push(token("symbol", "{", openStart, openStart + 1, text));
  cursor += 1;
  const rawStart = cursor;
  let depth = 1;
  while (cursor < text.length && depth > 0) {
    if (text[cursor] === "{") {
      depth += 1;
    } else if (text[cursor] === "}") {
      depth -= 1;
      if (depth === 0) break;
    }
    cursor += 1;
  }
  if (depth !== 0) {
    throw new ParseError("unterminated TEXT literal", token("text", text.slice(rawStart), rawStart, text.length, text));
  }
  if (cursor > rawStart) {
    tokens.push(token("text", text.slice(rawStart, cursor), rawStart, cursor, text));
  }
  tokens.push(token("symbol", "}", cursor, cursor + 1, text));
  return cursor + 1;
}

class Parser {
  constructor(file, text, tokens) {
    this.file = file;
    this.text = text;
    this.tokens = tokens;
    this.index = 0;
    this.ast = { type: "Program", declarations: [], tokens: tokens.length - 1 };
  }

  current() {
    return this.tokens[this.index];
  }

  peek(offset = 1) {
    return this.tokens[this.index + offset] ?? this.tokens[this.tokens.length - 1];
  }

  at(value) {
    return this.current().value === value;
  }

  consume(value = null) {
    const tok = this.current();
    if (value !== null && tok.value !== value) {
      throw new ParseError(`expected ${value}, found ${tok.value}`, tok);
    }
    this.index += 1;
    return tok;
  }

  parse() {
    this.checkCanonicalSourceDiagnostics();
    while (this.current().type !== "eof") {
      if (this.at("FUNCTION")) {
        this.ast.declarations.push(this.parseFunction());
      } else if (this.current().type === "ident" && this.peek().value === ":") {
        this.ast.declarations.push(this.parseDeclaration());
      } else {
        throw new ParseError("expected top-level declaration or FUNCTION", this.current());
      }
    }
    return this.ast;
  }

  parseFunction() {
    const start = this.consume("FUNCTION");
    const name = this.consumeIdent("function name");
    this.consumeBalanced("(", ")");
    this.consumeBalanced("{", "}");
    return { type: "Function", name: name.value, span: [start.start, this.tokens[this.index - 1].end] };
  }

  parseDeclaration() {
    const name = this.consumeIdent("declaration name");
    this.consume(":");
    const start = this.index;
    this.consumeExpressionUntilTopLevel();
    return { type: "Declaration", name: name.value, token_start: start, token_end: this.index };
  }

  consumeIdent(label) {
    const tok = this.current();
    if (tok.type !== "ident") {
      throw new ParseError(`expected ${label}`, tok);
    }
    return this.consume();
  }

  consumeExpressionUntilTopLevel() {
    let depth = 0;
    let consumed = false;
    while (this.current().type !== "eof") {
      const tok = this.current();
      if (depth === 0 && tok.type === "ident" && this.peek().value === ":") {
        if (consumed) return;
      }
      if (depth === 0 && tok.value === "FUNCTION") {
        if (consumed) return;
      }
      this.consumeOneBalancedToken();
      consumed = true;
      depth = 0;
    }
    if (!consumed) {
      throw new ParseError("expected expression", this.current());
    }
  }

  consumeBalanced(open, close) {
    this.consume(open);
    while (!this.at(close)) {
      if (this.current().type === "eof") {
        throw new ParseError(`unterminated ${open}`, this.current());
      }
      this.consumeOneBalancedToken();
    }
    this.consume(close);
  }

  consumeOneBalancedToken() {
    const tok = this.current();
    if (tok.value === "(") {
      this.consumeBalanced("(", ")");
    } else if (tok.value === "[") {
      this.consumeBalanced("[", "]");
    } else if (tok.value === "{") {
      this.consumeBalanced("{", "}");
    } else if ([")", "]", "}"].includes(tok.value)) {
      throw new ParseError(`unmatched ${tok.value}`, tok);
    } else {
      this.consume();
    }
  }

  checkCanonicalSourceDiagnostics() {
    for (let i = 0; i < this.tokens.length; i += 1) {
      const tok = this.tokens[i];
      if (tok.value === "LINK") {
        throw new ParseError("`LINK` was renamed to `SOURCE`; use `SOURCE` in canonical source mode", tok, "legacy_link");
      }
      if (tok.value === "SOURCE") {
        const prev = this.tokens[i - 1]?.value ?? "";
        const next = this.tokens[i + 1]?.value ?? "";
        if (["+", "-", "*", "/", "%", "==", "!=", ">=", "<=", ">", "<"].includes(next) ||
            (["+", "-", "*", "/", "%", "==", "!=", ">=", "<=", ">", "<"].includes(prev) && prev !== "|>")) {
          throw new ParseError("SOURCE marks a runtime source field and cannot be used as a normal value", tok, "source_as_value");
        }
      }
      if (tok.value === "event" && this.tokens[i + 1]?.value === ":" && this.tokens[i + 2]?.value === "SOURCE") {
        throw new ParseError("incompatible source binding", this.tokens[i + 2], "incompatible_source_binding");
      }
    }
  }
}

function parseFile(file) {
  const text = fs.readFileSync(file, "utf8");
  const tokens = lex(text);
  const ast = new Parser(file, text, tokens).parse();
  return {
    file,
    status: "pass",
    ast_summary: {
      declarations: ast.declarations.length,
      functions: ast.declarations.filter((d) => d.type === "Function").length,
      tokens: ast.tokens
    }
  };
}

function failure(file, error) {
  const tokenInfo = error.token ? {
    line: error.token.line,
    column: error.token.column,
    offset: error.token.offset,
    value: error.token.value
  } : null;
  return {
    file,
    status: "fail",
    code: error.code ?? "parse_error",
    message: error.message,
    location: tokenInfo
  };
}

function commandParse(args) {
  const file = args[0];
  if (!file) usage();
  let reportPath = null;
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--report") {
      reportPath = args[++i];
    } else {
      usage();
    }
  }

  const started = now();
  let result;
  try {
    result = parseFile(file);
  } catch (error) {
    result = failure(file, error);
  }
  const report = {
    command: "parse",
    status: result.status,
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [result],
    failures: result.status === "pass" ? [] : [result]
  };
  if (reportPath) writeReport(reportPath, report);
  if (result.status === "pass") {
    console.log(`parse ok: ${file}`);
    process.exit(0);
  }
  console.error(`${file}:${result.location?.line ?? 0}:${result.location?.column ?? 0}: error: ${result.message}`);
  process.exit(1);
}

function commandVerifyParser(args) {
  let corpus = null;
  let reportPath = "build/reports/verify-parser.json";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--corpus") {
      corpus = args[++i];
    } else if (args[i] === "--report") {
      reportPath = args[++i];
    } else {
      usage();
    }
  }
  if (!corpus) usage();

  const started = now();
  const manifest = JSON.parse(fs.readFileSync(corpus, "utf8"));
  const files = [];
  for (const example of manifest.examples ?? []) {
    for (const file of example.bn_files ?? []) files.push(file);
  }

  const cases = [];
  for (const file of files) {
    try {
      cases.push(parseFile(file));
    } catch (error) {
      cases.push(failure(file, error));
    }
  }
  const failures = cases.filter((c) => c.status !== "pass");
  const report = {
    command: "verify-parser",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    corpus,
    cases,
    failures
  };
  writeReport(reportPath, report);
  if (failures.length === 0) {
    console.log(`parser ok: ${cases.length} files`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const item of failures.slice(0, 10)) {
    console.error(`${item.file}:${item.location?.line ?? 0}:${item.location?.column ?? 0}: error: ${item.message}`);
  }
  console.error(`parser failed: ${failures.length}/${cases.length} files`);
  console.error(`report: ${reportPath}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
if (command === "parse") commandParse(args);
else if (command === "verify-parser") commandVerifyParser(args);
else usage();
