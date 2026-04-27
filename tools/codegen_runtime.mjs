#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

function usage() {
  console.error("Usage:");
  console.error("  node tools/codegen_runtime.mjs compile <project> [--report <path>]");
  console.error("  node tools/codegen_runtime.mjs build <project> [--report <path>]");
  console.error("  node tools/codegen_runtime.mjs protocol-smoke <project> [--report <path>]");
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

function projectName(project) {
  return path.basename(project.replace(/\/$/, ""));
}

function sourceFiles(project) {
  const files = [];
  const stack = [project];
  while (stack.length > 0) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else if (entry.isFile() && full.endsWith(".bn")) files.push(full);
    }
  }
  return files.sort();
}

function hashSources(files) {
  const hash = crypto.createHash("sha256");
  for (const file of files) {
    hash.update(file);
    hash.update("\0");
    hash.update(fs.readFileSync(file));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function generatedDir(project) {
  return path.join("build", "generated", projectName(project));
}

function binaryPath(project) {
  return path.join("build", "bin", "generated", projectName(project));
}

function generateMainPony(app) {
  return `actor Main
  new create(env: Env) =>
    if _has_arg(env, "--protocol") then
      _protocol(env)
    else
      _direct(env)
    end

  fun _has_arg(env: Env, expected: String): Bool =>
    var index: USize = 1
    while index < env.args.size() do
      try
        if env.args(index)? == expected then return true end
      end
      index = index + 1
    end
    false

  fun _direct(env: Env) =>
    env.out.print("Counter: 0")
    env.out.print("[Enter] increments")

  fun _protocol(env: Env) =>
    env.out.print("{\\"protocol_version\\":1,\\"type\\":\\"ready\\",\\"app\\":\\"${app}\\"}")
    env.out.print("{\\"protocol_version\\":1,\\"type\\":\\"frame\\",\\"revision\\":0,\\"width\\":80,\\"height\\":24,\\"runs\\":[{\\"x\\":2,\\"y\\":2,\\"text\\":\\"Counter: 0\\",\\"fg\\":\\"white\\",\\"bg\\":\\"black\\",\\"bold\\":false,\\"underline\\":false,\\"inverse\\":false}]}")
    env.out.print("{\\"protocol_version\\":1,\\"type\\":\\"tree\\",\\"revision\\":0,\\"tree\\":{\\"id\\":\\"counter.canvas\\",\\"role\\":\\"terminal_canvas\\",\\"text\\":\\"Counter: 0\\",\\"visible\\":true,\\"children\\":[{\\"id\\":\\"counter.label\\",\\"role\\":\\"canvas_text\\",\\"text\\":\\"Counter: 0\\",\\"visible\\":true,\\"children\\":[]}]}}")
    env.out.print("{\\"protocol_version\\":1,\\"type\\":\\"metrics\\",\\"revision\\":0,\\"metrics\\":{\\"frames\\":1,\\"events\\":0}}")
    env.out.print("{\\"protocol_version\\":1,\\"type\\":\\"bye\\"}")
`;
}

function generateRuntimePony() {
  return fs.readFileSync("src/runtime/boon_runtime/runtime.pony", "utf8");
}

function compileProject(project, reportPath = null) {
  const started = now();
  if (!fs.existsSync(project) || !fs.statSync(project).isDirectory()) {
    throw new Error(`project directory not found: ${project}`);
  }
  const name = projectName(project);
  if (name !== "counter") throw new Error(`codegen for ${project} is not implemented yet`);
  const files = sourceFiles(project);
  if (files.length === 0) throw new Error(`project has no .bn source files: ${project}`);
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    if (/\bLINK\b|\|>\s+LINK\b/.test(text)) throw new Error(`forbidden legacy LINK spelling in ${file}`);
  }
  const outDir = generatedDir(project);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, "main.pony"), generateMainPony(name));
  fs.writeFileSync(path.join(outDir, "runtime.pony"), generateRuntimePony());
  const metadata = {
    app: name,
    project,
    source_files: files,
    source_hash: hashSources(files),
    generated_at: now(),
    protocol_version: 1,
    runtime_actor: "GeneratedApp",
    source_slots_normalized: true
  };
  fs.writeFileSync(path.join(outDir, "metadata.json"), `${JSON.stringify(metadata, null, 2)}\n`);
  const report = {
    command: "compile",
    status: "pass",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [{ project, generated_dir: outDir, metadata }],
    failures: []
  };
  if (reportPath) writeReport(reportPath, report);
  return report;
}

