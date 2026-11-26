import type { Instrument } from '@nemesis-oss/dhanhq-sdk';
import { z } from 'zod';
import type { InstrumentRef, OptionContract, OptionSegment, OptionType } from '../domain/types.js';
import type { CacheStore } from '../persistence/cache.js';
import { msUntilNextIstMidnight } from '../persistence/cache.js';

/** The slice of the SDK's `client.instruments` this module needs. */
export interface InstrumentSource {
  bySegment(exchangeSegment: string): Promise<Instrument[]>;
}

const ISO_DATE_PREFIX = /^(\d{4}-\d{2}-\d{2})/;

const CONTRACT = z.object({
  underlying: z.string().min(1),
  securityId: z.string().min(1),
  exchangeSegment: z.enum(['NSE_FNO', 'BSE_FNO']),
  symbol: z.string().min(1),
  optionType: z.enum(['CE', 'PE']),
  strike: z.number().positive(),
  expiry: z.string().regex(ISO_DATE_PREFIX),
  lotSize: z.number().int().positive(),
  tickSize: z.number().positive(),
});
const CONTRACT_LIST = z.array(CONTRACT);

/** Scrip-master expiries arrive as `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS`; both reduce to the date. */
export function normalizeExpiry(raw: string | undefined): string | undefined {
  if (raw === undefined) {
    return undefined;
  }
  return ISO_DATE_PREFIX.exec(raw.trim())?.[1];
}

function positiveNumber(value: number | undefined): number | undefined {
  return value !== undefined && Number.isFinite(value) && value > 0 ? value : undefined;
}

/**
 * Maps one scrip-master row to an index option contract. Returns undefined for
 * any row that is not a complete, unambiguous index option on the expected segment.
 */
export function toOptionContract(row: Instrument, underlying: string, optionSegment: OptionSegment): OptionContract | undefined {
  if (row.instrument !== 'OPTIDX') {
    return undefined;
  }
  if (row.underlyingSymbol?.toUpperCase() !== underlying || row.exchangeSegment !== optionSegment) {
    return undefined;
  }
  const optionType = row.optionType?.toUpperCase();
  if (optionType !== 'CE' && optionType !== 'PE') {
    return undefined;
  }
  const strike = positiveNumber(row.strikePrice);
  const expiry = normalizeExpiry(row.expiryDate);
  const lotSize = positiveNumber(row.lotSize);
  // Scrip master TICK_SIZE is in paise (5 = ₹0.05); read as rupees it rounded every price to ₹5.
  const tickSizePaise = positiveNumber(row.tickSize);
  const tickSize = tickSizePaise === undefined ? undefined : tickSizePaise / 100;
  if (strike === undefined || expiry === undefined || lotSize === undefined || tickSize === undefined) {
    return undefined;
  }
  if (!row.securityId) {
    return undefined;
  }
  return {
    underlying,
    securityId: row.securityId,
    exchangeSegment: optionSegment,
    symbol: row.displayName ?? row.symbolName ?? row.securityId,
    optionType: optionType as OptionType,
    strike,
    expiry,
    lotSize: Math.round(lotSize),
    tickSize,
  };
}

/**
 * Resolves underlyings and option contracts from the scrip master. Lookups are
 * exact and fail closed: an unknown or ambiguous symbol throws instead of
 * guessing a security id, because a wrong id would trade the wrong instrument.
 */
export class InstrumentMaster {
  private readonly contractCache = new Map<string, { day: string; contracts: readonly OptionContract[] }>();

  constructor(
    private readonly source: InstrumentSource,
    private readonly istDay: () => string,
    private readonly options: {
      /** Shared across processes and restarts. Entries expire at the next IST midnight. */
      readonly cache?: CacheStore;
      readonly now?: () => number;
    } = {},
  ) {}

  async resolveSpot(symbol: string, spotSegment: 'IDX_I' = 'IDX_I'): Promise<InstrumentRef> {
    const wanted = symbol.trim().toUpperCase();
    const rows = await this.source.bySegment(spotSegment);
    const matches = rows.filter(
      (row) => row.symbolName?.toUpperCase() === wanted || row.displayName?.toUpperCase() === wanted,
    );
    const distinct = new Map(matches.map((row) => [row.securityId, row]));
    if (distinct.size === 0) {
      throw new Error(`index "${symbol}" not found in ${spotSegment} scrip master`);
    }
    if (distinct.size > 1) {
      throw new Error(`index "${symbol}" is ambiguous in ${spotSegment}: ${[...distinct.keys()].join(', ')}`);
    }
    const [securityId] = [...distinct.keys()];
    return { exchangeSegment: spotSegment, securityId: String(securityId) };
  }

  /** Every listed index option for the underlying, cached per IST trading day. */
  async optionContracts(underlying: string, optionSegment: OptionSegment): Promise<readonly OptionContract[]> {
    const key = `${underlying}:${optionSegment}`;
    const day = this.istDay();
    const cached = this.contractCache.get(key);
    if (cached !== undefined && cached.day === day) {
      return cached.contracts;
    }
    const shared = await this.sharedContracts(key, day);
    if (shared !== undefined) {
      this.contractCache.set(key, { day, contracts: shared });
      return shared;
    }
    const wanted = underlying.toUpperCase();
    const rows = await this.source.bySegment(optionSegment);
    const contracts = rows
      .map((row) => toOptionContract(row, wanted, optionSegment))
      .filter((contract): contract is OptionContract => contract !== undefined);
    if (contracts.length === 0) {
      throw new Error(`no ${optionSegment} index option contracts found for ${underlying}`);
    }
    this.contractCache.set(key, { day, contracts });
    await this.options.cache?.set(this.cacheKey(key, day), contracts, msUntilNextIstMidnight((this.options.now ?? Date.now)()));
    return contracts;
  }

  /** A shared entry is trusted only after it passes the same shape check as a fresh read. A bad entry is a miss. */
  private async sharedContracts(key: string, day: string): Promise<readonly OptionContract[] | undefined> {
    if (this.options.cache === undefined) {
      return undefined;
    }
    const raw = await this.options.cache.get<unknown>(this.cacheKey(key, day));
    const parsed = CONTRACT_LIST.safeParse(raw);
    return parsed.success && parsed.data.length > 0 ? parsed.data : undefined;
  }

  private cacheKey(key: string, day: string): string {
    return `contracts:${key}:${day}`;
  }
}
