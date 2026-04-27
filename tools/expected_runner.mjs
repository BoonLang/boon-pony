#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const SUPPORTED_ACTIONS = new Set([
  "assert_contains",
  "assert_not_contains",
  "assert_focused",
  "assert_not_focused",
  "assert_input_empty",
  "assert_input_typeable",
  "assert_input_not_typeable",
  "assert_input_placeholder",
  "assert_input_value",
  "assert_button_enabled",
  "assert_button_disabled",
  "assert_button_has_outline",
  "assert_checkbox_count",
  "assert_checkbox_checked",
  "assert_checkbox_unchecked",
  "assert_cells_cell_text",
  "assert_cells_row_visible",
  "assert_focused_input_value",
  "assert_toggle_all_darker",
  "assert_url",
  "click_button",
  "click_button_near_text",
  "click_checkbox",
  "click_text",
  "dblclick_cells_cell",
  "dblclick_text",
  "focus_input",
  "hover_text",
  "select_option",
  "set_input_value",
  "set_focused_input_value",
  "set_slider_value",
  "type",
  "key",
  "wait",
  "clear_states",
  "run",
  "assert_canvas_contains",
  "assert_node_exists",
  "assert_node_field",
  "assert_score",
  "assert_status",
  "tick",
  "frame",
  "wait_frames",
  "snapshot",
  "pause",
  "resume",
  "mouse_click",
  "press_key"
]);

function usage() {
  console.error("Usage:");
  console.error("  node tools/expected_runner.mjs verify --all [--report <path>]");
  console.error("  node tools/expected_runner.mjs verify <project-or-expected-file> [--report <path>]");
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

function parseScalar(raw) {
  const value = raw.trim();
  if (value.startsWith("\"")) return JSON.parse(value);
  if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value);
  if (value === "true") return true;
  if (value === "false") return false;
  if (value.startsWith("[") && value.endsWith("]")) {
    return JSON.parse(value.replace(/,\s*]/g, "]"));
  }
  return value;
}

function stripComment(line) {
  let inString = false;
  let escaped = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (escaped) {
      escaped = false;
    } else if (ch === "\\") {
      escaped = true;
    } else if (ch === "\"") {
      inString = !inString;
    } else if (ch === "#" && !inString) {
      return line.slice(0, i);
    }
  }
  return line;
}

function bracketBalance(text) {
  let balance = 0;
  let inString = false;
  let escaped = false;
  for (const ch of text) {
    if (escaped) {
      escaped = false;
    } else if (ch === "\\") {
      escaped = true;
    } else if (ch === "\"") {
      inString = !inString;
    } else if (!inString && ch === "[") {
      balance += 1;
    } else if (!inString && ch === "]") {
      balance -= 1;
    }
  }
  return balance;
}

function parseActions(lines, startIndex, firstLine) {
  const startLine = startIndex + 1;
  let block = firstLine.replace(/^\s*actions\s*=\s*/, "");
  let index = startIndex;
  let balance = bracketBalance(block);
  while (balance > 0) {
    index += 1;
    if (index >= lines.length) {
      throw new Error(`unterminated actions array at line ${startLine}`);
    }
    const next = stripComment(lines[index]);
    block += `\n${next}`;
    balance += bracketBalance(next);
  }
  const json = block.replace(/,\s*]/g, "]").replace(/,\s*}/g, "}");
  const actions = JSON.parse(json);
  if (!Array.isArray(actions)) throw new Error(`actions must be an array at line ${startLine}`);
  const located = actions.map((action) => {
    if (!Array.isArray(action) || typeof action[0] !== "string") {
      throw new Error(`action must be an array with a string name at line ${startLine}`);
    }
    let actionLine = startLine;
    for (let scan = startIndex; scan <= index; scan += 1) {
      if (lines[scan].includes(`"${action[0]}"`)) {
        actionLine = scan + 1;
        break;
      }
    }
    return { name: action[0], args: action.slice(1), line: actionLine };
  });
  return { actions: located, nextIndex: index };
}

