#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const ROOT = process.cwd();
const UPSTREAM_DIR = path.join(ROOT, "third_party", "boon-upstream");
const EXAMPLE_ROOT = path.join(UPSTREAM_DIR, "playground", "frontend", "src", "examples");
const IMPORTED_ROOT = path.join(ROOT, "examples", "upstream");
const OVERRIDE_ROOT = path.join(ROOT, "examples", "upstream_overrides");
const FIXTURES_ROOT = path.join(ROOT, "fixtures");

function fail(message, code = 1) {
  console.error(`error: ${message}`);
  process.exit(code);
}

function parseArgs(argv) {
  const args = { source: null, commit: null };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--source") {
      args.source = argv[++i];
    } else if (arg === "--commit") {
      args.commit = argv[++i];
    } else {
      fail(`unknown option: ${arg}`, 2);
    }
  }
  if (!args.source || !args.commit) {
    fail("import-upstream requires --source and --commit", 2);
  }
  return args;
}

function run(cmd, args, options = {}) {
  execFileSync(cmd, args, { stdio: "inherit", ...options });
}

function walkFiles(dir) {
  const files = [];
  if (!fs.existsSync(dir)) return files;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(full));
    } else if (entry.isFile()) {
      files.push(full);
    }
  }
  return files.sort();
}

function rel(file, base = ROOT) {
  return path.relative(base, file).replaceAll(path.sep, "/");
}

function migrateBoonSources(dir) {
  for (const file of walkFiles(dir)) {
    if (!file.endsWith(".bn")) continue;
    const original = fs.readFileSync(file, "utf8");
    const migrated = original
      .replace(/\|>\s+LINK\b/g, "|> SOURCE")
      .replace(/\bLINK\b/g, "SOURCE");
    if (migrated !== original) {
      fs.writeFileSync(file, migrated);
    }
  }
}

function hashImportedTree() {
  const hash = crypto.createHash("sha256");
  for (const file of walkFiles(IMPORTED_ROOT).concat(walkFiles(OVERRIDE_ROOT))) {
    hash.update(rel(file));
    hash.update("\0");
    hash.update(fs.readFileSync(file));
    hash.update("\0");
  }
  return hash.digest("hex");
}

function groupExamples() {
  const entries = fs.readdirSync(IMPORTED_ROOT, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name));
  const examples = [];
  const sharedRootFiles = [];
  const rootExpected = new Map();

  for (const entry of entries) {
    if (entry.isFile() && entry.name.endsWith(".expected")) {
      rootExpected.set(path.basename(entry.name, ".expected"), path.join(IMPORTED_ROOT, entry.name));
    }
  }

  for (const entry of entries) {
    const full = path.join(IMPORTED_ROOT, entry.name);
    if (entry.isDirectory()) {
      const files = walkFiles(full);
      const bnFiles = files.filter((file) => file.endsWith(".bn")).map((file) => rel(file));
      const expectedFiles = files.filter((file) => file.endsWith(".expected")).map((file) => rel(file));
      examples.push({
        name: entry.name,
        category: "upstream",
        source_path: `playground/frontend/src/examples/${entry.name}`,
        imported_path: rel(full),
        entry_file: bnFiles[0] ?? null,
        bn_files: bnFiles,
        expected_file: expectedFiles[0] ?? null,
        expected_files: expectedFiles,
        parser_status: "NOT_RUN",
        source_shape_status: "NOT_RUN",
        runtime_status: "NOT_RUN",
        terminal_status: "NOT_RUN",
        browser_status: "NOT_RUN",
        hard_gate: false,
        blockers: [],
        evidence: []
      });
    } else if (entry.isFile() && entry.name.endsWith(".bn")) {
      const base = path.basename(entry.name, ".bn");
      const expected = rootExpected.get(base);
      examples.push({
        name: `${base}_root`,
        category: "upstream_root",
        source_path: `playground/frontend/src/examples/${entry.name}`,
        imported_path: rel(full),
        entry_file: rel(full),
        bn_files: [rel(full)],
        expected_file: expected ? rel(expected) : null,
        expected_files: expected ? [rel(expected)] : [],
        parser_status: "NOT_RUN",
        source_shape_status: "NOT_RUN",
        runtime_status: "NOT_RUN",
        terminal_status: "NOT_RUN",
        browser_status: "NOT_RUN",
        hard_gate: false,
        blockers: [],
        evidence: []
      });
    } else if (entry.isFile()) {
      sharedRootFiles.push({
        path: rel(full),
        kind: path.extname(entry.name).replace(/^\./, "") || "file"
      });
    }
  }

  return { examples, sharedRootFiles };
}

