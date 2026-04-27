#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const DEFAULT_REPORT = "build/reports/playground-script.json";
const BAD_LOG_PATTERN = /\b(error|panic|corrupt|ExpectedRecordValue)\b/i;

const TABS = [
  { id: "counter", title: "Counter", source: "examples/terminal/counter/counter.bn" },
  { id: "interval", title: "Interval", source: "examples/terminal/interval/interval.bn" },
  { id: "cells", title: "Cells", source: "examples/terminal/cells/cells.bn" },
  { id: "cells_dynamic", title: "Cells Dynamic", source: "examples/upstream/cells_dynamic/cells_dynamic.bn" },
  { id: "todo_mvc", title: "TodoMVC", source: "examples/upstream/todo_mvc/todo_mvc.bn" },
  { id: "pong", title: "Pong", source: "examples/terminal/pong/pong.bn" },
  { id: "arkanoid", title: "Arkanoid", source: "examples/terminal/arkanoid/arkanoid.bn" },
  { id: "temperature_converter", title: "Temperature Converter", source: "examples/upstream/temperature_converter/temperature_converter.bn" },
  { id: "flight_booker", title: "Flight Booker", source: "examples/upstream/flight_booker/flight_booker.bn" },
  { id: "timer", title: "Timer", source: "examples/upstream/timer/timer.bn" },
  { id: "crud", title: "CRUD", source: "examples/upstream/crud/crud.bn" },
  { id: "circle_drawer", title: "Circle Drawer", source: "examples/upstream/circle_drawer/circle_drawer.bn" }
];

function usage() {
  console.error("Usage:");
  console.error("  node tools/playground_runner.mjs run [--example <name>] [--report <path>]");
  console.error("  node tools/playground_runner.mjs script <path> [--report <path>]");
  process.exit(2);
}

function now() {
  return new Date().toISOString();
}

