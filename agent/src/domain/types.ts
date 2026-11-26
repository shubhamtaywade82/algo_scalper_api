export type SpotSegment = 'IDX_I';
export type OptionSegment = 'NSE_FNO' | 'BSE_FNO';
export type OptionType = 'CE' | 'PE';
export type Direction = 'BULLISH' | 'BEARISH';

/** Composite identity: Dhan security ids are only unique within an exchange segment. */
export interface InstrumentRef {
  readonly exchangeSegment: string;
  readonly securityId: string;
}

export function instrumentKey(ref: InstrumentRef): string {
  return `${ref.exchangeSegment}:${ref.securityId}`;
}

export interface Candle {
  /** Bar open, epoch ms (UTC instant). */
  readonly time: number;
  readonly open: number;
  readonly high: number;
  readonly low: number;
  readonly close: number;
  readonly volume: number;
}

export interface Tick {
  readonly exchangeSegment: string;
  readonly securityId: string;
  readonly ltp: number;
  /** Exchange last-traded time, epoch ms. */
  readonly ltt: number;
}

export interface UnderlyingSpec {
  /** Index symbol as listed in the scrip master, e.g. `NIFTY`. */
  readonly symbol: string;
  /** Index spot instrument (`IDX_I`), resolved from the scrip master at startup. */
  readonly spot: InstrumentRef;
  readonly optionSegment: OptionSegment;
}

export interface OptionContract {
  readonly underlying: string;
  readonly securityId: string;
  readonly exchangeSegment: OptionSegment;
  readonly symbol: string;
  readonly optionType: OptionType;
  readonly strike: number;
  /** `YYYY-MM-DD`, IST expiry date. */
  readonly expiry: string;
  readonly lotSize: number;
  readonly tickSize: number;
}

export interface OptionQuote {
  readonly ltp: number;
  readonly bid: number | undefined;
  readonly ask: number | undefined;
  readonly oi: number | undefined;
  readonly volume: number | undefined;
  readonly observedAt: number;
}

export interface Signal {
  readonly underlying: string;
  readonly direction: Direction;
  /** Open time of the closed bar that produced the signal. */
  readonly barTime: number;
  readonly spot: number;
  readonly reasons: readonly string[];
  /** Which strategy fired, so results can be judged per strategy. `test` for an operator test trade. */
  readonly strategy?: string;
  readonly flipBarTime?: number | undefined;
}

export interface OpenPosition {
  /** Equals the entry correlation id; stable across the position's life. */
  readonly positionId: string;
  readonly underlying: string;
  readonly contract: OptionContract;
  readonly quantity: number;
  readonly averagePrice: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly openedAt: number;
  readonly initialStopPrice?: number | undefined;
  readonly highWaterMark?: number | undefined;
  readonly trailingJump?: number | undefined;
  readonly breakevenAtRr?: number | undefined;
  readonly runner?: boolean | undefined;
}

export type ExitReason =
  | 'STOP_LOSS'
  | 'TARGET'
  | 'TIME_STOP'
  | 'STALE_DATA'
  | 'EOD_FLATTEN'
  | 'DAILY_LOSS'
  | 'SHUTDOWN'
  | 'MANUAL'
  | 'EXTERNAL'
  /** Market structure shifted against the position's side. */
  | 'STRUCTURE_BREAK';
