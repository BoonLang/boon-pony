import http from "node:http";
import { createReadStream } from "node:fs";
import { writeFile } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";

const root = resolve(process.argv[2] ?? "build/browser");
const requestedPort = Number(process.argv[3] ?? process.env.PORT ?? 4177);
const host = "127.0.0.1";
const statusPath = resolve(process.argv[4] ?? "build/browser/server.json");

const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".json": "application/json; charset=utf-8",
};

function localPath(urlPath) {
  const decoded = decodeURIComponent(urlPath.split("?")[0]);
  const relative = decoded === "/" ? "index.html" : decoded.replace(/^\/+/, "");
  const path = normalize(join(root, relative));
  if (!path.startsWith(root + sep) && path !== root) throw new Error("bad path");
  return path;
}

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

server.listen(requestedPort, host, async () => {
  const { port } = server.address();
  const status = {
    status: "running",
    url: `http://${host}:${port}/index.html`,
    root,
    coop: "same-origin",
    coep: "require-corp",
  };
  await writeFile(statusPath, JSON.stringify(status, null, 2) + "\n");
  console.log(status.url);
});
