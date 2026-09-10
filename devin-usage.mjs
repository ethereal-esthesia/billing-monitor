#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

const token = process.env.DEVIN_PAT || process.env.DEVIN_API_KEY;
if (!token) fail("DEVIN_PAT or DEVIN_API_KEY is not set.");

const orgId = process.env.DEVIN_ORG_ID;
if (!orgId) fail("DEVIN_ORG_ID is not set. Find it on Settings → Service Users page.");

const configuredBase = process.env.DEVIN_BASE_URL || "https://api.devin.ai";
let origin;
try {
  origin = new URL(configuredBase).origin;
} catch {
  fail("DEVIN_BASE_URL is not a valid URL.");
}

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 15_000);

(async () => {
  try {
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const timeAfter = Math.floor(thirtyDaysAgo.getTime() / 1000);
    const timeBefore = Math.floor(now.getTime() / 1000);

    const response = await fetch(new URL(`/v3/organizations/${orgId}/consumption/daily?time_after=${timeAfter}&time_before=${timeBefore}`, origin), {
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
    const totalAcus = Number(data.total_acus || 0);
    const dailyData = data.acus_by_date || [];

    if (!Number.isFinite(totalAcus) || totalAcus < 0) {
      fail("Devin returned an invalid ACU consumption data.");
    }

    process.stdout.write(`${JSON.stringify({
      checkedAt: new Date().toISOString(),
      totalAcus,
      dailyData,
      periodStart: thirtyDaysAgo.toISOString(),
      periodEnd: now.toISOString(),
    }, null, 2)}\n`);
  } catch (error) {
    fail(error.name === "AbortError" ? "Timed out while reading Devin usage." : error.message);
  } finally {
    clearTimeout(timeout);
  }
})();

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}
