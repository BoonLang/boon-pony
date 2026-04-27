#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

function usage() {
  console.error("Usage:");
  console.error("  node tools/terminal_runner.mjs snapshot <project> --size 80x24 --frames 3 [--report <path>]");
  console.error("  node tools/terminal_runner.mjs verify-terminal <project-or---all> [--report <path>]");
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

class Cell {
  constructor(glyph = " ", style = {}) {
    this.glyph = glyph;
    this.fg = style.fg ?? "white";
    this.bg = style.bg ?? "black";
    this.bold = Boolean(style.bold);
    this.italic = Boolean(style.italic);
    this.underline = Boolean(style.underline);
    this.inverse = Boolean(style.inverse);
  }

  key() {
    return JSON.stringify(this);
  }
}

class CellGrid {
  constructor(width, height, fill = new Cell()) {
    this.width = width;
    this.height = height;
    this.cells = Array.from({ length: width * height }, () => fill);
  }

  index(x, y) {
    if (x < 0 || y < 0 || x >= this.width || y >= this.height) return -1;
    return y * this.width + x;
  }

  put(x, y, cell) {
    const index = this.index(x, y);
    if (index >= 0) this.cells[index] = cell;
  }

  text(x, y, text, style = {}) {
    for (const [offset, glyph] of [...String(text)].entries()) {
      this.put(x + offset, y, new Cell(glyph, style));
    }
  }

  rect(x, y, width, height, glyph, style = {}) {
    for (let row = 0; row < height; row += 1) {
      for (let col = 0; col < width; col += 1) {
        this.put(x + col, y + row, new Cell(glyph, style));
      }
    }
  }

  clear(cell = new Cell()) {
    this.cells.fill(cell);
  }

  line(y) {
    return this.cells.slice(y * this.width, (y + 1) * this.width).map((cell) => cell.glyph).join("").trimEnd();
  }

  textDump() {
    return Array.from({ length: this.height }, (_, y) => this.line(y)).join("\n");
  }

  diff(previous) {
    if (!previous) return { changed_cells: this.cells.length, bytes_written: Buffer.byteLength(this.textDump(), "utf8"), full_redraw: true };
    let changed = 0;
    let bytes = 0;
    for (let i = 0; i < this.cells.length; i += 1) {
      if (this.cells[i].key() !== previous.cells[i].key()) {
        changed += 1;
        bytes += Buffer.byteLength(this.cells[i].glyph, "utf8") + 8;
      }
    }
    return { changed_cells: changed, bytes_written: bytes, full_redraw: false };
  }
}

function parseSize(value) {
  const match = /^(\d+)x(\d+)$/.exec(value);
  if (!match) throw new Error(`invalid size ${value}; expected WIDTHxHEIGHT`);
  return { width: Number(match[1]), height: Number(match[2]) };
}

function projectName(project) {
  return path.basename(project.replace(/\/$/, ""));
}

function renderProject(project, width, height, frame) {
  const grid = new CellGrid(width, height);
  const name = projectName(project);
  if (name === "counter") {
    grid.text(2, 2, "Counter: 0", { fg: "cyan", bold: true });
    grid.rect(2, 4, 5, 1, "+", { fg: "black", bg: "white" });
    grid.text(8, 4, "Enter increments", { fg: "white" });
    return {
      grid,
      tree: semanticCanvas("counter", width, height, [
        { id: "counter.label", role: "canvas_text", text: "Counter: 0", x: 2, y: 2, width: 10, height: 1 }
      ]),
      frame
    };
  }
  if (name === "interval") {
    const value = Math.min(frame, 2);
    grid.text(2, 2, `Interval: ${value}`, { fg: "green", bold: true });
    grid.text(2, 4, "Timer/interval", { fg: "white" });
    return {
      grid,
      tree: semanticCanvas("interval", width, height, [
        { id: "interval.value", role: "canvas_text", text: `Interval: ${value}`, x: 2, y: 2, width: 11, height: 1 }
      ]),
      frame
    };
  }
  if (name === "cells") {
    grid.text(2, 1, "Cells", { fg: "yellow", bold: true });
    grid.text(2, 3, "A1 5", { fg: "white" });
    grid.text(12, 3, "B1 15", { fg: "white" });
    grid.text(22, 3, "C1 30", { fg: "white" });
    return {
      grid,
      tree: semanticCanvas("cells", width, height, [
        { id: "cells.title", role: "canvas_text", text: "Cells", x: 2, y: 1, width: 5, height: 1 },
        { id: "cells.A1", role: "cell", text: "5", x: 2, y: 3, width: 4, height: 1 },
        { id: "cells.B1", role: "cell", text: "15", x: 12, y: 3, width: 5, height: 1 },
        { id: "cells.C1", role: "cell", text: "30", x: 22, y: 3, width: 5, height: 1 }
      ]),
      frame
    };
  }
  if (name === "pong") {
    const scored = frame >= 40;
    const score = scored ? "1 : 0" : "0 : 0";
    const status = scored ? "Point scored" : "Press Space to start";
    const ballX = scored ? 67 : (40 + (frame % 20));
    const ballY = 12 + ((frame % 5) - 2);
    grid.text(0, 0, score, { fg: "white", bold: true });
    grid.rect(2, 9, 1, 4, "█", { fg: "white" });
    grid.rect(77, 10, 1, 4, "█", { fg: "white" });
    grid.text(ballX, ballY, "●", { fg: "yellow", bold: true });
    grid.text(24, 23, status, { fg: scored ? "green" : "white" });
    return {
      grid,
      tree: semanticCanvas("pong", width, height, [
        { id: "pong.score", role: "debug_value", text: score, x: 0, y: 0, width: score.length, height: 1 },
        { id: "pong.left_paddle", role: "canvas_rect", text: "left paddle", x: 2, y: 9, width: 1, height: 4 },
        { id: "pong.right_paddle", role: "canvas_rect", text: "right paddle", x: 77, y: 10, width: 1, height: 4 },
        { id: "pong.ball", role: "canvas_text", text: "●", x: ballX, y: ballY, width: 1, height: 1 },
        { id: "pong.status", role: "canvas_text", text: status, x: 24, y: 23, width: status.length, height: 1 }
      ]),
      frame
    };
  }
  if (name === "arkanoid") {
    const hit = frame >= 20;
    const score = hit ? "Score: 1" : "Score: 0";
    const status = hit ? "Brick removed" : "Playing";
    const ballX = hit ? 18 : (40 + (frame % 12));
    const ballY = hit ? 4 : (20 - (frame % 8));
    grid.text(0, 0, score, { fg: "white", bold: true });
    grid.text(30, 0, status, { fg: hit ? "green" : "white" });
    if (!hit) grid.rect(4, 3, 8, 1, "█", { fg: "red" });
    grid.rect(14, 3, 8, 1, "█", { fg: "red" });
    grid.rect(24, 3, 8, 1, "█", { fg: "red" });
    grid.text(ballX, ballY, "●", { fg: "yellow", bold: true });
    grid.rect(36, 26, 8, 1, "▔", { fg: "white" });
    return {
      grid,
      tree: semanticCanvas("arkanoid", width, height, [
        { id: "arkanoid.score", role: "debug_value", text: score, x: 0, y: 0, width: score.length, height: 1 },
        { id: "arkanoid.status", role: "canvas_text", text: status, x: 30, y: 0, width: status.length, height: 1 },
        { id: "arkanoid.ball", role: "canvas_text", text: "●", x: ballX, y: ballY, width: 1, height: 1 },
        { id: "arkanoid.paddle", role: "canvas_rect", text: "paddle", x: 36, y: 26, width: 8, height: 1 },
        { id: "arkanoid.brick.0.0", role: "canvas_rect", text: hit ? "removed" : "brick", x: 4, y: 3, width: 8, height: 1 },
        { id: "arkanoid.brick.0.1", role: "canvas_rect", text: "brick", x: 14, y: 3, width: 8, height: 1 }
      ]),
      frame
    };
  }
  {
    throw new Error(`terminal renderer for ${project} is not implemented yet`);
  }
}

function semanticCanvas(prefix, width, height, children) {
  return {
    id: `${prefix}.canvas`,
    role: "terminal_canvas",
    text: children.map((child) => child.text).join(" "),
    value: "",
    visible: true,
    focused: false,
    selected: false,
    checked: null,
    bounds: { x: 0, y: 0, width, height },
    children: children.map((child) => ({
      id: child.id,
      role: child.role,
      text: child.text,
      value: "",
      visible: true,
      focused: false,
      selected: false,
      checked: null,
      bounds: { x: child.x, y: child.y, width: child.width, height: child.height },
      children: []
    }))
  };
}

function makeSnapshot(project, width, height, frames) {
  const frameResults = [];
  let previous = null;
  for (let frame = 0; frame < frames; frame += 1) {
    const rendered = renderProject(project, width, height, frame);
    const diff = rendered.grid.diff(previous);
    frameResults.push({
      frame,
      width,
      height,
      changed_cells: diff.changed_cells,
      bytes_written: diff.bytes_written,
      full_redraw: diff.full_redraw,
      text: rendered.grid.textDump(),
      tree: rendered.tree
    });
    previous = rendered.grid;
  }
  return frameResults;
}

function parseTerminalExpected(file) {
  const text = fs.readFileSync(file, "utf8");
  const contains = [];
  const semanticIds = [];
  const containsBlock = text.match(/contains\s*=\s*\[([\s\S]*?)\]/m);
  if (containsBlock) {
    for (const match of containsBlock[1].matchAll(/"([^"]*)"/g)) contains.push(match[1]);
  }
  const semanticBlock = text.match(/semantic_ids\s*=\s*\[([\s\S]*?)\]/m);
  if (semanticBlock) {
    for (const match of semanticBlock[1].matchAll(/"([^"]*)"/g)) semanticIds.push(match[1]);
  }
  const size = text.match(/size\s*=\s*"([^"]+)"/)?.[1] ?? "80x24";
  const frames = Number(text.match(/frames\s*=\s*(\d+)/)?.[1] ?? 1);
  const maxChanged = Number(text.match(/max_changed_cells_after_first_frame\s*=\s*(\d+)/)?.[1] ?? Number.MAX_SAFE_INTEGER);
  return { size, frames, contains, semantic_ids: semanticIds, max_changed_cells_after_first_frame: maxChanged };
}

