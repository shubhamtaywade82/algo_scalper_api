import type { TradingMode } from '../domain/mode.js';
import type { ExitReason, OptionContract, Tick } from '../domain/types.js';

/** Entry is always a BUY of a long option. There is deliberately no SELL-to-open shape. */
export interface EntryOrder {
  readonly side: 'BUY';
  /** Unique per attempt, at most 30 characters (the broker's limit). Doubles as the position id. */
  readonly correlationId: string;
  readonly underlying: string;
  readonly contract: OptionContract;
  readonly quantity: number;
  readonly entryReference: number;
  readonly stopLossPrice: number;
  readonly targetPrice: number;
  readonly initialStopPrice?: number | undefined;
  readonly trailingJump?: number | undefined;
  readonly breakevenAtRr?: number | undefined;
  readonly runner?: boolean | undefined;
}

/** Exit closes a long position the agent already holds. It never opens a short. */
export interface ExitOrder {
  readonly side: 'SELL';
  readonly correlationId: string;
  readonly underlying: string;
  readonly positionId: string;
  readonly contract: OptionContract;
  readonly quantity: number;
  readonly reason: ExitReason;
  readonly referencePrice: number;
}

export type ExecutionEvent =
  | {
      readonly kind: 'ENTRY_FILLED';
      readonly correlationId: string;
      readonly underlying: string;
      readonly quantity: number;
      readonly averagePrice: number;
      readonly at: number;
    }
  | { readonly kind: 'ENTRY_REJECTED'; readonly correlationId: string; readonly underlying: string; readonly reason: string }
  | { readonly kind: 'ENTRY_UNCONFIRMED'; readonly correlationId: string; readonly underlying: string; readonly reason: string }
  | {
      readonly kind: 'EXIT_FILLED';
      readonly correlationId: string;
      readonly underlying: string;
      readonly positionId: string;
      readonly quantity: number;
      readonly averagePrice: number;
      readonly reason: ExitReason;
      readonly at: number;
    }
  | {
      readonly kind: 'EXIT_REJECTED';
      readonly correlationId: string;
      readonly underlying: string;
      readonly positionId: string;
      readonly reason: string;
    }
  | {
      readonly kind: 'EXIT_UNCONFIRMED';
      readonly correlationId: string;
      readonly underlying: string;
      readonly positionId: string;
      readonly reason: string;
    }
  | {
      /** The position closed without an agent exit order: a broker bracket leg or a paper SL/TP fill. */
      readonly kind: 'PROTECTIVE_EXIT_FILLED';
      readonly underlying: string;
      readonly positionId: string;
      readonly quantity: number;
      readonly averagePrice: number;
      readonly reason: ExitReason;
      readonly at: number;
    }
  | {
      /** Broker state contradicts local state (e.g. net short an option). Trading must stop. */
      readonly kind: 'BROKER_MISMATCH';
      readonly underlying: string;
      readonly positionId: string;
      readonly reason: string;
    };

export type ExecutionListener = (event: ExecutionEvent) => void;

/**
 * Where a stop and target are held. `EXCHANGE_BRACKET`: the broker holds them as super-order legs, so they fire
 * without the agent. `CLIENT_SIDE`: the agent sends the sell itself when the option LTP reaches them, so a silent
 * option feed leaves the position without a stop.
 */
export type VenueProtection = 'EXCHANGE_BRACKET' | 'CLIENT_SIDE';

/**
 * Single execution contract for paper and live. Entry and exit results arrive
 * as events, never as return values, so the state machine is driven by one
 * source of truth regardless of venue. `submit*` never throws for a venue
 * outcome; it reports rejected or unconfirmed states through events.
 */
export interface ExecutionPort {
  readonly mode: TradingMode;
  readonly protection: VenueProtection;
  /** Fill prices already include charges (paper_exchange nets them in). Otherwise the agent deducts an estimate. */
  readonly chargesInFills?: boolean;
  /** Starts background work such as broker reconciliation. Optional: paper has none. */
  start?(): void;
  submitEntry(order: EntryOrder): Promise<void>;
  submitExit(order: ExitOrder): Promise<void>;
  /** Option LTP feed. Paper simulates protective stop and target fills from it; live ignores it. */
  onOptionTick(tick: Tick): void;
  onEvent(listener: ExecutionListener): () => void;
  /** Live only: disengages trading at the broker. Paper has no broker-side switch. */
  engageBrokerKillSwitch?(reason: string): Promise<void>;
  /** Live only, and only when BROKER_PNL_EXIT is on: arms the broker's daily P&L exit at the loss limit. */
  armBrokerPnlExit?(lossInr: number): Promise<void>;
  close(): Promise<void>;
}
