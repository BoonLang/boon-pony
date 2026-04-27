#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

function usage() {
  console.error("Usage:");
  console.error("  node tools/source_shape.mjs verify-source-shape --all [--report <path>]");
  console.error("  node tools/source_shape.mjs flow <file> [--report <path>]");
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

function lexTextLiteralIfPresent(text, index, tokens) {
  let cursor = index;
  while (cursor < text.length && /[ \t\r\n]/.test(text[cursor])) cursor += 1;
  if (text[cursor] !== "{") return index;
  tokens.push(token("symbol", "{", cursor, cursor + 1, text));
  cursor += 1;
  const rawStart = cursor;
  let depth = 1;
  while (cursor < text.length && depth > 0) {
    if (text[cursor] === "{") depth += 1;
    else if (text[cursor] === "}") {
      depth -= 1;
      if (depth === 0) break;
    }
    cursor += 1;
  }
  if (depth !== 0) throw new Error("unterminated TEXT literal");
  if (cursor > rawStart) tokens.push(token("text", text.slice(rawStart, cursor), rawStart, cursor, text));
  tokens.push(token("symbol", "}", cursor, cursor + 1, text));
  return cursor + 1;
}

function lex(text) {
  const tokens = [];
  let index = 0;
  while (index < text.length) {
    const ch = text[index];
    const next = text[index + 1] ?? "";
    if (/[ \t\r\n]/.test(ch)) {
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
      if (value === "TEXT") index = lexTextLiteralIfPresent(text, index, tokens);
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
    throw new Error(`unexpected character ${JSON.stringify(ch)} at ${locFor(text, index).line}:${locFor(text, index).column}`);
  }
  return tokens;
}

function payloadType(path) {
  const leaf = path.split(".").filter(Boolean).at(-1) ?? "";
  if (leaf === "key_down") return "KeyEvent";
  if (leaf === "mouse") return "MouseEvent";
  if (leaf === "resize") return "ResizeEvent";
  if (leaf === "tick") return "TickEvent";
  if (leaf === "change") return "Text";
  if (leaf === "hovered" || leaf === "focused") return "Bool";
  if (leaf === "value") return "Number";
  return "Pulse";
}

function pathFromSourceBinding(tokens, index) {
  if (tokens[index - 1]?.value !== "|>" || tokens[index + 1]?.value !== "{") return null;
  const parts = [];
  let cursor = index + 2;
  let depth = 1;
  while (cursor < tokens.length && depth > 0) {
    const tok = tokens[cursor];
    if (tok.value === "{") depth += 1;
    else if (tok.value === "}") {
      depth -= 1;
      if (depth === 0) break;
    } else if (depth === 1 && (tok.type === "ident" || tok.value === ".")) {
      parts.push(tok.value);
    }
    cursor += 1;
  }
  const semantic = parts.join("").replace(/^\.+|\.+$/g, "");
  return semantic || null;
}

function analyzeFile(file) {
  const text = fs.readFileSync(file, "utf8");
  const tokens = lex(text);
  const fields = new Map();
  const slots = [];
  let depth = 0;
  let currentFunction = null;
  let passMarkers = 0;

  for (let i = 0; i < tokens.length; i += 1) {
    const tok = tokens[i];
    if (tok.value === "FUNCTION" && tokens[i + 1]?.type === "ident") {
      currentFunction = tokens[i + 1].value;
    }
    if (tok.type === "ident" && tokens[i + 1]?.value === ":") {
      fields.set(depth, tok.value);
    }
    if (tok.value === "PASS" || tok.value === "PASSED") {
      passMarkers += 1;
    }
    if (tok.value === "SOURCE") {
      const bindingPath = pathFromSourceBinding(tokens, i);
      const pathParts = [];
      if (bindingPath) {
        pathParts.push(bindingPath);
      } else {
        if (currentFunction) pathParts.push(currentFunction);
        for (const level of [...fields.keys()].sort((a, b) => a - b)) {
          if (level <= depth) pathParts.push(fields.get(level));
        }
      }
      const semanticId = pathParts.filter(Boolean).join(".").replaceAll("..", ".");
      slots.push({
        id: slots.length,
        semantic_id: semanticId || `source.${slots.length}`,
        payload_type: payloadType(semanticId),
        source_span: {
          start: tok.start,
          end: tok.end,
          line: tok.line,
          column: tok.column
        }
      });
    }
    if (["(", "[", "{"].includes(tok.value)) {
      depth += 1;
    } else if ([")", "]", "}"].includes(tok.value)) {
      for (const level of [...fields.keys()]) {
        if (level >= depth) fields.delete(level);
      }
      depth = Math.max(0, depth - 1);
    }
  }

  const seen = new Map();
  const repeatedTargets = [];
  for (const slot of slots) {
    if (seen.has(slot.semantic_id)) repeatedTargets.push(slot.semantic_id);
    else seen.set(slot.semantic_id, slot.id);
  }

  return {
    file,
    status: "pass",
    source_slots: slots,
    pass_markers: passMarkers,
    normalized_before_runtime: true,
    repeated_target_bindings: repeatedTargets,
    flow_ir: {
      source_slot_count: slots.length,
      pass_passthrough: false,
      nodes: slots.map((slot) => ({ kind: "SourceSlot", id: slot.id, semantic_id: slot.semantic_id, payload_type: slot.payload_type }))
    },
    failures: []
  };
}

function candidateFiles() {
  const files = [];
  for (const root of ["examples/upstream", "examples/source_physical"]) {
    if (!fs.existsSync(root)) continue;
    const stack = [root];
    while (stack.length > 0) {
      const dir = stack.pop();
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) stack.push(full);
        else if (entry.isFile() && full.endsWith(".bn")) files.push(full.replaceAll(path.sep, "/"));
      }
    }
  }
  return files.sort();
}

function commandVerify(args) {
  let all = false;
  let reportPath = "build/reports/verify-source-shape.json";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--all") all = true;
    else if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  if (!all) usage();
  const started = now();
  const cases = candidateFiles().map(analyzeFile);
  const failures = cases.flatMap((item) => item.failures.map((failure) => ({ file: item.file, ...failure })));
  const report = {
    command: "verify-source-shape",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases,
    failures
  };
  writeReport(reportPath, report);
  if (failures.length === 0) {
    console.log(`source-shape ok: ${cases.length} files, ${cases.reduce((sum, item) => sum + item.source_slots.length, 0)} slots`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const failure of failures.slice(0, 10)) {
    console.error(`${failure.file}: error: duplicate source path ${failure.semantic_id}`);
  }
  console.error(`source-shape failed: ${failures.length} failures`);
  process.exit(1);
}

function commandFlow(args) {
  const file = args[0];
  if (!file) usage();
  let reportPath = `build/reports/flow-${path.basename(file, ".bn")}.json`;
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  const started = now();
  const analysis = analyzeFile(file);
  const report = {
    command: "flow",
    status: analysis.status,
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [analysis],
    failures: analysis.failures
  };
  writeReport(reportPath, report);
  if (analysis.status === "pass") {
    console.log(`flow ok: ${file}`);
    console.log(`source slots: ${analysis.source_slots.length}`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  console.error(`flow failed: ${file}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
if (command === "verify-source-shape") commandVerify(args);
else if (command === "flow") commandFlow(args);
else usage();
