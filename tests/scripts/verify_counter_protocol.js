const fs = require("fs");
const { spawnSync } = require("child_process");

const apps = ["counter", "counter_hold"];
const previews = new Map();

for (const app of apps) {
  const messages = [
    { protocol_version: 1, type: "frame" },
    { protocol_version: 1, type: "expected_action", action: "click_button", index: 0 },
    { protocol_version: 1, type: "frame" },
    { protocol_version: 1, type: "quit" },
  ];
  const proc = spawnSync(`build/bin/generated/${app}`, ["--protocol"], {
    input: messages.map((m) => JSON.stringify(m)).join("\n") + "\n",
    encoding: "utf8",
  });
  fs.writeFileSync(`build/cache/pty-${app}-parity.jsonl`, proc.stdout);
  if (proc.status !== 0) {
    process.stderr.write(proc.stderr);
    process.exit(proc.status ?? 1);
  }
  const frames = proc.stdout
    .trim()
    .split(/\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line))
    .filter((msg) => msg.type === "frame")
    .map((msg) => (msg.runs || []).map((run) => run.text).join("\n"));
  const unique = [];
  for (const text of frames) {
    if (unique[unique.length - 1] !== text) unique.push(text);
  }
  previews.set(app, unique);
}

const counter = previews.get("counter");
const hold = previews.get("counter_hold");
if (!counter || !hold || counter[0] !== "0+" || hold[0] !== "0+" || counter[1] !== "1+" || hold[1] !== "1+") {
  console.error("counter preview parity failed");
  console.error({ counter, counter_hold: hold });
  process.exit(1);
}

console.log("counter preview parity ok");
console.log("counter initial=0+ click=1+");
console.log("counter_hold initial=0+ click=1+");
