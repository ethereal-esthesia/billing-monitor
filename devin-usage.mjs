#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

const token = process.env.DEVIN_API_KEY;
if (!token) fail("DEVIN_API_KEY is not set.");

const configuredBase = process.env.DEVIN_BASE_URL || "https://api.devin.ai";
let origin;
try {
  origin = new URL(configuredBase).origin;
} catch {
  fail("DEVIN_BASE_URL is not a valid URL.");
}

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 15_000);

try {
  const response = await fetch(new URL("/billing/usage", origin), {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
    signal: controller.signal,
  });

  if (!response.ok) {
    fail(`Devin usage request failed (${response.status}).`);
  }

  const data = await response.json();
  const balance = Number(data.balance || data.remaining_balance || 0);
  const limit = Number(data.limit || data.total_limit || 0);
  const used = Number(data.used || data.spent || 0);

  if (!Number.isFinite(balance) || balance < 0) {
    fail("Devin returned an invalid account balance.");
  }

  process.stdout.write(`${JSON.stringify({
    checkedAt: new Date().toISOString(),
    balance,
    limit: Number.isFinite(limit) && limit > 0 ? limit : null,
    used: Number.isFinite(used) && used > 0 ? used : null,
    currency: "USD",
  }, null, 2)}\n`);
} catch (error) {
  fail(error.name === "AbortError" ? "Timed out while reading Devin usage." : error.message);
} finally {
  clearTimeout(timeout);
}

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}
