#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const reportPath = "build/reports/playground-pty.json";
const session = `boonpony_playground_${process.pid}`;
const forbidden = /\b(error|panic|corrupt|ExpectedRecordValue)\b/i;

function capture() {
  try {
    return execFileSync("tmux", ["capture-pane", "-p", "-t", session], { encoding: "utf8" });
  } catch {
    return "";
  }
}

function waitFor(needle, timeoutMs) {
  const started = Date.now();
  let output = "";
  while ((Date.now() - started) < timeoutMs) {
    output = capture();
    if (output.includes(needle)) return output;
    spawnSync("sleep", ["0.05"], { timeout: 1000 });
  }
  return output;
}

function sendKey(key) {
  return spawnSync("tmux", ["send-keys", "-t", session, key], { encoding: "utf8", timeout: 1000 });
}

function sendLiteral(text) {
  return spawnSync("tmux", ["send-keys", "-t", session, "-l", text], { encoding: "utf8", timeout: 1000 });
}

function writeReport(report) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
}

function clean(output) {
  return output.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").slice(0, 4000);
}

const started = new Date().toISOString();
const failures = [];
const interactions = [];
let output = "";

function expectAfter(label, action, needle, timeoutMs = 5000) {
  interactions.push(label);
  action();
  output = waitFor(needle, timeoutMs);
  if (!output.includes(needle)) failures.push({ code: `missing_${label.replace(/[^a-z0-9]+/gi, "_").toLowerCase()}`, expected: needle, output_excerpt: clean(output) });
}

try {
  const shell = "bash -lc 'export PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH; build/bin/boonpony tui; code=$?; echo __EXIT:$code; sleep 3'";
  const start = spawnSync("tmux", ["new-session", "-d", "-s", session, "-x", "132", "-y", "40", shell], {
    encoding: "utf8",
    timeout: 5000
  });
  if (start.status !== 0) {
    failures.push({ code: "tmux_start_failed", stdout: start.stdout, stderr: start.stderr, status: start.status });
  } else {
    output = waitFor("Counter: 0", 5000);
    if (!output.includes("Counter: 0")) failures.push({ code: "initial_counter_missing", output_excerpt: clean(output) });

    expectAfter("counter increments", () => sendKey("Enter"), "Counter: 1");
    expectAfter("select interval", () => sendKey("S-Right"), "Active: Interval");
    output = waitFor("Interval: 1", 5000);
    if (!output.includes("Interval: 1")) failures.push({ code: "interval_did_not_tick", output_excerpt: clean(output) });

    expectAfter("select cells", () => sendKey("S-Right"), "Active: Cells");
    sendKey("Enter");
    sendKey("BSpace");
    sendLiteral("7");
    expectAfter("cells commits A0", () => sendKey("Enter"), "A0 = 7");

    expectAfter("cells dynamic renders", () => sendKey("S-Right"), "Active: Cells Dynamic");
    if (!output.includes("Dynamic total: 21")) failures.push({ code: "cells_dynamic_missing", output_excerpt: clean(output) });

    expectAfter("mouse selects TodoMVC", () => sendLiteral("\x1b[<0;44;1M"), "Active: TodoMVC");
    expectAfter("TodoMVC adds Write tests", () => sendLiteral("a"), "Write tests");

    expectAfter("select Pong", () => sendKey("S-Right"), "Active: Pong");
    expectAfter("Pong rally", () => sendKey("Enter"), "Rally");

    expectAfter("Arkanoid bricks and paddle", () => sendKey("S-Right"), "Active: Arkanoid");
    if (!output.includes("Bricks:") || !output.includes("Paddle")) failures.push({ code: "arkanoid_projection_missing", output_excerpt: clean(output) });

    expectAfter("Temperature Converter selected", () => sendKey("S-Right"), "Active: Temperature Converter");
    sendLiteral("c");
    expectAfter("Temperature both directions", () => sendLiteral("f"), "Both directions ok");

    expectAfter("Flight Booker selected", () => sendKey("S-Right"), "Active: Flight Booker");
    expectAfter("Flight Booker books return", () => sendLiteral("b"), "Booked: return flight");

    expectAfter("Timer selected", () => sendKey("S-Right"), "Active: Timer");
    expectAfter("Timer updates elapsed duration", () => sendLiteral("u"), "Elapsed: 12");

    expectAfter("CRUD selected", () => sendKey("S-Right"), "Active: CRUD");
    expectAfter("CRUD creates Ada Lovelace", () => sendLiteral("a"), "Ada Lovelace");

    expectAfter("Circle Drawer selected", () => sendKey("S-Right"), "Active: Circle Drawer");
    sendLiteral("\x1b[<0;50;12M");
    output = waitFor("Circles:1", 3000);
    sendLiteral("\x1b[<0;54;14M");
    output = waitFor("Circles:2", 3000);
    expectAfter("Circle Drawer undo leaves one", () => sendLiteral("u"), "Circles:1");

    expectAfter("tab wrap forward", () => sendKey("S-Right"), "Active: Counter");
    expectAfter("tab wrap backward", () => sendKey("S-Left"), "Active: Circle Drawer");

    sendKey("Q");
    output = waitFor("__EXIT:", 5000);
    if (!output.includes("__EXIT:0")) failures.push({ code: "playground_exit_nonzero", output_excerpt: clean(output) });
    if (!output.includes("terminal restored")) failures.push({ code: "terminal_not_restored", output_excerpt: clean(output) });
    if (!output.includes("log clean: yes")) failures.push({ code: "log_clean_summary_missing", output_excerpt: clean(output) });
    if (forbidden.test(output)) failures.push({ code: "forbidden_log_marker", output_excerpt: clean(output) });
  }
} finally {
  spawnSync("tmux", ["kill-session", "-t", session], { encoding: "utf8", timeout: 1000 });
}

const report = {
  command: "playground-pty-smoke",
  status: failures.length === 0 ? "pass" : "fail",
  started_at: started,
  finished_at: new Date().toISOString(),
  cases: [{
    project: "boonpony tui",
    interactions,
    output_excerpt: clean(output)
  }],
  failures
};
writeReport(report);
if (failures.length === 0) {
  console.log(`playground PTY ok: all tabs exercised and terminal restored; report: ${reportPath}`);
  process.exit(0);
}
for (const failure of failures) console.error(`error: ${failure.code}`);
console.error(`report: ${reportPath}`);
process.exit(1);
