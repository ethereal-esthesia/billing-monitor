#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later

const sessionToken = process.env.WINDSURF_SESSION_TOKEN;
const auth1Token = process.env.WINDSURF_AUTH1_TOKEN;
const accountId = process.env.WINDSURF_ACCOUNT_ID;
const primaryOrgId = process.env.WINDSURF_PRIMARY_ORG_ID;

if (!sessionToken) fail("WINDSURF_SESSION_TOKEN is not set.");
if (!auth1Token) fail("WINDSURF_AUTH1_TOKEN is not set.");
if (!accountId) fail("WINDSURF_ACCOUNT_ID is not set.");
if (!primaryOrgId) fail("WINDSURF_PRIMARY_ORG_ID is not set.");

const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 15_000);

(async () => {
  try {
    // Try using the GetPlanStatus API endpoint as documented
    // This uses ConnectRPC over protobuf, but we'll try a simpler approach first
    const response = await fetch("https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-auth-token": sessionToken,
        "x-devin-session-token": sessionToken,
        "x-devin-auth1-token": auth1Token,
        "x-devin-account-id": accountId,
        "x-devin-primary-org-id": primaryOrgId,
        "Origin": "https://windsurf.com",
        "Referer": "https://windsurf.com/",
      },
      body: JSON.stringify({
        auth_token: sessionToken,
        include_top_up_status: true
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      fail(`Windsurf API request failed (${response.status}).`);
    }

    const data = await response.json();
    
    // Extract the relevant usage data from the response
    const planStatus = data.planStatus || {};
    const planInfo = planStatus.planInfo || {};
    
    const weeklyRemaining = planStatus.weeklyQuotaRemainingPercent || null;
    const dailyRemaining = null; // Daily quota not in this response when exhausted
    const overageBalanceMicros = planStatus.overageBalanceMicros || "0";
    const extraBalance = parseFloat(overageBalanceMicros) / 1000000; // Convert micros to dollars
    
    const dailyResetAt = planStatus.dailyQuotaResetAtUnix || null;
    const weeklyResetAt = planStatus.weeklyQuotaResetAtUnix || null;
    const planName = planInfo.planName || null;
    
    const availablePromptCredits = planStatus.availablePromptCredits || null;
    const availableFlowCredits = planStatus.availableFlowCredits || null;

    if (!weeklyRemaining && !extraBalance) {
      fail("Could not extract usage data from Windsurf API response.");
    }

    process.stdout.write(`${JSON.stringify({
      checkedAt: new Date().toISOString(),
      dailyRemaining,
      weeklyRemaining,
      extraBalance,
      dailyResetAt: dailyResetAt ? new Date(dailyResetAt * 1000).toISOString() : null,
      weeklyResetAt: weeklyResetAt ? new Date(weeklyResetAt * 1000).toISOString() : null,
      planName,
      availablePromptCredits,
      availableFlowCredits,
      source: "windsurf-api",
    }, null, 2)}\n`);
  } catch (error) {
    fail(error.name === "AbortError" ? "Timed out while reading Windsurf usage." : error.message);
  } finally {
    clearTimeout(timeout);
  }
})();

function fail(message) {
  process.stderr.write(`Error: ${message}\n`);
  process.exit(1);
}