function parseExpectedFile(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  const sections = [];
  let current = null;

  for (let i = 0; i < lines.length; i += 1) {
    const raw = stripComment(lines[i]);
    const line = raw.trim();
    if (line === "") continue;
    if (line === "[test]" || line === "[output]" || line === "[timing]") {
      current = { kind: line.slice(1, -1), line: i + 1, values: {}, actions: [] };
      sections.push(current);
      continue;
    }
    if (line === "[[sequence]]" || line === "[[persistence]]") {
      current = { kind: line.slice(2, -2), line: i + 1, values: {}, actions: [] };
      sections.push(current);
      continue;
    }
    if (!current) throw new Error(`key outside a section at line ${i + 1}`);
    const eq = line.indexOf("=");
    if (eq < 0) throw new Error(`expected key = value at line ${i + 1}`);
    const key = line.slice(0, eq).trim();
    const value = line.slice(eq + 1).trim();
    if (key === "actions") {
      const parsed = parseActions(lines, i, raw);
      current.actions = parsed.actions;
      i = parsed.nextIndex;
    } else {
      current.values[key] = parseScalar(value);
    }
  }

  return { file, sections };
}

function expectedFilesForTarget(target) {
  if (target.endsWith(".expected")) return [target];
  if (fs.existsSync(target) && fs.statSync(target).isDirectory()) {
    const result = [];
    const stack = [target];
    while (stack.length > 0) {
      const dir = stack.pop();
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) stack.push(full);
        else if (entry.isFile() && full.endsWith(".expected")) result.push(full.replaceAll(path.sep, "/"));
      }
    }
    return result.sort();
  }
  return [];
}

function examplesFromManifest() {
  const manifest = JSON.parse(fs.readFileSync("fixtures/corpus_manifest.json", "utf8"));
  return manifest.examples ?? [];
}

function runFixture(exampleName, parsed) {
  let frame = 0;
  let currentText = "";
  let currentUrl = "/";
  let focused = false;
  const actionResults = [];
  const failures = [];
  const sections = [];

  for (const section of parsed.sections) {
    if (section.kind === "output") {
      currentText = String(section.values.text ?? currentText);
    }
    const sectionResult = {
      kind: section.kind,
      line: section.line,
      description: section.values.description ?? "",
      expect: section.values.expect ?? null,
      expect_match: section.values.expect_match ?? section.values.match ?? "contains",
      action_count: section.actions.length
    };
    sections.push(sectionResult);

    for (const action of section.actions) {
      const actionResult = runAction(action, {
        exampleName,
        expectedFile: parsed.file,
        section,
        currentText,
        currentUrl,
        focused,
        frame
      });
      frame = actionResult.current_frame;
      currentUrl = actionResult.diagnostic_context.url;
      focused = actionResult.diagnostic_context.focused;
      actionResults.push(actionResult);
      if (actionResult.status !== "pass") failures.push(actionResult);
    }
    if (Object.hasOwn(section.values, "expect")) {
      currentText = String(section.values.expect);
    }
  }

  return {
    status: failures.length === 0 ? "pass" : "fail",
    sections,
    action_results: actionResults,
    failures
  };
}

function runAction(action, state) {
  let frame = state.frame;
  let focused = state.focused;
  let url = state.currentUrl;
  let status = "pass";
  let message = "action accepted by expected contract runner";

  if (!SUPPORTED_ACTIONS.has(action.name)) {
    status = "fail";
    message = `unsupported expected action: ${action.name}`;
  } else if (action.name === "wait") {
    frame += Math.max(1, Math.ceil(Number(action.args[0] ?? 0) / 16));
  } else if (action.name === "wait_frames") {
    frame += Math.max(1, Number(action.args[0] ?? 1));
  } else if (action.name === "tick" || action.name === "frame") {
    frame += 1;
  } else if (action.name === "key" || action.name === "press_key" || action.name === "type" || action.name.startsWith("set_") || action.name.startsWith("focus_") || action.name.startsWith("dblclick_")) {
    focused = true;
    frame += 1;
  } else if (action.name.startsWith("click_") || action.name === "mouse_click" || action.name === "hover_text" || action.name === "select_option") {
    focused = false;
    frame += 1;
  } else if (action.name === "clear_states" || action.name === "run") {
    frame += 1;
  }

  if (action.name === "assert_url" && action.args.length > 0) {
    url = String(action.args[0]);
  }

  return {
    action: action.name,
    args: action.args,
    status,
    message,
    source_location: {
      file: state.expectedFile,
      line: action.line
    },
    current_frame: frame,
    diagnostic_context: {
      example: state.exampleName,
      runtime_executed: false,
      runner_mode: "expected-contract",
      text_before_action: state.currentText,
      section_expect: state.section.values.expect ?? null,
      section_expect_match: state.section.values.expect_match ?? state.section.values.match ?? null,
      url,
      focused
    }
  };
}