function syntaxInventory() {
  const tokens = [
    "SOURCE", "LINK", "LATEST", "HOLD", "THEN", "WHEN", "WHILE", "BLOCK",
    "SKIP", "FLUSH", "PASS", "PASSED", "LIST", "MAP", "FUNCTION", "BITS",
    "MEMORY", "BYTES", "TEXT"
  ];
  const inventory = {};
  for (const token of tokens) inventory[token] = { count: 0, files: [] };

  for (const file of walkFiles(IMPORTED_ROOT).filter((file) => file.endsWith(".bn"))) {
    const text = fs.readFileSync(file, "utf8");
    for (const token of tokens) {
      const re = new RegExp(`\\b${token}\\b`, "g");
      const matches = text.match(re);
      if (matches) {
        inventory[token].count += matches.length;
        inventory[token].files.push(rel(file));
      }
    }
  }
  return inventory;
}

function writeFeatureMatrix(manifest, inventory) {
  const lines = [
    "# Boon-Pony Feature Matrix",
    "",
    "| Example | BN files | Expected | Parser | Source Shape | Runtime | Terminal |",
    "|---|---:|---|---|---|---|---|"
  ];
  for (const example of manifest.examples) {
    lines.push(`| ${example.name} | ${example.bn_files.length} | ${example.expected_file ? "yes" : "no"} | ${example.parser_status} | ${example.source_shape_status} | ${example.runtime_status} | ${example.terminal_status} |`);
  }
  lines.push("");
  lines.push("## Syntax Inventory");
  lines.push("");
  lines.push("| Token | Count | Files |");
  lines.push("|---|---:|---:|");
  for (const [token, value] of Object.entries(inventory)) {
    lines.push(`| ${token} | ${value.count} | ${value.files.length} |`);
  }
  fs.writeFileSync(path.join(FIXTURES_ROOT, "feature_matrix.md"), `${lines.join("\n")}\n`);
}

const args = parseArgs(process.argv);

fs.rmSync(UPSTREAM_DIR, { recursive: true, force: true });
fs.rmSync(IMPORTED_ROOT, { recursive: true, force: true });
fs.mkdirSync(path.dirname(UPSTREAM_DIR), { recursive: true });
fs.mkdirSync(path.dirname(IMPORTED_ROOT), { recursive: true });
fs.mkdirSync(OVERRIDE_ROOT, { recursive: true });
fs.mkdirSync(FIXTURES_ROOT, { recursive: true });

run("git", ["clone", "--filter=blob:none", args.source, UPSTREAM_DIR]);
run("git", ["checkout", args.commit], { cwd: UPSTREAM_DIR });

if (!fs.existsSync(EXAMPLE_ROOT)) {
  fail(`upstream example root not found: ${EXAMPLE_ROOT}`);
}

fs.cpSync(EXAMPLE_ROOT, IMPORTED_ROOT, { recursive: true });
migrateBoonSources(IMPORTED_ROOT);
if (fs.existsSync(OVERRIDE_ROOT)) {
  fs.cpSync(OVERRIDE_ROOT, IMPORTED_ROOT, { recursive: true, force: true });
}

const treeHash = hashImportedTree();
const { examples, sharedRootFiles } = groupExamples();
const manifest = {
  generated_by: "tools/import_upstream.mjs",
  source_repo: {
    url: args.source,
    commit: args.commit,
    example_root: "playground/frontend/src/examples",
    imported_root: "examples/upstream",
    override_root: "examples/upstream_overrides"
  },
  shared_root_files: sharedRootFiles,
  examples
};
const inventory = syntaxInventory();

fs.writeFileSync(path.join(FIXTURES_ROOT, "upstream_pin.json"), `${JSON.stringify({
  repo: args.source,
  commit: args.commit,
  source_root: "playground/frontend/src/examples",
  imported_root: "examples/upstream",
  override_root: "examples/upstream_overrides",
  tree_hash: treeHash,
  tree_hash_command: "node tools/import_upstream.mjs internal tree hash over examples/upstream and examples/upstream_overrides"
}, null, 2)}\n`);
fs.writeFileSync(path.join(FIXTURES_ROOT, "corpus_manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
fs.writeFileSync(path.join(FIXTURES_ROOT, "syntax_inventory.json"), `${JSON.stringify(inventory, null, 2)}\n`);
writeFeatureMatrix(manifest, inventory);

console.log(`imported ${examples.length} upstream example groups`);
console.log(`shared root files: ${sharedRootFiles.length}`);
console.log(`tree hash: ${treeHash}`);