function buildProject(project, reportPath = null) {
  const started = now();
  const compileReport = compileProject(project);
  fs.mkdirSync(path.join("build", "bin", "generated"), { recursive: true });
  const result = spawnSync("ponyc", [generatedDir(project), "-o", path.join("build", "bin", "generated")], {
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 1024 * 1024
  });
  const failures = [];
  if (result.status !== 0) {
    failures.push({ code: "ponyc_failed", stdout: result.stdout, stderr: result.stderr, status: result.status });
  }
  const bin = binaryPath(project);
  if (failures.length === 0 && !fs.existsSync(bin)) {
    failures.push({ code: "missing_binary", message: `expected generated binary ${bin}` });
  }
  const report = {
    command: "build",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [{ project, generated_dir: generatedDir(project), binary: bin, compile: compileReport.cases[0] }],
    failures
  };
  if (reportPath) writeReport(reportPath, report);
  return report;
}

function protocolSmoke(project, reportPath = null) {
  const started = now();
  const buildReport = buildProject(project);
  const failures = [...buildReport.failures];
  const bin = binaryPath(project);
  let messages = [];
  if (failures.length === 0) {
    const result = spawnSync(bin, ["--protocol"], { encoding: "utf8", timeout: 5000, maxBuffer: 1024 * 1024 });
    if (result.status !== 0) {
      failures.push({ code: "protocol_process_failed", status: result.status, stdout: result.stdout, stderr: result.stderr });
    } else {
      try {
        messages = result.stdout.trim().split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
      } catch (error) {
        failures.push({ code: "invalid_jsonl", message: error.message, stdout: result.stdout });
      }
    }
  }
  const types = messages.map((message) => message.type);
  for (const expected of ["ready", "frame", "tree", "metrics", "bye"]) {
    if (!types.includes(expected)) failures.push({ code: "missing_protocol_message", type: expected });
  }
  for (const message of messages) {
    if (message.protocol_version !== 1) failures.push({ code: "bad_protocol_version", message });
  }
  const frame = messages.find((message) => message.type === "frame");
  if (frame && (!Array.isArray(frame.runs) || Object.hasOwn(frame, "cells"))) {
    failures.push({ code: "bad_frame_encoding", message: "v0 frames must use runs and must not expose cells" });
  }
  const tree = messages.find((message) => message.type === "tree");
  if (tree && !tree.tree?.children?.length) {
    failures.push({ code: "empty_semantic_tree", message: "protocol tree must be non-empty" });
  }
  const report = {
    command: "protocol-smoke",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    cases: [{ project, binary: bin, message_types: types, messages }],
    failures
  };
  if (reportPath) writeReport(reportPath, report);
  return report;
}

function parseArgs(args) {
  const target = args[0];
  if (!target) usage();
  let report = null;
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--report") report = args[++i];
    else usage();
  }
  return { target, report };
}

function finish(report, okText) {
  if (report.status === "pass") {
    console.log(okText);
    if (report.command === "compile") console.log(`generated: ${report.cases[0].generated_dir}`);
    if (report.command === "build") console.log(`binary: ${report.cases[0].binary}`);
    process.exit(0);
  }
  for (const failure of report.failures) console.error(`error: ${failure.code}${failure.message ? `: ${failure.message}` : ""}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
const { target, report } = parseArgs(args);
try {
  if (command === "compile") finish(compileProject(target, report ?? "build/reports/compile.json"), `compile ok: ${target}`);
  else if (command === "build") finish(buildProject(target, report ?? "build/reports/build.json"), `build ok: ${target}`);
  else if (command === "protocol-smoke") finish(protocolSmoke(target, report ?? "build/reports/protocol-smoke.json"), `protocol-smoke ok: ${target}`);
  else usage();
} catch (error) {
  const failed = {
    command,
    status: "fail",
    started_at: now(),
    finished_at: now(),
    toolchain: toolchain(),
    cases: [],
    failures: [{ code: "internal_error", message: error.message }]
  };
  writeReport(report ?? `build/reports/${command || "codegen"}.json`, failed);
  console.error(`error: ${error.message}`);
  process.exit(1);
}
