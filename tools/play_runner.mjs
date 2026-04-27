#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

function usage() {
  console.error("Usage:");
  console.error("  node tools/play_runner.mjs play <project> [--report <path>]");
  process.exit(2);
}

function projectName(project) {
  return path.basename(project.replace(/\/$/, ""));
}

function writeReport(file, report) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`);
}

function runBuild(project) {
  return spawnSync("node", ["tools/codegen_runtime.mjs", "build", project, "--report", `build/reports/build-${projectName(project)}.json`], {
    encoding: "utf8",
    timeout: 30000,
    maxBuffer: 1024 * 1024,
    env: process.env
  });
}

function commandPlay(args) {
  const project = args[0];
  if (!project) usage();
  let reportPath = `build/reports/play-${projectName(project)}.json`;
  for (let i = 1; i < args.length; i += 1) {
    if (args[i] === "--report") reportPath = args[++i];
    else usage();
  }
  const started = new Date().toISOString();
  const build = runBuild(project);
  const failures = [];
  if (build.status !== 0) {
    failures.push({ code: "build_failed", stdout: build.stdout, stderr: build.stderr, status: build.status });
  }
  const binary = path.join("build", "bin", "generated", projectName(project));
  let play = { status: 1, stdout: "", stderr: "" };
  if (failures.length === 0) {
    const args = (process.stdin.isTTY && process.stdout.isTTY) ? [] : ["--demo"];
    if (args.length === 0) {
      play = spawnSync(binary, args, { stdio: "inherit", env: process.env });
    } else {
      play = spawnSync(binary, args, { encoding: "utf8", timeout: 5000, maxBuffer: 1024 * 1024, env: process.env });
      if (play.stdout) process.stdout.write(play.stdout);
      if (play.stderr) process.stderr.write(play.stderr);
    }
    if (play.status !== 0) {
      failures.push({ code: "play_failed", status: play.status, stdout: play.stdout, stderr: play.stderr });
    }
  }
  const report = {
    command: "play",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: new Date().toISOString(),
    cases: [{
      project,
      binary,
      mode: (process.stdin.isTTY && process.stdout.isTTY) ? "interactive" : "demo",
      stdout: play.stdout ?? ""
    }],
    failures
  };
  writeReport(reportPath, report);
  process.exit(failures.length === 0 ? 0 : 1);
}

const [command, ...args] = process.argv.slice(2);
if (command === "play") commandPlay(args);
else usage();