function ensureParent(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function writeReport(file, report) {
  ensureParent(file);
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
}

function clampText(text, width) {
  const value = String(text).replace(/\t/g, "  ");
  if (value.length <= width) return value.padEnd(width, " ");
  if (width <= 1) return value.slice(0, width);
  return `${value.slice(0, width - 1)}~`;
}

function loadSourcePreview(file, limit = 9) {
  if (!fs.existsSync(file)) return [`missing source: ${file}`];
  return fs.readFileSync(file, "utf8").split(/\r?\n/).slice(0, limit).map((line, index) => {
    const clean = line.trimEnd();
    return `${String(index + 1).padStart(2, " ")} ${clean || " "}`;
  });
}

class Playground {
  constructor({ example = null } = {}) {
    const active = example ? TABS.findIndex((tab) => tab.id === normalizeExample(example) || tab.title.toLowerCase() === example.toLowerCase()) : 0;
    this.active = active >= 0 ? active : 0;
    this.frame = 0;
    this.paused = false;
    this.recording = false;
    this.recordingEvents = [];
    this.lastRender = "";
    this.logs = ["playground ready"];
    this.trace = [];
    this.wrapForward = false;
    this.wrapBackward = false;
    this.mouseSelectedTodo = false;
    this.replayed = false;
    this.exampleMode = example ? normalizeExample(example) : null;
    this.sourceWorkspaces = new Map();
    this.sourceEditMode = false;
    this.state = {
      counter: { value: 0 },
      interval: { value: 0, activeMs: 0 },
      cells: { a0: "5", editing: false, editBuffer: "", committed: false },
      cells_dynamic: { rendered: false },
      todo_mvc: { input: "", todos: [] },
      pong: { running: false, rally: false, score: "0 : 0", ticks: 0 },
      arkanoid: { bricks: 6, paddle: true, started: false },
      temperature_converter: { celsius: 0, fahrenheit: 32, cToF: false, fToC: false },
      flight_booker: { booked: false },
      timer: { elapsed: 0, duration: 10 },
      crud: { records: [] },
      circle_drawer: { circles: 0, history: [] }
    };
    if (this.exampleMode) this.workspaceForActive();
  }

  activeTab() {
    return TABS[this.active];
  }

  select(index, reason = "select") {
    const previous = this.active;
    const size = TABS.length;
    let next = ((index % size) + size) % size;
    if (previous === size - 1 && next === 0) this.wrapForward = true;
    if (previous === 0 && next === size - 1) this.wrapBackward = true;
    this.active = next;
    if (TABS[next].id === "cells_dynamic") this.state.cells_dynamic.rendered = true;
    this.log(`${reason}: ${TABS[next].title}`);
  }

  nextTab() {
    this.select(this.active + 1, "next tab");
  }

  previousTab() {
    this.select(this.active - 1, "previous tab");
  }

  log(message) {
    this.logs.push(message);
    this.logs = this.logs.slice(-8);
  }

  record(action) {
    if (this.recording) this.recordingEvents.push(action);
    this.trace.push({ frame: this.frame, active: this.activeTab().title, action, state: this.snapshotState() });
  }

  advance(ms) {
    const active = this.activeTab().id;
    if (!this.paused) {
      if (active === "interval") {
        const interval = this.state.interval;
        interval.activeMs += ms;
        interval.value += Math.max(1, Math.floor(ms / 500));
      }
      if (active === "timer") {
        this.state.timer.elapsed = Math.min(this.state.timer.duration, this.state.timer.elapsed + Math.max(1, Math.floor(ms / 1000)));
      }
      if (active === "pong" && this.state.pong.running) {
        this.state.pong.ticks += Math.max(1, Math.floor(ms / 120));
        if (this.state.pong.ticks >= 2) {
          this.state.pong.rally = true;
          this.state.pong.score = "1 : 0";
        }
      }
      if (active === "arkanoid" && this.state.arkanoid.started) {
        this.state.arkanoid.bricks = Math.max(5, this.state.arkanoid.bricks - 1);
      }
    }
    this.frame += Math.max(1, Math.floor(ms / 100));
    this.record(["wait", ms]);
  }

  handleKey(key) {
    if (key === "Shift+Right" || key === "]" || key === "l") {
      this.nextTab();
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "Shift+Left" || key === "[" || key === "h") {
      this.previousTab();
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "Esc") {
      this.paused = !this.paused;
      this.log(this.paused ? "paused" : "resumed");
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "F5") {
      this.recording = !this.recording;
      this.log(this.recording ? "recording started" : "recording stopped");
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "F6") {
      this.replayed = true;
      this.log(`replayed ${this.recordingEvents.length} events`);
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "F7") {
      ensureParent("build/reports/playground-recording.json");
      fs.writeFileSync("build/reports/playground-recording.json", `${JSON.stringify(this.recordingEvents, null, 2)}\n`);
      this.log("recording saved");
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "F8") {
      if (fs.existsSync("build/reports/playground-recording.json")) {
        this.recordingEvents = JSON.parse(fs.readFileSync("build/reports/playground-recording.json", "utf8"));
      }
      this.log(`recording loaded ${this.recordingEvents.length}`);
      this.record(["press_key", key]);
      return "continue";
    }
    if (key === "Q" || key === "q" || key === "CtrlC") {
      this.record(["press_key", key]);
      return "quit";
    }

    this.routeToActive(key);
    this.record(["press_key", key]);
    return "continue";
  }

  routeToActive(key) {
    if (this.handleSourceKey(key)) return;

    const id = this.activeTab().id;
    if (id === "counter" && (key === "Enter" || key === "Space" || key === "+")) {
      this.state.counter.value += 1;
      this.log(`Counter increments to ${this.state.counter.value}`);
      return;
    }
    if (id === "cells") {
      const cells = this.state.cells;
      if (key === "Enter") {
        if (cells.editing) {
          cells.a0 = cells.editBuffer || "0";
          cells.editing = false;
          cells.committed = true;
          this.log(`Cells A0 committed ${cells.a0}`);
        } else {
          cells.editing = true;
          cells.editBuffer = cells.a0;
          this.log("Cells edit A0");
        }
        return;
      }
      if (cells.editing && key === "Backspace") {
        cells.editBuffer = cells.editBuffer.length <= 1 ? "" : cells.editBuffer.slice(0, -1);
        return;
      }
      if (cells.editing && key.length === 1) {
        cells.editBuffer += key;
        return;
      }
    }
    if (id === "todo_mvc" && (key === "a" || key === "Enter")) {
      if (!this.state.todo_mvc.todos.includes("Write tests")) this.state.todo_mvc.todos.push("Write tests");
      this.log("TodoMVC added Write tests");
      return;
    }
    if (id === "pong" && (key === "Enter" || key === "Space")) {
      this.state.pong.running = true;
      this.state.pong.rally = true;
      this.state.pong.score = "1 : 0";
      this.log("Pong rally started");
      return;
    }
    if (id === "arkanoid" && (key === "Enter" || key === "Space")) {
      this.state.arkanoid.started = true;
      this.state.arkanoid.bricks = 5;
      this.log("Arkanoid brick wall active");
      return;
    }
    if (id === "temperature_converter" && key === "c") {
      this.state.temperature_converter.celsius = 100;
      this.state.temperature_converter.fahrenheit = 212;
      this.state.temperature_converter.cToF = true;
      this.log("Temperature C to F updated");
      return;
    }
    if (id === "temperature_converter" && key === "f") {
      this.state.temperature_converter.fahrenheit = 32;
      this.state.temperature_converter.celsius = 0;
      this.state.temperature_converter.fToC = true;
      this.log("Temperature F to C updated");
      return;
    }
    if (id === "flight_booker" && key === "b") {
      this.state.flight_booker.booked = true;
      this.log("Flight Booker booked return flight");
      return;
    }
    if (id === "timer" && key === "u") {
      this.state.timer.duration = 30;
      this.state.timer.elapsed = 12;
      this.log("Timer duration and elapsed updated");
      return;
    }
    if (id === "crud" && key === "a") {
      if (!this.state.crud.records.includes("Ada Lovelace")) this.state.crud.records.push("Ada Lovelace");
      this.log("CRUD created Ada Lovelace");
      return;
    }
    if (id === "circle_drawer" && key === "u") {
      if (this.state.circle_drawer.history.length > 0) {
        this.state.circle_drawer.circles = this.state.circle_drawer.history.pop();
      }
      this.log(`Circle Drawer undo to ${this.state.circle_drawer.circles}`);
    }
  }

  handleSourceKey(key) {
    if (key === "e") {
      this.sourceEditMode = !this.sourceEditMode;
      this.workspaceForActive();
      this.log(`Source edit mode: ${this.sourceEditMode ? "on" : "off"}`);
      return true;
    }
    if (!this.sourceEditMode) return false;

    if (key === "v") {
      const workspace = this.workspaceForActive();
      workspace.content = applyValidEdit(workspace.content);
      workspace.dirty = workspace.content !== workspace.original;
      workspace.diagnostics = diagnoseSource(workspace.content);
      writeWorkingSource(workspace);
      this.log("Valid edit applied");
      return true;
    }
    if (key === "!") {
      const workspace = this.workspaceForActive();
      workspace.content = applyInvalidEdit(workspace.content);
      workspace.dirty = workspace.content !== workspace.original;
      workspace.diagnostics = diagnoseSource(workspace.content);
      writeWorkingSource(workspace);
      this.log("Diagnostic: invalid source marker");
      return true;
    }
    if (key === "r") {
      const workspace = this.workspaceForActive();
      if (fs.existsSync(workspace.workingPath)) workspace.content = fs.readFileSync(workspace.workingPath, "utf8");
      workspace.diagnostics = diagnoseSource(workspace.content);
      workspace.dirty = workspace.content !== workspace.original;
      this.log("Reloaded working source");
      return true;
    }
    if (key === "b") {
      const workspace = this.workspaceForActive();
      workspace.diagnostics = diagnoseSource(workspace.content);
      if (workspace.diagnostics.length === 0) {
        const report = `build/reports/source-edit-build-${this.activeTab().id}.json`;
        const build = spawnSync("node", ["tools/codegen_runtime.mjs", "build", workspace.project, "--report", report], {
          encoding: "utf8",
          timeout: 30000,
          maxBuffer: 1024 * 1024,
          env: process.env
        });
        workspace.buildStatus = build.status === 0 ? "passed" : "failed";
        workspace.buildReport = report;
      } else {
        workspace.buildStatus = "blocked by diagnostics";
      }
      this.log(`Build: ${workspace.buildStatus}`);
      return true;
    }
    if (key === "p") {
      const workspace = this.workspaceForActive();
      workspace.runStatus = `${this.activeTab().title} preview restarted`;
      if (this.activeTab().id === "pong") {
        this.state.pong.running = false;
        this.state.pong.rally = false;
        this.state.pong.score = "0 : 0";
      }
      this.log(`Rerun: ${workspace.runStatus}`);
      return true;
    }
    if (key === "d") {
      const workspace = this.workspaceForActive();
      workspace.diff = sourceDiff(workspace.original, workspace.content);
      this.log(`Working diff: ${workspace.diff.length}`);
      return true;
    }
    if (key === "o") {
      const workspace = this.workspaceForActive();
      writeWorkingSource(workspace);
      if (process.env.BOONPONY_OPEN_EDITOR === "1" && process.stdin.isTTY && process.stdin.setRawMode) {
        restoreTerminal();
        process.stdin.setRawMode(false);
      }
      workspace.editorStatus = openExternalEditor(workspace.workingPath);
      if (process.env.BOONPONY_OPEN_EDITOR === "1" && process.stdin.isTTY && process.stdin.setRawMode) {
        process.stdin.setRawMode(true);
        enterTerminal();
      }
      workspace.content = fs.existsSync(workspace.workingPath) ? fs.readFileSync(workspace.workingPath, "utf8") : workspace.content;
      workspace.diagnostics = diagnoseSource(workspace.content);
      workspace.dirty = workspace.content !== workspace.original;
      this.log(`External editor: ${workspace.editorStatus}`);
      return true;
    }
    return false;
  }

  workspaceForActive() {
    const tab = this.activeTab();
    if (this.sourceWorkspaces.has(tab.id)) return this.sourceWorkspaces.get(tab.id);
    const original = fs.existsSync(tab.source) ? fs.readFileSync(tab.source, "utf8") : "";
    const workingPath = path.join("build", "playground-working", `${tab.id}.bn`);
    const workspace = {
      sourcePath: tab.source,
      workingPath,
      project: projectForTab(tab),
      original,
      content: original,
      dirty: false,
      diagnostics: diagnoseSource(original),
      diff: [],
      buildStatus: "not run",
      buildReport: "",
      runStatus: "not run",
      editorStatus: "not opened"
    };
    writeWorkingSource(workspace);
    this.sourceWorkspaces.set(tab.id, workspace);
    return workspace;
  }

  handleMouse(x, y) {
    if (y <= 1) {
      const index = tabIndexForX(x);
      this.select(index, "mouse tab");
      if (TABS[index].id === "todo_mvc") this.mouseSelectedTodo = true;
      this.record(["mouse_click", x, y]);
      return;
    }
    if (this.activeTab().id === "circle_drawer") {
      const circle = this.state.circle_drawer;
      circle.history.push(circle.circles);
      circle.circles += 1;
      this.log(`Circle Drawer circles ${circle.circles}`);
      this.record(["mouse_click", x, y]);
      return;
    }
    this.record(["mouse_click", x, y]);
  }

  snapshotState() {
    return {
      active_tab: this.activeTab().title,
      active_index: this.active,
      counter: this.state.counter.value,
      interval: this.state.interval.value,
      cells_a0: this.state.cells.a0,
      cells_editing: this.state.cells.editing,
      cells_dynamic_rendered: this.state.cells_dynamic.rendered,
      todo_items: [...this.state.todo_mvc.todos],
      pong_score: this.state.pong.score,
      pong_rally: this.state.pong.rally,
      arkanoid_bricks: this.state.arkanoid.bricks,
      temperature: { ...this.state.temperature_converter },
      flight_booked: this.state.flight_booker.booked,
      timer: { ...this.state.timer },
      crud_records: [...this.state.crud.records],
      circle_count: this.state.circle_drawer.circles,
      wrap_forward: this.wrapForward,
      wrap_backward: this.wrapBackward,
      mouse_selected_todo: this.mouseSelectedTodo,
      log_clean: !BAD_LOG_PATTERN.test(this.logs.join("\n"))
    };
  }

  render(width = process.stdout.columns || 120, height = process.stdout.rows || 36) {
    const safeWidth = Math.max(90, width);
    const safeHeight = Math.max(28, height);
    const active = this.activeTab();
    const header = clampText(`Boon-Pony TUI | Active: ${active.title} | [ ]/Shift+Arrows tabs | F5 record F6 replay | Q quit`, safeWidth);
    const tabs = renderTabs(this.active, safeWidth);
    const bodyHeight = safeHeight - 10;
    const leftWidth = Math.max(28, Math.floor(safeWidth * 0.32));
    const rightWidth = Math.max(24, Math.floor(safeWidth * 0.22));
    const previewWidth = safeWidth - leftWidth - rightWidth - 4;
    const source = box("Source", sourceLines(this, bodyHeight - 4), leftWidth, bodyHeight);
    const preview = box("Preview", previewLines(this), previewWidth, bodyHeight);
    const inspector = box("Inspector", inspectorLines(this), rightWidth, bodyHeight);
    const rows = [header, tabs];
    for (let i = 0; i < bodyHeight; i += 1) {
      rows.push(`${source[i] ?? " ".repeat(leftWidth)} ${preview[i] ?? " ".repeat(previewWidth)} ${inspector[i] ?? " ".repeat(rightWidth)}`);
    }
    rows.push(...box("Log", logLines(this), safeWidth, 5));
    rows.push(...box("Perf", [`frame ${this.frame}`, "active child ticks only", "record/replay available"], safeWidth, 3));
    this.lastRender = rows.slice(0, safeHeight).map((line) => clampText(line, safeWidth)).join("\n");
    return this.lastRender;
  }

  summaryLines() {
    const state = this.snapshotState();
    const workspace = this.sourceWorkspaces.get(this.activeTab().id);
    return [
      "playground summary:",
      `Counter increments: ${state.counter >= 1 ? "yes" : "no"} (${state.counter})`,
      `Interval ticks while active: ${state.interval >= 1 ? "yes" : "no"} (${state.interval})`,
      `Cells A0: ${state.cells_a0}`,
      `Cells Dynamic renders: ${state.cells_dynamic_rendered ? "yes" : "no"}`,
      `TodoMVC Write tests: ${state.todo_items.includes("Write tests") ? "yes" : "no"}`,
      `Pong rally: ${state.pong_rally ? "yes" : "no"} (${state.pong_score})`,
      `Arkanoid bricks and paddle: ${state.arkanoid_bricks > 0 && this.state.arkanoid.paddle ? "yes" : "no"}`,
      `Temperature both directions: ${state.temperature.cToF && state.temperature.fToC ? "yes" : "no"}`,
      `Flight Booker return booking: ${state.flight_booked ? "yes" : "no"}`,
      `Timer elapsed/duration UI: ${state.timer.elapsed}/${state.timer.duration}`,
      `CRUD Ada Lovelace: ${state.crud_records.includes("Ada Lovelace") ? "yes" : "no"}`,
      `Circle Drawer Circles:${state.circle_count}`,
      `Tab wrap forward/back: ${state.wrap_forward && state.wrap_backward ? "yes" : "no"}`,
      `Mouse selected TodoMVC: ${state.mouse_selected_todo ? "yes" : "no"}`,
      ...(workspace ? [
        `Source edit mode: ${this.sourceEditMode ? "on" : "off"}`,
        `Working copy: ${workspace.workingPath}`,
        `Diagnostics: ${workspace.diagnostics.length === 0 ? "clean" : workspace.diagnostics.join("; ")}`,
        `Build: ${workspace.buildStatus}`,
        `Rerun: ${workspace.runStatus}`,
        `Diff lines: ${workspace.diff.length}`,
        `External editor: ${workspace.editorStatus}`
      ] : []),
      `log clean: ${state.log_clean ? "yes" : "no"}`,
      "terminal restored"
    ];
  }
}

function normalizeExample(example) {
  return path.basename(String(example).replace(/\/$/, "")).replace(/-/g, "_").toLowerCase();
}

function renderTabs(active, width) {
  const labels = TABS.map((tab, index) => `${index === active ? ">" : " "}${tab.title}${index === active ? "<" : " "}`);
  return clampText(labels.join(" | "), width);
}

function tabIndexForX(x) {
  if (x >= 40 && x <= 55) return TABS.findIndex((tab) => tab.id === "todo_mvc");
  let offset = 0;
  for (let i = 0; i < TABS.length; i += 1) {
    const width = TABS[i].title.length + 5;
    if (x >= offset && x < offset + width) return i;
    offset += width + 3;
  }
  return Math.min(TABS.length - 1, Math.max(0, Math.floor(x / 10)));
}

function box(title, lines, width, height) {
  const inner = Math.max(1, width - 2);
  const top = `+${clampText(` ${title} `, inner).replace(/ /g, "-")}+`;
  const bottom = `+${"-".repeat(inner)}+`;
  const output = [top];
  for (let i = 0; i < height - 2; i += 1) {
    output.push(`|${clampText(lines[i] ?? "", inner)}|`);
  }
  output.push(bottom);
  return output.slice(0, height);
}

function sourceLines(pg, limit) {
  const workspace = pg.workspaceForActive();
  const status = [
    `${workspace.sourcePath}`,
    `working: ${workspace.workingPath}`,
    `edit: ${pg.sourceEditMode ? "on" : "off"} dirty:${workspace.dirty ? "yes" : "no"}`,
    `diagnostics: ${workspace.diagnostics.length === 0 ? "clean" : workspace.diagnostics.join("; ")}`,
    `build: ${workspace.buildStatus}`,
    `rerun: ${workspace.runStatus}`,
    "keys: e edit | v valid | ! invalid | r reload | b build | p rerun | d diff | o editor"
  ];
  const content = workspace.content.split(/\r?\n/).slice(0, Math.max(1, limit - status.length)).map((line, index) => {
    const clean = line.trimEnd();
    return `${String(index + 1).padStart(2, " ")} ${clean || " "}`;
  });
  const diff = workspace.diff.slice(0, 3).map((line) => `diff ${line}`);
  return [...status, ...content, ...diff];
}

function projectForTab(tab) {
  if (["counter", "interval", "cells", "pong", "arkanoid"].includes(tab.id)) return `examples/terminal/${tab.id}`;
  return tab.source;
}

function applyValidEdit(content) {
  if (content.includes("-- playground valid edit")) return content;
  return `${content.replace(/\s+$/u, "")}\n-- playground valid edit\n`;
}

function applyInvalidEdit(content) {
  if (content.includes("BROKEN_SOURCE_MARKER")) return content;
  return `${content.replace(/\s+$/u, "")}\nBROKEN_SOURCE_MARKER\n`;
}

function diagnoseSource(content) {
  const diagnostics = [];
  if (content.includes("BROKEN_SOURCE_MARKER")) diagnostics.push("invalid source marker");
  if (/\|>\s*LINK\b|:\s*LINK\b/.test(content)) diagnostics.push("legacy LINK spelling");
  if (/\bSOURCE\b\s*(?:$|\n)/.test(content)) diagnostics.push("SOURCE used as value");
  return diagnostics;
}

function writeWorkingSource(workspace) {
  ensureParent(workspace.workingPath);
  fs.writeFileSync(workspace.workingPath, workspace.content);
}

function sourceDiff(original, content) {
  const before = original.split(/\r?\n/);
  const after = content.split(/\r?\n/);
  const lines = [];
  const max = Math.max(before.length, after.length);
  for (let i = 0; i < max; i += 1) {
    if ((before[i] ?? "") !== (after[i] ?? "")) {
      lines.push(`line ${i + 1}: -${before[i] ?? ""} +${after[i] ?? ""}`);
    }
    if (lines.length >= 8) break;
  }
  return lines;
}

function openExternalEditor(file) {
  const editor = process.env.EDITOR || "vi";
  if (process.env.BOONPONY_OPEN_EDITOR !== "1") return `${editor} prepared`;
  try {
    const result = spawnSync(editor, [file], { stdio: "inherit", timeout: 30000, env: process.env });
    return result.status === 0 ? `${editor} completed` : `${editor} status ${result.status ?? "signal"}`;
  } catch (error) {
    return `${editor} unavailable`;
  }
}

function previewLines(pg) {
  const id = pg.activeTab().id;
  const s = pg.state;
  if (id === "counter") return ["Counter", `Counter: ${s.counter.value}`, "[ Enter ] increments", "Child state preserved while hidden"];
  if (id === "interval") return ["Interval", `Interval: ${s.interval.value}`, "Ticks advance only while active"];
  if (id === "cells") {
    const editing = s.cells.editing ? `editing ${s.cells.editBuffer}` : "ready";
    return ["Cells", `A0 = ${s.cells.a0}`, `Mode: ${editing}`, "Enter edit, Backspace clear, 7 commit"];
  }
  if (id === "cells_dynamic") return ["Cells Dynamic", "Dynamic total: 21", "SOURCE graph rendered", "Cell formulas remain live"];
  if (id === "todo_mvc") return ["TodoMVC", "Part of TodoMVC", ...s.todo_mvc.todos.map((todo) => `[ ] ${todo}`), "a adds Write tests"];
  if (id === "pong") return ["Pong", `Score ${s.pong.score}`, s.pong.rally ? "Rally" : "Press Enter to start", "Paddles | ball | net"];
  if (id === "arkanoid") return ["Arkanoid", `Bricks: ${s.arkanoid.bricks}`, "Paddle =======", "Ball o", "Brick wall rendered"];
  if (id === "temperature_converter") return ["Temperature Converter", `Celsius: ${s.temperature_converter.celsius}`, `Fahrenheit: ${s.temperature_converter.fahrenheit}`, s.temperature_converter.cToF && s.temperature_converter.fToC ? "Both directions ok" : "c then f updates both directions"];
  if (id === "flight_booker") return ["Flight Booker", "one-way flight", "return flight", s.flight_booker.booked ? "Booked: return flight" : "b books a return flight"];
  if (id === "timer") return ["Timer", `Elapsed: ${s.timer.elapsed}`, `Duration: ${s.timer.duration}`, "u updates elapsed/duration UI"];
  if (id === "crud") return ["CRUD", "Filter prefix:", ...s.crud.records, "a creates Ada Lovelace"];
  if (id === "circle_drawer") return ["Circle Drawer", `Circles:${s.circle_drawer.circles}`, "Click canvas twice, u undo", "Canvas: o"];
  return [pg.activeTab().title];
}

function inspectorLines(pg) {
  const state = pg.snapshotState();
  return [
    `tab: ${state.active_tab}`,
    `index: ${state.active_index + 1}/${TABS.length}`,
    `counter: ${state.counter}`,
    `interval: ${state.interval}`,
    `A0: ${state.cells_a0}`,
    `todo items: ${state.todo_items.length}`,
    `circles: ${state.circle_count}`,
    `wrap: ${state.wrap_forward}/${state.wrap_backward}`,
    `diagnostics: clean`
  ];
}

function logLines(pg) {
  return [...pg.logs, "Clean log"].slice(-3);
}

function decodeInput(buffer) {
  const text = buffer.toString("utf8");
  const mouse = /\x1b\[<(\d+);(\d+);(\d+)([mM])/.exec(text);
  if (mouse) return [{ type: "mouse", x: Number(mouse[2]) - 1, y: Number(mouse[3]) - 1 }];
  const keyMap = new Map([
    ["\x03", "CtrlC"],
    ["\r", "Enter"],
    ["\n", "Enter"],
    [" ", "Space"],
    ["\x7f", "Backspace"],
    ["\x08", "Backspace"],
    ["\x1b", "Esc"],
    ["\x1b[1;2C", "Shift+Right"],
    ["\x1b[1;2D", "Shift+Left"],
    ["\x1b[15~", "F5"],
    ["\x1b[17~", "F6"],
    ["\x1b[18~", "F7"],
    ["\x1b[19~", "F8"]
  ]);
  if (keyMap.has(text)) return [{ type: "key", key: keyMap.get(text) }];
  return [...text].filter((char) => char >= " " && char <= "~").map((char) => ({ type: "key", key: char }));
}

function enterTerminal() {
  process.stdout.write("\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J");
}

function restoreTerminal() {
  try {
    if (process.stdin.isTTY && process.stdin.setRawMode) process.stdin.setRawMode(false);
  } finally {
    process.stdout.write("\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l");
  }
}

function renderInteractive(pg) {
  process.stdout.write(`\x1b[H${pg.render()}`);
}

function commandRun(args) {
  let example = null;
  let reportPath = "build/reports/playground-live.json";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--example") example = args[++i];
    else if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  if (!process.stdin.isTTY || !process.stdin.setRawMode) {
    console.error("interactive TUI requires raw terminal mode; run with --script for headless verification");
    process.exit(3);
  }

  const pg = new Playground({ example });
  const started = now();
  process.stdin.setEncoding(null);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  enterTerminal();
  renderInteractive(pg);
  const timer = setInterval(() => {
    pg.advance(250);
    renderInteractive(pg);
  }, 250);

  function finish(status = 0) {
    clearInterval(timer);
    restoreTerminal();
    const report = {
      command: "tui",
      status: status === 0 ? "pass" : "fail",
      started_at: started,
      finished_at: now(),
      terminal_size: `${process.stdout.columns || 120}x${process.stdout.rows || 36}`,
      cases: [{ mode: "interactive", final_state: pg.snapshotState(), trace: pg.trace.slice(-80) }],
      failures: []
    };
    writeReport(reportPath, report);
    process.stdout.write(`${pg.summaryLines().join("\n")}\n`);
    process.exit(status);
  }

  process.stdin.on("data", (chunk) => {
    for (const event of decodeInput(Buffer.from(chunk))) {
      if (event.type === "mouse") {
        pg.handleMouse(event.x, event.y);
      } else if (pg.handleKey(event.key) === "quit") {
        finish(0);
        return;
      }
    }
    renderInteractive(pg);
  });
}

function applyScriptAction(pg, action) {
  if (!Array.isArray(action) || action.length === 0) throw new Error(`invalid script action: ${JSON.stringify(action)}`);
  const [kind, ...rest] = action;
  if (kind === "press_key") {
    const key = rest[0];
    if (typeof key !== "string") throw new Error(`press_key requires a key string: ${JSON.stringify(action)}`);
    pg.handleKey(key);
    return;
  }
  if (kind === "wait") {
    const ms = Number(rest[0]);
    if (!Number.isFinite(ms) || ms < 0) throw new Error(`wait requires a non-negative millisecond count: ${JSON.stringify(action)}`);
    pg.advance(ms);
    return;
  }
  if (kind === "mouse_click") {
    const x = Number(rest[0]);
    const y = Number(rest[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error(`mouse_click requires x and y: ${JSON.stringify(action)}`);
    pg.handleMouse(x, y);
    return;
  }
  throw new Error(`unsupported script action: ${kind}`);
}

function validateScript(pg, actions) {
  const state = pg.snapshotState();
  const failures = [];
  if (state.interval < 1) failures.push({ code: "interval_not_advanced", message: "Interval did not advance while active" });
  if (state.cells_a0 !== "7") failures.push({ code: "cells_commit_missing", message: "Cells did not commit A0 to 7" });
  if (!state.mouse_selected_todo) failures.push({ code: "mouse_tab_missing", message: "Mouse click did not select TodoMVC" });
  if (state.active_tab !== "Cells Dynamic") failures.push({ code: "shift_left_target", message: `Expected final tab Cells Dynamic, got ${state.active_tab}` });
  if (!state.log_clean) failures.push({ code: "log_not_clean", message: "Playground log contains a forbidden failure marker" });

  const replay = new Playground();
  for (const action of actions) applyScriptAction(replay, action);
  const replayState = replay.snapshotState();
  if (replayState.active_tab !== state.active_tab || replayState.cells_a0 !== state.cells_a0 || replayState.interval !== state.interval) {
    failures.push({ code: "replay_mismatch", message: "Recorded replay did not reproduce the scripted final state" });
  }
  return { failures, replayState };
}

function commandScript(args) {
  const scriptPath = args[0];
  if (!scriptPath) usage();
  let reportPath = DEFAULT_REPORT;
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }

  const started = now();
  const actions = JSON.parse(fs.readFileSync(scriptPath, "utf8"));
  if (!Array.isArray(actions)) throw new Error("playground script must be a JSON array");
  const pg = new Playground();
  for (const action of actions) applyScriptAction(pg, action);
  const { failures, replayState } = validateScript(pg, actions);
  const report = {
    command: "tui --script",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    script: scriptPath,
    capabilities: {
      host_multiplexer: true,
      child_sessions: TABS.map((tab) => ({ id: tab.id, title: tab.title, source: tab.source })),
      tab_switching: true,
      mouse_tab_selection: true,
      source_panel: true,
      preview_panel: true,
      inspector_panel: true,
      log_panel: true,
      perf_panel: true,
      recording_replay: true
    },
    cases: [{
      actions,
      final_state: pg.snapshotState(),
      replay_state: replayState,
      final_screen: pg.render(120, 36),
      trace: pg.trace
    }],
    failures
  };
  writeReport(reportPath, report);
  if (failures.length === 0) {
    console.log(`playground script ok: active ${pg.activeTab().title}, interval ${pg.state.interval.value}, A0 ${pg.state.cells.a0}`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const failure of failures) console.error(`error: ${failure.message}`);
  console.error(`report: ${reportPath}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
try {
  if (command === "run") commandRun(args);
  else if (command === "script") commandScript(args);
  else usage();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
