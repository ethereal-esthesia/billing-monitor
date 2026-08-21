#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

const token = process.env.DEEPSEEK_API_KEY;
if (!token) fail("DEEPSEEK_API_KEY is not set.");

const configuredBase = process.env.DEEPSEEK_BASE_URL || "https://api.deepseek.com";
let origin;
try {
  origin = new URL(configuredBase).origin;
} catch {
  fail("DEEPSEEK_BASE_URL is not a valid URL.");
}

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 15_000);

try {
  const response = await fetch(new URL("/user/balance", origin), {
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
    signal: controller.signal,
  });

  if (!response.ok) {
    fail(`DeepSeek balance request failed (${response.status}).`);
  }

  const data = await response.json();
  const balances = Array.isArray(data.balance_infos) ? data.balance_infos : [];
  const selected = balances.find((entry) => entry.currency === "USD") || balances[0];
  const balance = Number(selected?.total_balance);

  if (!selected || !Number.isFinite(balance) || balance < 0) {
    fail("DeepSeek returned an invalid account balance.");
  }

  process.stdout.write(`${JSON.stringify({
    checkedAt: new Date().toISOString(),
    available: Boolean(data.is_available),
    currency: selected.currency,
    balance,
    grantedBalance: Number(selected.granted_balance || 0),
    toppedUpBalance: Number(selected.topped_up_balance || 0),
  }, null, 2)}\n`);
} catch (error) {
  fail(error.name === "AbortError" ? "Timed out while reading DeepSeek balance." : error.message);
} finally {
  clearTimeout(timeout);
}

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}
