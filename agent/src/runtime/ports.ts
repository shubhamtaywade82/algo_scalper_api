import type { Candle, InstrumentRef, OptionContract, OptionSegment, UnderlyingSpec } from '../domain/types.js';
import type { ChainSnapshot } from '../options/selector.js';

export interface DiscoveredOpenPosition {
  readonly positionId: string;
  readonly underlying: string;
  readonly securityId: string;
  readonly exchangeSegment: string;
  readonly quantity: number;
  readonly averagePrice: number;
  readonly stopLossPrice?: number;
  readonly targetPrice?: number;
  readonly openedAt?: number;
}

/** Everything the agent needs from the market-data side, behind one seam for tests. */
export interface MarketPort {
  intradayCandles(spot: InstrumentRef, barMinutes: number, fromDate: string, toDate: string): Promise<Candle[]>;
  listExpiries(spot: InstrumentRef): Promise<string[]>;
  optionChain(spot: InstrumentRef, expiry: string): Promise<ChainSnapshot>;
  optionContracts(underlying: UnderlyingSpec['symbol'], optionSegment: OptionSegment): Promise<readonly OptionContract[]>;
  /** Funds the premium can be paid from. Paper uses configured capital; live uses the broker balance. */
  availableFunds(): Promise<number>;
  /** Live or paper: number of option legs with a non-zero net quantity at the broker/venue. */
  brokerOpenOptionCount(): Promise<number>;
  /** Discovered open positions to adopt on startup if any exist. */
  brokerOpenPositions?(): Promise<readonly DiscoveredOpenPosition[]>;
  /**
   * Live only: orders and super orders at the broker that are not in a terminal status, or whose status is
   * missing. An order the process sent before a crash shows here even before it fills. Paper returns 0.
   */
  brokerLiveOrderCount(): Promise<number>;
}

/** Feed-side view for the agent: LTP freshness and option subscription lifecycle. */
export interface FeedPort {
  /** The reason code that ended the market feed for good, or undefined while it is recoverable. */
  terminalDisconnectCode?(): number | undefined;
  ageMs(ref: InstrumentRef): number | undefined;
  subscribe(refs: readonly InstrumentRef[]): void;
  unsubscribe(refs: readonly InstrumentRef[]): void;
}
