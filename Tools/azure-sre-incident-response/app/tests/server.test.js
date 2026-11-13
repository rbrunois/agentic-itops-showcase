const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const { once } = require("node:events");
const path = require("node:path");
const { test, before, after } = require("node:test");
const { createApp, parsePort } = require("../server");

let server;
let baseUrl;
before(async () => {
  server = createApp().listen(0, "127.0.0.1");
  await once(server, "listening");
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  await new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
    server.closeAllConnections();
  });
});

test("root preserves the v1.2.0 response", async () => {
  const response = await fetch(baseUrl);
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "sre-demo-app v1.2.0 - hello from Container Apps");
});

test("health probe preserves status and version", async () => {
  const response = await fetch(`${baseUrl}/healthz`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /application\/json/);
  assert.deepEqual(await response.json(), { status: "ok", version: "1.2.0" });
});

test("readiness probe preserves its response", async () => {
  const response = await fetch(`${baseUrl}/readyz`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ready: true });
});

test("unknown endpoints return 404", async () => {
  assert.equal((await fetch(`${baseUrl}/not-found`)).status, 404);
});

test("port defaults to 8080 and supports explicit TCP ports", () => {
  assert.equal(parsePort(), 8080);
  assert.equal(parsePort("9090"), 9090);
  assert.equal(parsePort("0"), 0);
  for (const invalid of ["", "-1", "65536", "8.5", "pipe", "Infinity"]) {
    assert.throws(() => parsePort(invalid), /PORT must be an integer/);
  }
});

test("entrypoint honors PORT=0 and runs without telemetry credentials", { timeout: 15000 }, async (t) => {
  const env = { ...process.env, PORT: "0" };
  delete env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  delete env.APPINSIGHTS_INSTRUMENTATIONKEY;
  const child = spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) {
      const closed = once(child, "close");
      child.kill();
      await closed;
    }
  });
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const port = await new Promise((resolve, reject) => {
    let stdout = "";
    child.on("error", reject);
    child.on("exit", (code) => reject(new Error(`Server exited (${code}): ${stderr}`)));
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      const match = stdout.match(/listening on :(\d+)/);
      if (match) resolve(Number(match[1]));
    });
  });
  assert.ok(port > 0);
  const response = await fetch(`http://127.0.0.1:${port}/healthz`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok", version: "1.2.0" });
  assert.equal(stderr, "");
});
