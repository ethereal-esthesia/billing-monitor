#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

const token = process.env.DEEPINFRA_TOKEN;
if (!token) fail("DEEPINFRA_TOKEN is not set.");

const configuredBase = process.env.DEEPINFRA_BASE_URL || "https://api.deepinfra.com";
let origin;
try {
  origin = new URL(configuredBase).origin;
} catch {
  fail("DEEPINFRA_BASE_URL is not a valid URL.");
}

const now = new Date();
const from = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
const headers = { Authorization: `Bearer ${token}` };
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 15_000);

try {
  const usageURL = new URL("/payment/usage", origin);
  usageURL.searchParams.set("from", String(Math.floor(from.getTime() / 1000)));
  usageURL.searchParams.set("to", String(Math.floor(now.getTime() / 1000)));

  const [usageResponse, configResponse] = await Promise.all([
    fetch(usageURL, { headers, signal: controller.signal }),
    fetch(new URL("/payment/config", origin), { headers, signal: controller.signal }),
  ]);

  if (!usageResponse.ok) {
    fail(`DeepInfra usage request failed (${usageResponse.status}).`);
  }
  if (!configResponse.ok) {
    fail(`DeepInfra limit request failed (${configResponse.status}).`);
  }

  const usage = await usageResponse.json();
  const config = await configResponse.json();
  // DeepInfra reports usage costs in cents, while the configured limit is USD.
  const spentCents = (usage.months || []).reduce(
    (total, month) => total + Number(month.total_cost || 0),
    0,
  );
  const spent = spentCents / 100;
  const limit = Number(config.limit);

  if (!Number.isFinite(limit) || limit <= 0) {
    fail("DeepInfra does not have a monthly spending limit configured.");
  }

  process.stdout.write(`${JSON.stringify({
    checkedAt: now.toISOString(),
    periodStart: from.toISOString(),
    periodEnd: now.toISOString(),
    spent,
    limit,
    remaining: Math.max(0, limit - spent),
  }, null, 2)}\n`);
} catch (error) {
  fail(error.name === "AbortError" ? "Timed out while reading DeepInfra billing." : error.message);
} finally {
  clearTimeout(timeout);
}

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}
