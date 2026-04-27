#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const requiredFiles = [
  "fixtures/upstream_pin.json",
  "fixtures/corpus_manifest.json",
  "fixtures/syntax_inventory.json",
  "fixtures/feature_matrix.md",
  "fixtures/spec_gaps.md"
];

function fail(message) {
  console.error(`error: ${message}`);
  process.exitCode = 1;
}

for (const file of requiredFiles) {
  if (!fs.existsSync(file)) {
    fail(`missing ${file}`);
  }
}

let manifest = null;
if (fs.existsSync("fixtures/corpus_manifest.json")) {
  manifest = JSON.parse(fs.readFileSync("fixtures/corpus_manifest.json", "utf8"));
  if (!Array.isArray(manifest.examples) || manifest.examples.length === 0) {
    fail("corpus manifest has no examples");
  }
  const manifestBnFiles = new Set();
  for (const example of manifest.examples ?? []) {
    for (const bnFile of example.bn_files ?? []) {
      if (!fs.existsSync(bnFile)) fail(`manifest references missing source ${bnFile}`);
      manifestBnFiles.add(bnFile);
    }
    for (const expectedFile of example.expected_files ?? []) {
      if (!fs.existsSync(expectedFile)) fail(`manifest references missing expected file ${expectedFile}`);
    }
  }
  const actualBnFiles = [];
  function collectBn(dir) {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) collectBn(full);
      else if (entry.isFile() && full.endsWith(".bn")) actualBnFiles.push(full.replaceAll(path.sep, "/"));
    }
  }
  collectBn("examples/upstream");
  for (const bnFile of actualBnFiles) {
    if (!manifestBnFiles.has(bnFile)) fail(`manifest omits runnable source ${bnFile}`);
  }
}

const forbidden = [];
function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.isFile() && full.endsWith(".bn")) {
      const text = fs.readFileSync(full, "utf8");
      if (/\bLINK\b|\|>\s+LINK\b/.test(text)) forbidden.push(full);
    }
  }
}
walk("examples");
for (const file of forbidden) {
  fail(`forbidden legacy LINK spelling in runnable source: ${file}`);
}

if (process.exitCode) {
  process.exit();
}

console.log(`manifest ok: ${manifest?.examples?.length ?? 0} examples`);
