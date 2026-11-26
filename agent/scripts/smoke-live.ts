/**
 * Read-only smoke test against live DhanHQ data. Run it before any live session to check
 * the assumptions the README lists as "verification required": scrip-master resolution,
 * expiry list, option-chain fields, warmup bar timestamps and funds. This script imports no
 * order code and places no orders. MODE is forced to paper, so the live acknowledgement
 * does not apply.
 *
 * With DHAN_PIN and DHAN_TOTP_SECRET set, the first step is a PIN+TOTP login, which is also
 * the auth check. The access token is never printed.
 *
 *   npm run smoke:live
 */
import 'dotenv/config';
import { createDhanClient } from '../src/dhan/client.js';
import { InstrumentMaster } from '../src/dhan/instrumentMaster.js';
import { DhanMarketData } from '../src/dhan/marketData.js';
import { loadConfig } from '../src/config.js';
import { createConsoleLogger } from '../src/ops/logger.js';
import { assertWarmupClock } from '../src/runtime/clockGuard.js';
import { pickExpiry } from '../src/options/selector.js';
import { formatMinuteOfDay, istParts, shiftDateKey } from '../src/time/ist.js';

interface Check {
  readonly name: string;
  readonly ok: boolean;
  readonly detail: string;
}

async function check(name: string, run: () => Promise<string>): Promise<Check> {
  try {
    return { name, ok: true, detail: await run() };
  } catch (error) {
    return { name, ok: false, detail: error instanceof Error ? error.message : String(error) };
  }
}

async function main(): Promise<void> {
  const config = loadConfig({ ...process.env, MODE: 'paper' });
  const client = await createDhanClient(config.dhan, { logger: createConsoleLogger() });
  const nowMs = Date.now();
  const today = istParts(nowMs).date;
  const master = new InstrumentMaster(client.instruments, () => today);
  const market = new DhanMarketData(client, { istShiftedTimestamps: config.feed.istShiftedTimestamps });
  const checks: Check[] = [];

  for (const underlying of config.underlyings) {
    const label = underlying.symbol;
    const spotCheck = await check(`${label}: spot instrument`, async () => {
      const spot = await master.resolveSpot(label);
      return `${spot.exchangeSegment} security id ${spot.securityId}`;
    });
    checks.push(spotCheck);
    if (!spotCheck.ok) {
      continue;
    }
    const spot = await master.resolveSpot(label);

    checks.push(
      await check(`${label}: option contracts`, async () => {
        const contracts = await master.optionContracts(label, underlying.optionSegment);
        const sample = contracts[0];
        const lots = [...new Set(contracts.map((contract) => contract.lotSize))].sort((a, b) => a - b);
        const ticks = [...new Set(contracts.map((contract) => contract.tickSize))].sort((a, b) => a - b);
        return `${contracts.length} contracts; lot sizes ${lots.join(',')}; tick sizes ${ticks.join(',')}; sample ${sample?.symbol} expiring ${sample?.expiry}`;
      }),
    );

    let expiry: string | undefined;
    checks.push(
      await check(`${label}: expiry list`, async () => {
        const expiries = await market.listExpiries(spot);
        expiry = pickExpiry(expiries, today, config.contract.minDaysToExpiry);
        if (expiry === undefined) {
          throw new Error(`no expiry at least ${config.contract.minDaysToExpiry} day(s) out in ${expiries.slice(0, 5).join(', ')}`);
        }
        return `${expiries.length} expiries; selected ${expiry}`;
      }),
    );

    if (expiry !== undefined) {
      const chosen = expiry;
      checks.push(
        await check(`${label}: option chain fields`, async () => {
          const chain = await market.optionChain(spot, chosen);
          const strikes = chain.strikes;
          const withCall = strikes.filter((row) => row.call !== undefined);
          const missing = (pick: (leg: NonNullable<(typeof strikes)[number]['call']>) => unknown) =>
            withCall.filter((row) => row.call !== undefined && pick(row.call) === undefined).length;
          if (withCall.length === 0) {
            throw new Error('chain has no call legs');
          }
          return `${strikes.length} strikes; legs missing ltp ${missing((leg) => leg.ltp)}, bid ${missing((leg) => leg.bid)}, ask ${missing((leg) => leg.ask)}, oi ${missing((leg) => leg.oi)}, volume ${missing((leg) => leg.volume)}, securityId ${missing((leg) => leg.securityId)} (of ${withCall.length} call legs)`;
        }),
      );
    }

    checks.push(
      await check(`${label}: warmup bars and clock`, async () => {
        const from = shiftDateKey(today, -(config.strategy.warmupDays * 2 + 2));
        const bars = await market.intradayCandles(spot, config.strategy.barMinutes, from, today);
        const newest = bars[bars.length - 1];
        assertWarmupClock(newest, nowMs, config.strategy.barMinutes);
        if (newest === undefined) {
          return 'no bars returned (holiday or market not yet open?)';
        }
        const parts = istParts(newest.time);
        return `${bars.length} bars from ${from}; newest bar opens ${parts.date} ${formatMinuteOfDay(parts.minuteOfDay)} IST`;
      }),
    );
  }

  checks.push(
    await check('funds', async () => {
      const balance = await market.availableFunds();
      return `available balance ${balance.toFixed(2)} INR (sizing uses CAPITAL_INR in paper mode and this value in live mode)`;
    }),
  );

  checks.push(
    await check('open option positions at broker', async () => {
      const rows = await client.positions.list();
      const open = rows.filter(
        (row) => (String(row.exchangeSegment) === 'NSE_FNO' || String(row.exchangeSegment) === 'BSE_FNO') && (row.netQty ?? 0) !== 0,
      );
      if (open.length > 0) {
        throw new Error(`${open.length} open option position(s); the live agent refuses to start with these`);
      }
      return 'none';
    }),
  );

  for (const result of checks) {
    console.log(`${result.ok ? 'PASS' : 'FAIL'}  ${result.name}: ${result.detail}`);
  }
  const failed = checks.filter((result) => !result.ok).length;
  console.log(`\n${checks.length - failed}/${checks.length} checks passed. No orders were placed by this script.`);
  process.exitCode = failed === 0 ? 0 : 1;
}

main().catch((error: unknown) => {
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
