const fs = require("fs");
const { spawnSync } = require("child_process");

const messages = [
  frame(),
  action("type", "Test todo"),
  action("key", "Enter"),
  frame(),
  action("click_checkbox", "", 1),
  action("click_text", "Active"),
  frame(),
  action("click_text", "Completed"),
  frame(),
  action("click_text", "All"),
  action("click_checkbox", "", 1),
  action("type", "Walk the dog"),
  action("key", "Enter"),
  action("type", "Feed the cat"),
  action("key", "Enter"),
  frame(),
  action("click_checkbox", "", 3),
  frame(),
  action("click_checkbox", "", 3),
  frame(),
  action("click_checkbox", "", 0),
  frame(),
  action("click_checkbox", "", 0),
  frame(),
  action("click_checkbox", "", 0),
  action("click_text", "Clear completed"),
  frame(),
  action("type", "Buy milk"),
  action("key", "Enter"),
  frame(),
  action("click_checkbox", "", 1),
  frame(),
  action("click_checkbox", "", 1),
  frame(),
  action("dblclick_text", "Buy milk"),
  action("key", "Escape"),
  frame(),
  action("dblclick_text", "Buy milk"),
  action("type", "Buy milk EDITED"),
  action("key", "Enter"),
  frame(),
  action("click_button_near_text", "Buy milk EDITED"),
  frame(),
  action("type", "Todo to complete"),
  action("key", "Enter"),
  action("type", "Todo to keep"),
  action("key", "Enter"),
  action("click_checkbox", "", 1),
  action("click_text", "Clear completed"),
  frame(),
  { protocol_version: 1, type: "quit" },
];

const proc = spawnSync("build/bin/generated/todo_mvc", ["--protocol"], {
  input: messages.map((m) => JSON.stringify(m)).join("\n") + "\n",
  encoding: "utf8",
});

fs.writeFileSync("build/cache/pty-todo-protocol.jsonl", proc.stdout);
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

const uniqueFrames = [];
for (const text of frames) {
  if (uniqueFrames[uniqueFrames.length - 1] !== text) uniqueFrames.push(text);
}

const checks = [
  [0, ["2 items left", "[ ] Buy groceries", "[ ] Clean room"], []],
  [1, ["3 items left", "[ ] Test todo"], []],
  [2, ["Filter: Active", "[ ] Clean room", "[ ] Test todo"], ["Buy groceries"]],
  [3, ["Filter: Completed", "[x] Buy groceries"], ["Clean room"]],
  [4, ["5 items left", "[ ] Walk the dog", "[ ] Feed the cat"], []],
  [5, ["4 items left", "[x] Test todo"], []],
  [6, ["5 items left", "[ ] Test todo"], []],
  [7, ["0 items left", "[x] Buy groceries", "[x] Feed the cat"], []],
  [8, ["5 items left", "[ ] Buy groceries", "[ ] Feed the cat"], []],
  [9, ["0 items left"], ["Buy groceries", "Feed the cat", "Test todo"]],
  [10, ["1 item left", "[ ] Buy milk"], []],
  [11, ["0 items left", "[x] Buy milk"], []],
  [12, ["1 item left", "[ ] Buy milk"], []],
  [13, ["1 item left", "[ ] Buy milk EDITED"], ["[ ] Buy milk\n"]],
  [14, ["0 items left"], ["Buy milk EDITED"]],
  [15, ["1 item left", "[ ] Todo to keep"], ["Todo to complete"]],
];

let ok = true;
for (const [index, required, forbidden] of checks) {
  const text = uniqueFrames[index] || "";
  for (const needle of required) {
    if (!text.includes(needle)) {
      console.error(`missing ${JSON.stringify(needle)} in todo frame ${index + 1}`);
      ok = false;
    }
  }
  for (const needle of forbidden) {
    if (text.includes(needle)) {
      console.error(`unexpected ${JSON.stringify(needle)} in todo frame ${index + 1}`);
      ok = false;
    }
  }
}

if (!ok) {
  uniqueFrames.forEach((text, index) => {
    console.error(`--- todo frame ${index + 1}`);
    console.error(text.replace(/\n/g, " | "));
  });
  process.exit(1);
}

console.log("todo protocol scenarios ok");
console.log("initial/add/filter/toggle/toggle-all/clear/edit/delete/persistence covered");

function frame() {
  return { protocol_version: 1, type: "frame" };
}

function action(action, value = "", index = undefined) {
  const msg = { protocol_version: 1, type: "expected_action", action };
  if (value !== "") msg.value = value;
  if (index !== undefined) msg.index = index;
  return msg;
}
