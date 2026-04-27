#!/usr/bin/env node
import fs from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import path from "node:path";

function usage() {
  console.error("Usage:");
  console.error("  node tools/terminal_safety.mjs keyboard-test");
  console.error("  node tools/terminal_safety.mjs verify-terminal-safety --pty [--report <path>]");
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

function decodeKey(buffer) {
  const bytes = [...buffer];
  const text = buffer.toString("utf8");
  if (bytes.length === 1 && bytes[0] === 0x03) return "CtrlC";
  if (text === "Q" || text === "q") return "Q";
  if (text === "\r" || text === "\n") return "Enter";
  if (text === " ") return "Space";
  if (text === "\x1b[A") return "ArrowUp";
  if (text === "\x1b[B") return "ArrowDown";
  if (text === "\x1b[C") return "ArrowRight";
  if (text === "\x1b[D") return "ArrowLeft";
  if (/^\x1b\[<\d+;\d+;\d+[mM]$/.test(text)) return "MouseSGR";
  if (/^[\x20-\x7e]$/.test(text)) return `Text:${text}`;
  return `Bytes:${bytes.map((byte) => byte.toString(16).padStart(2, "0")).join(" ")}`;
}

function enterTerminal() {
  process.stdout.write("\x1b[?1049h\x1b[?25l");
}

function restoreTerminal() {
  try {
    if (process.stdin.isTTY && process.stdin.setRawMode) process.stdin.setRawMode(false);
  } finally {
    process.stdout.write("\x1b[?25h\x1b[?1049l");
    process.stdout.write("restore: ok\n");
  }
}

function commandKeyboardTest() {
  if (!process.stdin.isTTY || !process.stdin.setRawMode) {
    console.error("error: interactive TUI requires raw terminal mode; platform not yet supported");
    process.exit(3);
  }
  process.stdin.setEncoding(null);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdout.write("keyboard-test ready\n");
  enterTerminal();
  const timeout = setTimeout(() => {
    restoreTerminal();
    process.stdout.write("error: keyboard-test timed out waiting for input\n");
    process.exit(1);
  }, 3000);

  process.stdin.on("data", (chunk) => {
    clearTimeout(timeout);
    const key = decodeKey(Buffer.from(chunk));
    restoreTerminal();
    process.stdout.write(`decoded: ${key}\n`);
    process.exit(0);
  });
}

function runPtyCase(name, input) {
  const session = `boonpony_safety_${process.pid}_${name}`;
  const shellCommand = "bash -lc 'PATH=/home/martinkavik/.local/share/ponyup/bin:$PATH build/bin/boonpony tui --keyboard-test; code=$?; echo __EXIT:$code; sleep 3'";
  let output = "";
  let status = 1;
  let signal = null;
  try {
    const start = spawnSync("tmux", ["new-session", "-d", "-s", session, "-x", "80", "-y", "24", shellCommand], {
      encoding: "utf8",
      timeout: 5000
    });
    if (start.status !== 0) {
      output = `${start.stdout ?? ""}${start.stderr ?? ""}`;
      status = start.status ?? 1;
      signal = start.signal;
    } else {
      waitForPane(session, "keyboard-test ready", 3000);
      spawnSync("tmux", ["send-keys", "-t", session, input], { encoding: "utf8", timeout: 1000 });
      output = waitForPane(session, "__EXIT:", 3000);
      const exitMatch = output.match(/__EXIT:(\d+)/);
      status = exitMatch ? Number(exitMatch[1]) : 1;
    }
  } finally {
    spawnSync("tmux", ["kill-session", "-t", session], { encoding: "utf8", timeout: 1000 });
  }
  const expectedDecode = name === "ctrl_c_restore" ? "decoded: CtrlC" : "decoded: Q";
  const pass = status === 0 && output.includes(expectedDecode) && output.includes("restore: ok");
  return {
    name,
    status: pass ? "pass" : "fail",
    exit_status: status,
    signal,
    expected_decode: expectedDecode,
    decoded: output.includes(expectedDecode),
    restored: output.includes("restore: ok"),
    output_excerpt: output.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").slice(0, 1000)
  };
}

function capturePane(session) {
  try {
    return execFileSync("tmux", ["capture-pane", "-p", "-t", session], { encoding: "utf8" });
  } catch {
    return "";
  }
}

function waitForPane(session, needle, timeoutMs) {
  const started = Date.now();
  let output = "";
  while ((Date.now() - started) < timeoutMs) {
    output = capturePane(session);
    if (output.includes(needle)) return output;
    spawnSync("sleep", ["0.05"], { timeout: 1000 });
  }
  return output;
}

function commandVerifySafety(args) {
  let pty = false;
  let reportPath = "build/reports/verify-terminal-safety.json";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--pty") pty = true;
    else if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  if (!pty) usage();

  const started = now();
  const cases = [
    runPtyCase("q_restore", "Q"),
    runPtyCase("ctrl_c_restore", "C-c")
  ];
  const failures = cases.filter((item) => item.status !== "pass");
  const report = {
    command: "verify-terminal-safety",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    terminal_capabilities: {
      alternate_screen: true,
      cursor_hide_show: true,
      raw_input: true,
      pty_command: "tmux new-session/send-keys"
    },
    cases,
    failures
  };
  writeReport(reportPath, report);
  if (failures.length === 0) {
    console.log("terminal-safety ok: PTY decoded Q and Ctrl+C, restore observed");
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const failure of failures) console.error(`error: ${failure.name} failed`);
  console.error(`report: ${reportPath}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
if (command === "keyboard-test") commandKeyboardTest();
else if (command === "verify-terminal-safety") commandVerifySafety(args);
else usage();
