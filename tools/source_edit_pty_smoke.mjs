#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const reportPath = "build/reports/source-edit-pty.json";
const session = `boonpony_source_edit_${process.pid}`;

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

function sendLiteral(text) {
  return spawnSync("tmux", ["send-keys", "-t", session, "-l", text], { encoding: "utf8", timeout: 1000 });
}

function sendKey(key) {
  return spawnSync("tmux", ["send-keys", "-t", session, key], { encoding: "utf8", timeout: 1000 });
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

function expectAfter(label, action, needle, timeoutMs = 6000) {
  interactions.push(label);
  action();
  output = waitFor(needle, timeoutMs);
  if (!output.includes(needle)) failures.push({ code: `missing_${label.replace(/[^a-z0-9]+/gi, "_").toLowerCase()}`, expected: needle, output_excerpt: clean(output) });
}

try {
  const shell = "bash -lc 'export PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH; export EDITOR=true; export BOONPONY_OPEN_EDITOR=1; build/bin/boonpony tui --example pong; code=$?; echo __EXIT:$code; sleep 3'";
  const start = spawnSync("tmux", ["new-session", "-d", "-s", session, "-x", "132", "-y", "40", shell], {
    encoding: "utf8",
    timeout: 5000
  });
  if (start.status !== 0) {
    failures.push({ code: "tmux_start_failed", stdout: start.stdout, stderr: start.stderr, status: start.status });
  } else {
    output = waitFor("Active: Pong", 5000);
    if (!output.includes("Active: Pong")) failures.push({ code: "pong_example_not_opened", output_excerpt: clean(output) });
    if (!output.includes("examples/terminal/pong/pong.bn")) failures.push({ code: "source_panel_missing_pong", output_excerpt: clean(output) });

    expectAfter("enter source edit", () => sendLiteral("e"), "Source edit mode: on");
    expectAfter("apply valid edit", () => sendLiteral("v"), "Valid edit applied");
    expectAfter("working diff", () => sendLiteral("d"), "Working diff: 1");
    expectAfter("reload working source", () => sendLiteral("r"), "Reloaded working source");
    expectAfter("rebuild updated game", () => sendLiteral("b"), "Build: passed", 10000);
    expectAfter("rerun updated game", () => sendLiteral("p"), "Rerun: Pong preview restarted");
    expectAfter("invalid diagnostic", () => sendLiteral("!"), "Diagnostic: invalid source marker");
    expectAfter("external editor", () => sendLiteral("o"), "External editor: true completed");

    sendKey("Q");
    output = waitFor("__EXIT:", 5000);
    if (!output.includes("__EXIT:0")) failures.push({ code: "source_edit_exit_nonzero", output_excerpt: clean(output) });
    if (!output.includes("terminal restored")) failures.push({ code: "terminal_not_restored", output_excerpt: clean(output) });
    if (!output.includes("Diagnostics: invalid source marker")) failures.push({ code: "diagnostic_summary_missing", output_excerpt: clean(output) });
    if (!output.includes("Build: passed")) failures.push({ code: "build_summary_missing", output_excerpt: clean(output) });
    if (!output.includes("Rerun: Pong preview restarted")) failures.push({ code: "rerun_summary_missing", output_excerpt: clean(output) });
  }
} finally {
  spawnSync("tmux", ["kill-session", "-t", session], { encoding: "utf8", timeout: 1000 });
}

const report = {
  command: "source-edit-pty-smoke",
  status: failures.length === 0 ? "pass" : "fail",
  started_at: started,
  finished_at: new Date().toISOString(),
  cases: [{
    project: "boonpony tui --example pong",
    interactions,
    output_excerpt: clean(output)
  }],
  failures
};
writeReport(report);
if (failures.length === 0) {
  console.log(`source edit PTY ok: edit/reload/build/rerun/diagnostic/editor path verified; report: ${reportPath}`);
  process.exit(0);
}
for (const failure of failures) console.error(`error: ${failure.code}`);
console.error(`report: ${reportPath}`);
process.exit(1);