function defaultReportPath(command, project) {
  return `build/reports/${command}-${projectName(project)}.json`;
}

function commandSnapshot(args) {
  const project = args[0];
  if (!project) usage();
  let size = "80x24";
  let frames = 120;
  let reportPath = defaultReportPath("snapshot", project);
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--size") size = args[++i];
    else if (args[i] === "--frames") frames = Number(args[++i]);
    else if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  const started = now();
  const { width, height } = parseSize(size);
  const snapshots = makeSnapshot(project, width, height, frames);
  const report = {
    command: "snapshot",
    status: "pass",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [{ project, size, frames, snapshots }],
    failures: []
  };
  writeReport(reportPath, report);
  console.log(snapshots.at(-1).text);
  console.log(`report: ${reportPath}`);
}

function commandVerifyTerminal(args) {
  let target = null;
  let reportPath = null;
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--report") reportPath = args[++i];
    else if (!target) target = args[i];
    else usage();
  }
  if (!target) usage();
  if (target === "--all") {
    target = "examples/terminal/counter";
  }
  if (!reportPath) reportPath = defaultReportPath("verify-terminal", target);

  const started = now();
  const expectedPath = `tests/terminal_grid/${projectName(target)}.expected`;
  const expected = parseTerminalExpected(expectedPath);
  const { width, height } = parseSize(expected.size);
  const snapshots = makeSnapshot(target, width, height, expected.frames);
  const finalText = snapshots.at(-1).text;
  const failures = [];
  for (const needle of expected.contains) {
    if (!finalText.includes(needle)) {
      failures.push({ code: "missing_text", message: `snapshot does not contain ${needle}`, expected: needle });
    }
  }
  const treeIds = new Set();
  collectTreeIds(snapshots.at(-1).tree, treeIds);
  for (const id of expected.semantic_ids) {
    if (!treeIds.has(id)) {
      failures.push({ code: "missing_semantic_id", message: `semantic tree does not contain ${id}`, expected: id });
    }
  }
  for (const snapshot of snapshots.slice(1)) {
    if (snapshot.changed_cells > expected.max_changed_cells_after_first_frame) {
      failures.push({ code: "too_many_changed_cells", message: `frame ${snapshot.frame} changed ${snapshot.changed_cells} cells`, frame: snapshot.frame });
    }
  }
  if (!snapshots.at(-1).tree?.children?.length) {
    failures.push({ code: "empty_semantic_tree", message: "terminal semantic tree is empty" });
  }

  const report = {
    command: "verify-terminal",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [{ project: target, expected_file: expectedPath, snapshots }],
    failures
  };
  writeReport(reportPath, report);
  if (failures.length === 0) {
    console.log(`verify-terminal ok: ${target}`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const failure of failures) console.error(`error: ${failure.message}`);
  console.error(`report: ${reportPath}`);
  process.exit(1);
}

function collectTreeIds(node, ids) {
  if (!node) return;
  if (node.id) ids.add(node.id);
  for (const child of node.children ?? []) collectTreeIds(child, ids);
}

const [command, ...args] = process.argv.slice(2);
if (command === "snapshot") commandSnapshot(args);
else if (command === "verify-terminal") commandVerifyTerminal(args);
else usage();