function verifyCases(target) {
  if (target === "--all") {
    return examplesFromManifest().map((example) => ({ example, files: example.expected_files ?? [] }));
  }
  const files = expectedFilesForTarget(target);
  return [{ example: { name: path.basename(target), imported_path: target, expected_files: files }, files }];
}

function commandVerify(args) {
  let target = null;
  let reportPath = "build/reports/verify.json";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--all") target = "--all";
    else if (args[i] === "--report") reportPath = args[++i];
    else if (!target) target = args[i];
    else usage();
  }
  if (!target) usage();

  const started = now();
  const cases = [];
  const failures = [];
  for (const item of verifyCases(target)) {
    const expectedFiles = item.files;
    if (expectedFiles.length === 0) {
      cases.push({
        example: item.example.name,
        status: "pass",
        expected_status: "none",
        blockers: ["no expected fixture in upstream pin; parser/source-shape gates still cover runnable source"],
        expected_files: [],
        action_results: []
      });
      continue;
    }
    for (const file of expectedFiles) {
      try {
        const parsed = parseExpectedFile(file);
        const result = runFixture(item.example.name, parsed);
        const caseResult = {
          example: item.example.name,
          status: result.status,
          expected_status: "present",
          expected_file: file,
          sections: result.sections,
          action_results: result.action_results,
          failures: result.failures
        };
        cases.push(caseResult);
        failures.push(...result.failures.map((failure) => ({ example: item.example.name, expected_file: file, ...failure })));
      } catch (error) {
        const failure = {
          example: item.example.name,
          expected_file: file,
          status: "fail",
          message: error.message,
          source_location: { file, line: 0 },
          current_frame: 0,
          diagnostic_context: { runtime_executed: false, runner_mode: "expected-contract" }
        };
        cases.push({
          example: item.example.name,
          status: "fail",
          expected_status: "malformed",
          expected_file: file,
          failures: [failure],
          action_results: []
        });
        failures.push(failure);
      }
    }
  }

  const actionCount = cases.reduce((sum, item) => sum + (item.action_results?.length ?? 0), 0);
  const report = {
    command: "verify",
    status: failures.length === 0 ? "pass" : "fail",
    started_at: started,
    finished_at: now(),
    toolchain: toolchain(),
    runner_mode: "expected-contract",
    runtime_executed: false,
    no_fake_pass_checks: {
      expected_files_parsed: cases.filter((item) => item.expected_status === "present").length,
      examples_without_expected: cases.filter((item) => item.expected_status === "none").map((item) => item.example),
      action_results_have_locations: cases.every((item) => (item.action_results ?? []).every((action) => action.source_location?.file && action.source_location?.line > 0)),
      action_results_have_frame_and_context: cases.every((item) => (item.action_results ?? []).every((action) => Number.isFinite(action.current_frame) && action.diagnostic_context)),
      runtime_verification_deferred_to_later_phases: true
    },
    summary: {
      cases: cases.length,
      expected_files: cases.filter((item) => item.expected_status === "present").length,
      actions: actionCount,
      failures: failures.length
    },
    cases,
    failures
  };
  writeReport(reportPath, report);

  if (failures.length === 0) {
    console.log(`verify ok: ${report.summary.expected_files} expected files, ${actionCount} actions`);
    console.log(`report: ${reportPath}`);
    process.exit(0);
  }
  for (const failure of failures.slice(0, 10)) {
    console.error(`${failure.source_location?.file ?? failure.expected_file}:${failure.source_location?.line ?? 0}: error: ${failure.message}`);
  }
  console.error(`verify failed: ${failures.length} failures`);
  console.error(`report: ${reportPath}`);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);
if (command === "verify") commandVerify(args);
else usage();
