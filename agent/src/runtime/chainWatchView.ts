import type { ChainSnapshot } from '../options/selector.js';
import { minStrikeStep, nearestAtmStrike, targetEntryStrike } from '../options/selector.js';
import { analyzeOptionChain } from '../options/chainAnalyzer.js';
import type { OptionType } from '../domain/types.js';
import type { ChainMarketBias, ChainWatchView, IndicatorView } from './views.js';

const EPSILON = 1e-6;
export const CHAIN_STRIKE_RADIUS = 2;

export interface ChainWatchBuildInput {
  readonly symbol: string;
  readonly spot: number | undefined;
  readonly chain: ChainSnapshot | undefined;
  readonly offsetSteps: number;
  readonly maxSpreadPct: number;
  readonly minOpenInterest: number;
  readonly openPosition: { readonly strike: number; readonly optionType: OptionType } | undefined;
  readonly indicators: IndicatorView;
  readonly strikeScroll: number;
  readonly nowMs: number;
  readonly status: ChainWatchView['status'];
  readonly error: string | undefined;
}

export function strikeScrollBounds(strikeCount: number, atmIndex: number): { min: number; max: number } {
  if (strikeCount <= 0) {
    return { min: 0, max: 0 };
  }
  const minCenter = Math.min(atmIndex, CHAIN_STRIKE_RADIUS);
  const maxCenter = Math.max(atmIndex, strikeCount - 1 - CHAIN_STRIKE_RADIUS);
  return { min: minCenter - atmIndex, max: maxCenter - atmIndex };
}

export function marketBiasFromIndicators(indicators: IndicatorView): ChainMarketBias {
  const { supertrend, emaFast, emaSlow } = indicators;
  if (supertrend === undefined || emaFast === undefined || emaSlow === undefined) {
    return 'NEUTRAL';
  }
  if (supertrend === 'UP' && emaFast > emaSlow) {
    return 'BULLISH';
  }
  if (supertrend === 'DOWN' && emaFast < emaSlow) {
    return 'BEARISH';
  }
  return 'NEUTRAL';
}

function spreadPct(bid: number | undefined, ask: number | undefined): number | undefined {
  if (bid === undefined || ask === undefined || !(bid > 0) || !(ask >= bid)) {
    return undefined;
  }
  const mid = (bid + ask) / 2;
  return mid > 0 ? ((ask - bid) / mid) * 100 : undefined;
}

function legPasses(spread: number | undefined, oi: number | undefined, maxSpreadPct: number, minOi: number): boolean {
  if (spread === undefined || spread > maxSpreadPct) {
    return false;
  }
  return (oi ?? 0) >= minOi;
}

function sliceStrikeWindow(strikes: readonly number[], atmIndex: number, scroll: number): number[] {
  const center = Math.max(0, Math.min(strikes.length - 1, atmIndex + scroll));
  const start = Math.max(0, center - CHAIN_STRIKE_RADIUS);
  const end = Math.min(strikes.length, center + CHAIN_STRIKE_RADIUS + 1);
  return strikes.slice(start, end);
}

