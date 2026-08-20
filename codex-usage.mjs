#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const codexCommand = process.env.CODEX_BIN || "codex";
const server = spawn(codexCommand, ["app-server", "--stdio"], {
  stdio: ["pipe", "pipe", "pipe"],
});

let stderr = "";
let finished = false;
const timeout = setTimeout(() => fail("Timed out while reading Codex usage."), 15_000);

server.stderr.setEncoding("utf8");
server.stderr.on("data", (chunk) => {
  stderr += chunk;
});

server.on("error", (error) => {
  fail(
    error.code === "ENOENT"
      ? `Could not find '${codexCommand}'. Set CODEX_BIN to the Codex executable path.`
      : error.message,
  );
});

server.on("exit", (code) => {
  if (!finished && code !== 0) {
    fail(stderr.trim() || `Codex app server exited with status ${code}.`);
  }
});

const lines = createInterface({ input: server.stdout });

lines.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message.id === 1 && message.result) {
    send({ method: "initialized" });
    send({ id: 2, method: "account/rateLimits/read" });
    return;
  }

  if (message.id === 2) {
    if (message.error) {
      fail(message.error.message || JSON.stringify(message.error));
      return;
    }

    const result = formatUsage(message.result);
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    finish(0);
  }
});

send({
  id: 1,
  method: "initialize",
  params: {
    clientInfo: {
      name: "billing-monitor",
      title: "Billing Monitor",
      version: "1.0.0",
    },
    capabilities: {
      experimentalApi: true,
      requestAttestation: false,
    },
  },
});

function send(message) {
  server.stdin.write(`${JSON.stringify(message)}\n`);
}

function formatUsage(response = {}) {
  const snapshots = response.rateLimitsByLimitId
    ? Object.entries(response.rateLimitsByLimitId)
    : [[response.rateLimits?.limitId || "codex", response.rateLimits]];

  return {
    checkedAt: new Date().toISOString(),
    limits: snapshots
      .filter(([, snapshot]) => snapshot)
      .map(([id, snapshot]) => ({
        id,
        name: snapshot.limitName,
        planType: snapshot.planType,
        primary: formatWindow(snapshot.primary),
        secondary: formatWindow(snapshot.secondary),
      })),
  };
}

function formatWindow(window) {
  if (!window) return null;

  const resetDate =
    typeof window.resetsAt === "number"
      ? new Date(window.resetsAt * 1000)
      : null;

  return {
    usedPercent: window.usedPercent,
    remainingPercent: Math.max(0, 100 - window.usedPercent),
    windowMinutes: window.windowDurationMins,
    windowDuration: formatMinutes(window.windowDurationMins),
    resetsAt: resetDate?.toISOString() ?? null,
    resetsAtLocal: resetDate
      ? new Intl.DateTimeFormat(undefined, {
          dateStyle: "medium",
          timeStyle: "long",
        }).format(resetDate)
      : null,
    resetsIn: resetDate
      ? formatMinutes(Math.max(0, Math.ceil((resetDate - Date.now()) / 60_000)))
      : null,
  };
}

function formatMinutes(totalMinutes) {
  if (typeof totalMinutes !== "number") return null;

  const days = Math.floor(totalMinutes / 1_440);
  const hours = Math.floor((totalMinutes % 1_440) / 60);
  const minutes = totalMinutes % 60;
  const parts = [];

  if (days) parts.push(`${days} ${days === 1 ? "day" : "days"}`);
  if (hours) parts.push(`${hours} ${hours === 1 ? "hour" : "hours"}`);
  if (minutes || parts.length === 0) {
    parts.push(`${minutes} ${minutes === 1 ? "minute" : "minutes"}`);
  }

  return parts.join(", ");
}

function fail(message) {
  if (finished) return;
  process.stderr.write(`Error: ${message}\n`);
  finish(1);
}

function finish(code) {
  if (finished) return;
  finished = true;
  clearTimeout(timeout);
  lines.close();
  server.kill();
  process.exitCode = code;
}
