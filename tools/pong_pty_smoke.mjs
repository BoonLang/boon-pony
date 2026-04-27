#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const reportPath = "build/reports/pong-pty.json";
const session = `boonpony_pong_${process.pid}`;

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

function writeReport(report) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
}

const started = new Date().toISOString();
const failures = [];
let output = "";
try {
  spawnSync("tmux", ["new-session", "-d", "-s", session, "-x", "100", "-y", "32", "bash", "-lc", "export PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH; build/bin/boonpony play examples/terminal/pong; code=$?; echo __EXIT:$code; sleep 3"], { encoding: "utf8", timeout: 5000 });
  output = waitFor("Press Space to start", 5000);
  if (!output.includes("Press Space to start")) failures.push({ code: "missing_initial_status" });
  spawnSync("tmux", ["send-keys", "-t", session, "Space"], { encoding: "utf8", timeout: 1000 });
  output = waitFor("Point scored", 5000);
  if (!output.includes("Point scored")) failures.push({ code: "score_status_missing" });
  if (!output.includes("1 : 0")) failures.push({ code: "score_not_updated" });
  spawnSync("tmux", ["send-keys", "-t", session, "Q"], { encoding: "utf8", timeout: 1000 });
  output = waitFor("__EXIT:", 5000);
  if (!output.includes("terminal restored")) failures.push({ code: "terminal_not_restored" });
  if (!output.includes("final score 1 : 0")) failures.push({ code: "final_score_missing" });
  if (!output.includes("__EXIT:0")) failures.push({ code: "play_exit_nonzero" });
} finally {
  spawnSync("tmux", ["kill-session", "-t", session], { encoding: "utf8", timeout: 1000 });
}

const report = {
  command: "pong-pty-smoke",
  status: failures.length === 0 ? "pass" : "fail",
  started_at: started,
  finished_at: new Date().toISOString(),
  cases: [{
    project: "examples/terminal/pong",
    interactions: ["open Pong", "Space starts and scores", "Q quits"],
    output_excerpt: output.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").slice(0, 2000)
  }],
  failures
};
writeReport(report);
if (failures.length === 0) {
  console.log(`pong PTY ok: score updated and terminal restored; report: ${reportPath}`);
  process.exit(0);
}
for (const failure of failures) console.error(`error: ${failure.code}`);
console.error(`report: ${reportPath}`);
process.exit(1);