/** Read-only chain ladder for the cockpit; mirrors entry strike selection without trading. */
export function buildChainWatchView(input: ChainWatchBuildInput): ChainWatchView {
  const base = {
    symbol: input.symbol,
    spot: input.spot,
    expiry: input.chain?.expiry,
    atmStrike: undefined as number | undefined,
    bullishEntryStrike: undefined as number | undefined,
    bearishEntryStrike: undefined as number | undefined,
    fetchedAgeMs: input.chain === undefined ? undefined : Math.max(0, input.nowMs - input.chain.fetchedAt),
    status: input.status,
    error: input.error,
    rows: [] as ChainWatchView['rows'],
    maxOpenInterest: 0,
    strikeScroll: 0,
    strikeScrollMin: 0,
    strikeScrollMax: 0,
    marketBias: marketBiasFromIndicators(input.indicators),
  };
  if (input.spot === undefined) {
    return { ...base, status: input.status === 'ready' ? 'waiting_spot' : input.status };
  }
  if (input.chain === undefined || input.chain.strikes.length === 0) {
    return base;
  }

  const strikePrices = [...new Set(input.chain.strikes.map((row) => row.strike))].sort((a, b) => a - b);
  const atm = nearestAtmStrike(input.spot, strikePrices);
  const step = minStrikeStep(strikePrices);
  if (atm === undefined || step === undefined) {
    return { ...base, expiry: input.chain.expiry, status: 'error', error: 'chain too thin to show strikes' };
  }

  const atmIndex = strikePrices.findIndex((strike) => Math.abs(strike - atm) < EPSILON);
  const scrollBounds = strikeScrollBounds(strikePrices.length, atmIndex);
  const strikeScroll = Math.min(scrollBounds.max, Math.max(scrollBounds.min, input.strikeScroll));
  const bullishEntryStrike = targetEntryStrike(atm, step, 'BULLISH', input.offsetSteps);
  const bearishEntryStrike = targetEntryStrike(atm, step, 'BEARISH', input.offsetSteps);
  const visible = sliceStrikeWindow(strikePrices, atmIndex, strikeScroll);
  const analysis = input.chain !== undefined && input.spot !== undefined ? analyzeOptionChain(input.chain, input.spot) : undefined;
  let maxOi = 1;
  const rows = visible.map((strike) => {
    const row = input.chain!.strikes.find((candidate) => Math.abs(candidate.strike - strike) < EPSILON);
    const callSpread = spreadPct(row?.call?.bid, row?.call?.ask);
    const putSpread = spreadPct(row?.put?.bid, row?.put?.ask);
    const callOi = row?.call?.oi ?? 0;
    const putOi = row?.put?.oi ?? 0;
    maxOi = Math.max(maxOi, callOi, putOi);
    const markers: ('ATM' | 'CE_ENTRY' | 'PE_ENTRY' | 'OPEN' | 'RES' | 'SUP')[] = [];
    if (Math.abs(strike - atm) < EPSILON) {
      markers.push('ATM');
    }
    if (Math.abs(strike - bullishEntryStrike) < EPSILON) {
      markers.push('CE_ENTRY');
    }
    if (Math.abs(strike - bearishEntryStrike) < EPSILON) {
      markers.push('PE_ENTRY');
    }
    if (analysis !== undefined) {
      if (Math.abs(strike - analysis.callResistance.strike) < EPSILON) {
        markers.push('RES');
      }
      if (Math.abs(strike - analysis.putSupport.strike) < EPSILON) {
        markers.push('SUP');
      }
    }
    if (input.openPosition !== undefined && Math.abs(strike - input.openPosition.strike) < EPSILON) {
      markers.push('OPEN');
    }
    return {
      strike,
      markers,
      call: {
        bid: row?.call?.bid,
        ask: row?.call?.ask,
        spreadPct: callSpread,
        openInterest: row?.call?.oi,
        passesGate: legPasses(callSpread, row?.call?.oi, input.maxSpreadPct, input.minOpenInterest),
      },
      put: {
        bid: row?.put?.bid,
        ask: row?.put?.ask,
        spreadPct: putSpread,
        openInterest: row?.put?.oi,
        passesGate: legPasses(putSpread, row?.put?.oi, input.maxSpreadPct, input.minOpenInterest),
      },
    };
  });

  return {
    ...base,
    expiry: input.chain.expiry,
    atmStrike: atm,
    bullishEntryStrike,
    bearishEntryStrike,
    status: 'ready',
    rows,
    maxOpenInterest: maxOi,
    strikeScroll,
    strikeScrollMin: scrollBounds.min,
    strikeScrollMax: scrollBounds.max,
    marketBias: marketBiasFromIndicators(input.indicators),
    analysis,
  };
}
