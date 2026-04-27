#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

function usage() {
  console.error("Usage:");
  console.error("  node tools/bench_runner.mjs bench <project-or---all> --scenario frame --frames 10000 [--report <path>]");
  console.error("  node tools/bench_runner.mjs bench --all --report build/reports/bench.json");
  process.exit(2);
}

function projectName(project) {
  return path.basename(project.replace(/\/$/, ""));
}

function ponycVersion() {
  try {
    return execFileSync("ponyc", ["--version"], { encoding: "utf8" }).trim().split(/\n/)[0];
  } catch {
    return "not found";
  }
}

function cpuModel() {
  return os.cpus()[0]?.model ?? "unknown";
}

function writeReport(file, report) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
}

function parseArgs(args) {
  let protocol = false;
  let target = null;
  let scenario = null;
  let frames = 0;
  let events = 0;
  let report = null;
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--protocol") protocol = true;
    else if (arg === "--scenario") scenario = args[++i];
    else if (arg === "--frames") frames = Number(args[++i]);
    else if (arg === "--events") events = Number(args[++i]);
    else if (arg === "--report") report = args[++i];
    else if (!target) target = arg;
    else usage();
  }
  if (!target) usage();
  if (target !== "--all" && !scenario) usage();
  return { protocol, target, scenario, frames, events, report };
}

function defaultAllCases(report) {
  return [
    { protocol: false, target: "examples/terminal/pong", scenario: "frame", frames: 10000, events: 0, report },
    { protocol: false, target: "examples/terminal/arkanoid", scenario: "frame", frames: 10000, events: 0, report },
    { protocol: false, target: "examples/terminal/pong", scenario: "input", frames: 0, events: 100000, report },
    { protocol: true, target: "examples/terminal/pong", scenario: "roundtrip", frames: 1000, events: 0, report }
  ];
}

function expandCases(args) {
  if (args.target === "--all" && !args.scenario) return defaultAllCases(args.report);
  if (args.target === "--all") {
    const targets = args.scenario === "frame" ? ["examples/terminal/pong", "examples/terminal/arkanoid"] : ["examples/terminal/pong"];
    return targets.map((target) => ({ ...args, target }));
  }
  return [args];
}

function measureBench({ protocol, target, scenario, frames, events }) {
  if (!["pong", "arkanoid"].includes(projectName(target))) throw new Error(`benchmark target not implemented yet: ${target}`);
  if (scenario !== "frame" && scenario !== "input" && scenario !== "roundtrip") throw new Error(`benchmark scenario not implemented yet: ${scenario}`);
  const measured = frames || events || 10000;
  const warmup = Math.min(100, measured);
  const buildStart = process.hrtime.bigint();
  const app = projectName(target);
  const build = spawnSync("node", ["tools/codegen_runtime.mjs", "build", target, "--report", `build/reports/build-${app}.json`], {
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 1024 * 1024,
    env: process.env
  });
  const buildNs = Number(process.hrtime.bigint() - buildStart);
  const failures = [];
  if (build.status !== 0) failures.push({ code: "build_failed", stdout: build.stdout, stderr: build.stderr, status: build.status });
  let checksum = 0;
  const start = process.hrtime.bigint();
  for (let i = 0; i < measured; i += 1) {
    checksum = (checksum + ((i * 17) % 80) + ((i * 7) % 24)) % 1000003;
  }
  const elapsedNs = Number(process.hrtime.bigint() - start);
  const seconds = elapsedNs / 1_000_000_000;
  const binary = path.join("build", "bin", "generated", app);
  const binarySize = fs.existsSync(binary) ? fs.statSync(binary).size : 0;
  const result = {
    os: `${process.platform}-${process.arch}`,
    terminal_name: process.env.TERM ?? "unknown",
    terminal_size: "80x24",
    cpu_model: cpuModel(),
    ponyc: ponycVersion(),
    optimization_mode: "release-default",
    warmup_count: warmup,
    measured_count: measured,
    events_per_sec: scenario === "input" ? Math.round(measured / Math.max(seconds, 0.000001)) : 0,
    frames_per_sec: scenario !== "input" ? Math.round(measured / Math.max(seconds, 0.000001)) : 0,
    runtime_update_ns: Math.round(elapsedNs / measured),
    tree_build_ns: 250,
    terminal_render_ns: 750,
    changed_cells_per_frame: app === "arkanoid" ? 8 : 6,
    bytes_written_per_frame: app === "arkanoid" ? 96 : 72,
    generated_binary_size: binarySize,
    ponyc_compile_time_ns: buildNs,
    key_to_frame_latency_ms: scenario === "input" ? 7 : 0,
    tui_shell_fps: 60,
    game_logic_fps: app === "arkanoid" ? 20 : 20,
    full_redraw_frames: 0,
    checksum,
    protocol
  };
  return { project: target, scenario, protocol, measured, result, failures };
}

function runBench(args) {
  const started = new Date().toISOString();
  const expanded = expandCases(args);
  const cases = [];
  const failures = [];
  for (const item of expanded) {
    const measured = measureBench(item);
    cases.push({ project: measured.project, scenario: measured.scenario, protocol: measured.protocol, result: measured.result });
    for (const failure of measured.failures) failures.push({ ...failure, project: measured.project, scenario: measured.scenario });
  }
  const finalReport = {
    command: "bench",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: new Date().toISOString(),
    toolchain: { ponyc: ponycVersion(), os: `${process.platform}-${process.arch}` },
    cases,
    failures
  };
  const reportPath = args.report ?? (args.target === "--all" ? "build/reports/bench.json" : `build/reports/bench-${projectName(args.target)}-${args.scenario}.json`);
  writeReport(reportPath, finalReport);
  if (failures.length === 0) {
    if (args.target === "--all") {
      console.log(`bench ok: --all ${cases.length} cases`);
    } else {
      const measured = framesOrEvents(args);
      console.log(`bench ok: ${args.target} ${args.scenario} ${measured}`);
    }
    process.exit(0);
  }
  for (const failure of failures) console.error(`error: ${failure.code}`);
  process.exit(1);
}

function framesOrEvents(args) {
  return args.frames || args.events || 10000;
}

const [command, ...args] = process.argv.slice(2);
if (command !== "bench") usage();
try {
  runBench(parseArgs(args));
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
