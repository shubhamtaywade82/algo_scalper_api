import type { AgentConfig } from '../config.js';
import type { UnderlyingSpec } from '../domain/types.js';
import { pickExpiry } from '../options/selector.js';
import type { ChainSnapshot } from '../options/selector.js';
import { istParts } from '../time/ist.js';
import { buildChainWatchView } from './chainWatchView.js';
import type { MarketPort } from './ports.js';
import type { AgentView, ChainWatchView, IndicatorView } from './views.js';

const REFRESH_MS = 12_000;

const EMPTY_INDICATORS: IndicatorView = {
  emaFast: undefined,
  emaSlow: undefined,
  supertrend: undefined,
  supertrendLine: undefined,
  orbHigh: undefined,
  orbLow: undefined,
  orbFormed: false,
};

interface ChainWatchCache {
  readonly symbol: string;
  readonly expiry: string;
  readonly chain: ChainSnapshot;
}

/**
 * Polls Dhan option chain for whichever underlying the operator has selected in the cockpit.
 * One symbol at a time keeps REST traffic low and matches how ↑↓ focus works.
 */
export class CockpitChainWatch {
  private focusSymbol: string | undefined;
  private cache: ChainWatchCache | undefined;
  private lastFetchAt = 0;
  private inFlight: Promise<void> | undefined;
  private error: string | undefined;
  private loading = false;
  private strikeScroll = 0;

  constructor(
    private readonly config: AgentConfig,
    private readonly specs: readonly UnderlyingSpec[],
    private readonly market: MarketPort,
    private readonly agentView: (symbol: string, nowMs: number) => AgentView | undefined,
    private readonly now: () => number,
    private readonly onUpdated: () => void,
  ) {}

  setFocus(symbol: string | undefined): void {
    if (symbol === this.focusSymbol) {
      return;
    }
    this.focusSymbol = symbol;
    this.cache = undefined;
    this.error = undefined;
    this.lastFetchAt = 0;
    this.strikeScroll = 0;
    void this.refresh(true);
  }

  nudgeStrikeScroll(delta: number): boolean {
    const bounds = this.view(this.now());
    if (bounds === undefined || bounds.status !== 'ready') {
      return false;
    }
    const next = bounds.strikeScroll + delta;
    if (next < bounds.strikeScrollMin || next > bounds.strikeScrollMax) {
      return false;
    }
    this.strikeScroll = next;
    this.onUpdated();
    return true;
  }

  onClock(phase: 'RUNNING' | string): void {
    if (phase !== 'RUNNING' || this.focusSymbol === undefined) {
      return;
    }
    if (this.now() - this.lastFetchAt < REFRESH_MS) {
      return;
    }
    void this.refresh(false);
  }

  view(nowMs: number): ChainWatchView | undefined {
    if (this.focusSymbol === undefined) {
      return undefined;
    }
    const agent = this.agentView(this.focusSymbol, nowMs);
    const chain = this.cache?.symbol === this.focusSymbol ? this.cache.chain : undefined;
    const status =
      this.loading ? 'loading' : this.error !== undefined ? 'error' : chain === undefined ? 'idle' : 'ready';
    const position = agent?.position;
    const view = buildChainWatchView({
      symbol: this.focusSymbol,
      spot: agent?.spot,
      chain,
      offsetSteps: this.config.contract.strikeOffsetSteps,
      maxSpreadPct: this.config.contract.maxSpreadPct,
      minOpenInterest: this.config.contract.minOpenInterest,
      openPosition:
        position === undefined ? undefined : { strike: position.strike, optionType: position.optionType },
      indicators: agent?.indicators ?? EMPTY_INDICATORS,
      strikeScroll: this.strikeScroll,
      nowMs,
      status,
      error: this.error,
    });
    if (view.strikeScroll !== this.strikeScroll) {
      this.strikeScroll = view.strikeScroll;
    }
    return view;
  }

  private async refresh(force: boolean): Promise<void> {
    const symbol = this.focusSymbol;
    if (symbol === undefined) {
      return;
    }
    if (this.inFlight !== undefined) {
      if (!force) {
        return;
      }
      await this.inFlight.catch(() => undefined);
    }
    const spec = this.specs.find((row) => row.symbol === symbol);
    if (spec === undefined) {
      this.error = 'unknown underlying';
      return;
    }
    this.loading = true;
    this.error = undefined;
    this.inFlight = this.fetch(spec, symbol).finally(() => {
      this.inFlight = undefined;
      this.loading = false;
      this.onUpdated();
    });
    await this.inFlight;
  }

  private async fetch(spec: UnderlyingSpec, symbol: string): Promise<void> {
    try {
      const today = istParts(this.now()).date;
      const expiries = await this.market.listExpiries(spec.spot);
      const expiry = pickExpiry(expiries, today, this.config.contract.minDaysToExpiry, this.config.contract.maxDaysToExpiry);
      if (expiry === undefined) {
        this.error = expiries.length === 0
          ? `${symbol} (${spec.optionSegment}) option chain not supported by Dhan API`
          : `no expiry ≥ ${this.config.contract.minDaysToExpiry} day(s) out`;
        this.cache = undefined;
        return;
      }
      const chain = await this.market.optionChain(spec.spot, expiry);
      this.cache = { symbol, expiry, chain };
      this.lastFetchAt = this.now();
    } catch (error) {
      this.cache = undefined;
      this.error = error instanceof Error ? error.message : String(error);
      this.lastFetchAt = this.now();
    }
  }
}
