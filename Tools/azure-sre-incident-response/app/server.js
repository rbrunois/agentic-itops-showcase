function configureTelemetry(connectionString) {
  if (connectionString) {
    // Initialize instrumentation before loading Express.
    require("applicationinsights").setup(connectionString).start();
  }
}

function parsePort(value = "8080") {
  if (!/^\d+$/.test(String(value))) {
    throw new Error("PORT must be an integer between 0 and 65535");
  }
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error("PORT must be an integer between 0 and 65535");
  }
  return port;
}

function createApp() {
  const express = require("express");
  const app = express();

  app.get("/", (_req, res) => {
    res.send("sre-demo-app v1.2.0 - hello from Container Apps");
  });
  app.get("/healthz", (_req, res) => {
    res.status(200).json({ status: "ok", version: "1.2.0" });
  });
  app.get("/readyz", (_req, res) => {
    res.status(200).json({ ready: true });
  });
  return app;
}

function startServer() {
  const port = parsePort(process.env.PORT);
  configureTelemetry(process.env.APPLICATIONINSIGHTS_CONNECTION_STRING);
  const server = createApp().listen(port, "0.0.0.0", () => {
    console.log(`sre-demo-app listening on :${server.address().port}`);
  });
  return server;
}

if (require.main === module) {
  const server = startServer();
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.once(signal, () => {
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(1), 10000).unref();
    });
  }
}

module.exports = { createApp, parsePort, startServer };
