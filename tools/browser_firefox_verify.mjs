import http from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { extname, join, normalize, resolve, sep } from "node:path";
import { spawn } from "node:child_process";

const root = resolve(process.argv[2] ?? "build/browser");
const out = resolve(process.argv[3] ?? "build/browser/firefox-proof.json");

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".json": "application/json; charset=utf-8",
};

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function localPath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split("?")[0]);
  const relative = decoded === "/" ? "index.html" : decoded.replace(/^\/+/, "");
  const path = normalize(join(root, relative));
  if (!path.startsWith(root + sep) && path !== root) throw new Error("bad path");
  return path;
}

async function freePort() {
  const server = http.createServer();
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  await new Promise(resolve => server.close(resolve));
  return port;
}

async function requestJson(port, method, path, body) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`, {
    method,
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let parsed = {};
  try { parsed = text ? JSON.parse(text) : {}; } catch (_) {}
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: ${response.status} ${text}`);
  }
  return parsed;
}

async function main() {
  const httpPort = await freePort();
  const driverPort = await freePort();

  const server = http.createServer((req, res) => {
    let path;
    try {
      path = localPath(req.url ?? "/");
    } catch (error) {
      res.writeHead(400);
      res.end(String(error));
      return;
    }
    res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
    res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
    res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    res.setHeader("content-type", mime[extname(path)] ?? "application/octet-stream");
    createReadStream(path)
      .on("error", () => {
        res.writeHead(404);
        res.end("missing");
      })
      .pipe(res);
  });

  await new Promise(resolve => server.listen(httpPort, "127.0.0.1", resolve));

  const driver = spawn("geckodriver", ["--port", String(driverPort), "--host", "127.0.0.1"], {
    stdio: ["ignore", "ignore", "pipe"],
  });
  let driverLog = "";
  driver.stderr.on("data", chunk => { driverLog += chunk.toString(); });

  let sessionId;
  try {
    for (let i = 0; i < 50; i++) {
      try {
        const status = await fetch(`http://127.0.0.1:${driverPort}/status`);
        if (status.ok) break;
      } catch (_) {}
      await sleep(100);
    }

    const session = await requestJson(driverPort, "POST", "/session", {
      capabilities: {
        alwaysMatch: {
          browserName: "firefox",
          "moz:firefoxOptions": { args: ["-headless"] },
        },
      },
    });
    sessionId = session.value.sessionId;

    await requestJson(driverPort, "POST", `/session/${sessionId}/url`, {
      url: `http://127.0.0.1:${httpPort}/index.html`,
    });

    let proof = null;
    for (let i = 0; i < 100; i++) {
      const result = await requestJson(driverPort, "POST", `/session/${sessionId}/execute/sync`, {
        script: `
          const canvas = document.querySelector("#canvas");
          const ctx = canvas && canvas.getContext("2d");
          let canvas_nonblank = false;
          if (ctx) {
            const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
            for (let i = 0; i < data.length; i += 4) {
              if (data[i] || data[i + 1] || data[i + 2] || data[i + 3]) {
                canvas_nonblank = true;
                break;
              }
            }
          }
          const pageProof = window.__boonBrowserProof || null;
          if (!pageProof) return null;
          return {
            ...pageProof,
            status_text: document.querySelector("#status")?.textContent || "",
            runtime_text: document.querySelector("#runtime")?.textContent || "",
            cross_origin_isolated: window.crossOriginIsolated === true,
            shared_array_buffer: typeof SharedArrayBuffer !== "undefined",
            canvas_nonblank,
            semantic_ids_present: document.querySelectorAll("[data-semantic-id]").length > 0,
            hit_regions_present: document.querySelectorAll("[data-hit-region]").length > 0
          };
        `,
        args: [],
      });
      proof = result.value;
      if (proof && (proof.status === "pass" || proof.status === "fail")) break;
      await sleep(100);
    }

    if (!proof) throw new Error("Firefox page did not publish a browser proof");

    await requestJson(driverPort, "POST", `/session/${sessionId}/execute/sync`, {
      script: `document.querySelector("#run").click(); return true;`,
      args: [],
    });

    let inputRoundtrip = false;
    for (let i = 0; i < 50; i++) {
      const result = await requestJson(driverPort, "POST", `/session/${sessionId}/execute/sync`, {
        script: `
          const proof = window.__boonBrowserProof || {};
          const source = document.querySelector("#source")?.textContent || "";
          return Boolean(proof.scene?.source?.includes("Counter state: 1") || source.includes("Counter state: 1"));
        `,
        args: [],
      });
      inputRoundtrip = result.value === true;
      if (inputRoundtrip) break;
      await sleep(100);
    }
    proof.input_roundtrip = inputRoundtrip;

    const failures = [];
    if (proof.status !== "pass") failures.push("page proof status is not pass");
    if (!proof.pony_wasm_loaded) failures.push("Pony wasm was not loaded");
    if (!proof.cross_origin_isolated) failures.push("cross-origin isolation is false");
    if (!proof.shared_array_buffer) failures.push("SharedArrayBuffer is unavailable");
    if (proof.native_runtime_used) failures.push("native runtime fallback was used");
    if (proof.javascript_runtime_used) failures.push("JavaScript runtime fallback was used");
    if (!proof.canvas_nonblank) failures.push("canvas is blank");
    if (!proof.semantic_ids_present) failures.push("semantic IDs are missing");
    if (!proof.hit_regions_present) failures.push("hit regions are missing");
    if (!proof.input_roundtrip) failures.push("browser input did not update Pony wasm state");

    const report = {
      command: "browser-firefox-proof",
      status: failures.length === 0 ? "pass" : "fail",
      browser: "firefox",
      renderer: "canvas2d",
      url: `http://127.0.0.1:${httpPort}/index.html`,
      ...proof,
      page_proof: proof,
      failures,
    };
    await writeFile(out, JSON.stringify(report, null, 2) + "\n");
    if (failures.length !== 0) process.exitCode = 1;
  } catch (error) {
    await writeFile(out, JSON.stringify({
      command: "browser-firefox-proof",
      status: "fail",
      browser: "firefox",
      renderer: "canvas2d",
      pony_wasm_loaded: false,
      native_runtime_used: false,
      javascript_runtime_used: false,
      failures: [String(error && error.stack || error), driverLog],
    }, null, 2) + "\n");
    process.exitCode = 1;
  } finally {
    if (sessionId) {
      try { await requestJson(driverPort, "DELETE", `/session/${sessionId}`); } catch (_) {}
    }
    driver.kill("SIGTERM");
    await new Promise(resolve => server.close(resolve));
  }
}

await main();
