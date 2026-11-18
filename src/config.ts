import { existsSync, readFileSync } from 'node:fs';
import { parse as parseYaml } from 'yaml';
import { createHash } from 'node:crypto';
import type { OptionSegment } from './domain/types.js';
import type { AllInRiskPolicy } from './risk/allInLoss.js';
import { TRADING_MODES, type TradingMode } from './domain/mode.js';
import { POSTURES, type StrategyPosture, STRATEGY_CATALOG, type StrategyId } from './strategy/session.js';

/** The production REST host the SDK uses when DHAN_BASE_URL is not set. The sandbox must never point here. */
const PRODUCTION_DHAN_HOST = 'api.dhan.co';
import { parseRedisUrl, validatePostgresUrl } from './persistence/urls.js';
import { parseMinuteOfDay } from './time/ist.js';

/** Index symbols this agent knows how to trade, with the segment their options list on. */
// Real-money ceilings, deliberately not configurable: a stray .env (MAX_RISK_PER_TRADE_PCT=30 was found on
// 2026-10-27) must stop a live start, not size a live order.
const LIVE_MAX_RISK_PER_TRADE_PCT = 2;
const LIVE_MAX_DAILY_LOSS_PCT = 6;
const LATEST_FLATTEN_MINUTE = 15 * 60 + 15;

export const KNOWN_UNDERLYINGS: Readonly<Record<string, OptionSegment>> = {
  NIFTY: 'NSE_FNO',
  BANKNIFTY: 'NSE_FNO',
  FINNIFTY: 'NSE_FNO',
  MIDCPNIFTY: 'NSE_FNO',
  SENSEX: 'BSE_FNO',
};

export const LIVE_ACK_PHRASE = 'I_ACCEPT_LIVE_ORDER_RISK';
/** Operator sign-off for enforcing all-in risk live (OTA-311). Shadow comparison needs no sign-off. */
export const ALL_IN_LIVE_ACK_PHRASE = 'I_APPROVE_ALL_IN_RISK_ENFORCEMENT';

/**
 * How the Dhan access token is obtained. `otp` logs in with PIN + TOTP at startup and renews
 * the token itself. `static` uses a token pasted in by hand, which expires and must be replaced.
 */
export type DhanAuthConfig =
  | { readonly kind: 'static'; readonly accessToken: string }
  | { readonly kind: 'otp'; readonly pin: string; readonly totpSecret: string }
  | { readonly kind: 'authority'; readonly url: string; readonly key: string };

/**
 * Sandbox order credentials, passed to the SDK's `hybrid` mode. Market data stays on the production credentials;
 * orders, positions, funds and controls go to the sandbox. `baseUrl` is optional: the SDK defaults to sandbox.dhan.co.
 */
export interface SandboxConfig {
  readonly clientId: string;
  readonly accessToken: string;
  readonly baseUrl: string | undefined;
}

/** The paper_exchange server (github.com/shubhamtaywade82/paper_exchange) used as the paper order venue. */
export interface PaperExchangeConfig {
  /** Base URL of the server, without the /api suffix. */
  readonly url: string;
  /** Sent as X-API-Key. Never logged. */
  readonly apiKey: string;
  /** Sent as X-Account-Id. The paper account the orders belong to. */
  readonly accountId: string;
}

/** Telegram credentials for operator alerts. Bot token acts as a secret; never logged. */
export interface TelegramConfig {
  readonly botToken: string;
  readonly chatId: string;
}

export interface AgentConfig {
  readonly mode: TradingMode;
  readonly dhan: {
    readonly clientId: string;
    readonly auth: DhanAuthConfig;
    readonly baseUrl: string | undefined;
    /** OTP tokens are cached here between process runs. Defaults to the SDK directory (~/.dhanhq). */
    readonly tokenCacheDir: string | undefined;
  };
  /** Present only in sandbox mode. */
  readonly sandbox: SandboxConfig | undefined;
  /**
   * `freezeQuantity` is the exchange's per-order quantity limit for the underlying's options, set by the operator
   * (FREEZE_QTY_<SYMBOL>). It is not hardcoded: the exchanges revise it. When set, an entry is sized at or below it.
   */
  readonly underlyings: readonly { readonly symbol: string; readonly optionSegment: OptionSegment; readonly freezeQuantity?: number | undefined }[];
  readonly capital: {
    readonly inr: number;
    readonly maxRiskPerTradePct: number;
    readonly maxDailyLossPct: number;
    readonly maxOpenPositions: number;
    readonly maxPositionsPerUnderlying: number;
    readonly maxPositionsPerSide: number;
    /** Whether a CE and a PE may be open together, on one index or across indices. */
    readonly allowOpposingSides: boolean;
    readonly maxTradesPerDay: number;
    readonly maxLotsPerOrder: number;
    readonly enforceDailyLoss: boolean;
    /** OTA-311 rollout: 'off', 'shadow' (planned risk decides, all-in is journalled), or 'enforce' (all-in decides). */
    readonly allInRiskPolicy: AllInRiskPolicy;
  };
  readonly contract: {
    readonly minDaysToExpiry: number;
    readonly maxDaysToExpiry: number;
    readonly expiryDayEntryCutoffMinute: number;
    /** 0 = ATM, positive = further OTM, negative = further ITM. */
    readonly strikeOffsetSteps: number;
    readonly maxSpreadPct: number;
    readonly minOpenInterest: number;
    readonly minVolume: number;
    /** Live entries are LIMIT orders at ask × (1 + this %), and are sized and bracketed off that limit. */
    readonly entryLimitBufferPct: number;
  };
  readonly chainAnalysis: {
    readonly enabled: boolean;
    readonly minHeadroomPts: number;
  };
  /** Day trend, regime, market structure and chain bias as an entry gate and a structure-shift exit. */
  readonly context: {
    readonly enabled: boolean;
    readonly structureExit: boolean;
  };
  readonly exits: {
    readonly stopLossPct: number;
    readonly targetRr: number;
    readonly maxHoldMinutes: number;
    readonly flattenByMinute: number;
    readonly cooldownSeconds: number;
    readonly trailingJumpPct: number;
    readonly breakevenAtRr: number;
    readonly runnerMode: boolean;
  };
  readonly session: {
    readonly entryStartMinute: number;
    readonly entryEndMinute: number;
    readonly initialPosture: StrategyPosture;
  };
  readonly strategy: {
    readonly barMinutes: number;
    readonly supertrendPeriod: number;
    readonly supertrendMultiplier: number;
    readonly emaFast: number;
    readonly emaSlow: number;
    readonly orbMinutes: number;
    readonly warmupDays: number;
    readonly enabledStrategies: readonly StrategyId[] | undefined;
    readonly maxBarsSinceFlip: number;
    readonly minDistanceAtr: number;
  };
  readonly feed: {
    readonly staleMs: number;
    readonly istShiftedTimestamps: boolean;
    /** WebSocket LTT convention. Measured 2026-10-23: ticker and full packets stamp IST wall-clock, unlike REST bars. */
    readonly feedIstShifted: boolean;
    /** Dhan market WebSocket subscription mode. Index spots (IDX_I) do not stream in `full` mode. */
    readonly marketFeedMode: 'ticker' | 'quote' | 'full';
  };
  readonly paper: {
    /** Where paper orders are simulated: the local PostgreSQL venue, or the paper_exchange server. */
    readonly backend: 'postgres' | 'exchange';
    /** Present when backend is exchange. */
    readonly exchange: PaperExchangeConfig | undefined;
    readonly slippageBps: number;
  };
  readonly llm: {
    readonly enabled: boolean;
    readonly host: string;
    readonly model: string | undefined;
    readonly apiKey: string | undefined;
    readonly timeoutMs: number;
  };
  readonly ops: {
    /** Directory holding one `events-YYYY-MM-DD.jsonl` file per IST trading day. */
    readonly eventLogDir: string;
    readonly brokerKillSwitchOnBreach: boolean;
    /** Milliseconds of option-tick silence after which a client-side position is sold as STALE_DATA. Never below FEED_STALE_MS. */
    readonly stalePositionGraceMs: number;
    /** Live only: arms Dhan's broker-side daily P&L exit at the loss limit, so it outlives a crash. Off by default. */
    readonly brokerPnlExit: boolean;
    readonly reconcileIntervalMs: number;
    readonly orderTimeoutMs: number;
    /** Plain-text POST target for operator alerts (an ntfy.sh topic URL works). Acts as a secret; never logged. */
    readonly alertWebhookUrl: string | undefined;
    /** Telegram credentials for formatted operator alerts. Token acts as a secret; never logged. */
    readonly telegram: TelegramConfig | undefined;
  };
  readonly persistence: {
    /** PostgreSQL. Required in every mode: the ledger and lease for live and sandbox, the paper venue for paper. Credentials inside the URL are never logged. */
    readonly databaseUrl: string | undefined;
    /** Redis for the account rate gate and the contract cache. Required for live and sandbox, optional for paper. The trading lease lives in PostgreSQL. */
    readonly redisUrl: string | undefined;
    /**
     * Opt-in. The Redis key another process (the Rails app) reserves Dhan option-chain slots under. When set, chain calls
     * queue in one line with that process instead of each keeping its own gate. Requires `redisUrl`.
     */
    readonly sharedRateLimitKey: string | undefined;
    /** Stable name for this host, recorded on every run. Defaults to the hostname at runtime. */
    readonly instanceId: string | undefined;
    /** Trading lease TTL. A crashed holder's lease expires after this, plus the order timeout. */
    readonly leaseTtlMs: number;
    readonly postgresMaxConnections: number;
  };
}

type Env = Readonly<Record<string, string | undefined>>;

function text(env: Env, key: string, fallback?: string): string {
  const raw = env[key]?.trim();
  if (raw !== undefined && raw !== '') {
    return raw;
  }
  if (fallback === undefined) {
    throw new Error(`${key} is required`);
  }
  return fallback;
}

function optionalText(env: Env, key: string): string | undefined {
  const raw = env[key]?.trim();
  return raw === undefined || raw === '' ? undefined : raw;
}

function number(env: Env, key: string, fallback: number, bounds: { min: number; max: number; integer?: boolean }): number {
  const raw = optionalText(env, key);
  const value = raw === undefined ? fallback : Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`${key} must be a number, got "${raw}"`);
  }
  if (bounds.integer && !Number.isInteger(value)) {
    throw new Error(`${key} must be an integer, got ${value}`);
  }
  if (value < bounds.min || value > bounds.max) {
    throw new Error(`${key} must be within [${bounds.min}, ${bounds.max}], got ${value}`);
  }
  return value;
}

/** OTA-311 rollout policy. Anything other than the three names is refused, so a typo cannot silently enforce or disable a check. */
function riskPolicy(env: Env): AllInRiskPolicy {
  const value = text(env, 'ALL_IN_RISK_POLICY', 'off');
  if (value !== 'off' && value !== 'shadow' && value !== 'enforce') {
    throw new Error(`ALL_IN_RISK_POLICY must be off, shadow or enforce, got ${value}`);
  }
  return value;
}

function flag(env: Env, key: string, fallback: boolean): boolean {
  const raw = optionalText(env, key);
  if (raw === undefined) {
    return fallback;
  }
  if (['true', '1', 'on', 'yes'].includes(raw.toLowerCase())) {
    return true;
  }
  if (['false', '0', 'off', 'no'].includes(raw.toLowerCase())) {
    return false;
  }
  throw new Error(`${key} must be a boolean flag (true/false), got "${raw}"`);
}

function minuteOfDay(env: Env, key: string, fallback: string): number {
  try {
    return parseMinuteOfDay(text(env, key, fallback));
  } catch (error) {
    throw new Error(`${key}: ${(error as Error).message}`);
  }
}

function parseMarketFeedMode(env: Env): 'ticker' | 'quote' | 'full' {
  const raw = text(env, 'DHAN_MARKET_FEED_MODE', 'ticker').toLowerCase();
  if (raw === 'ticker' || raw === 'quote' || raw === 'full') {
    return raw;
  }
  throw new Error('DHAN_MARKET_FEED_MODE must be ticker, quote or full');
}

/**
 * OTP login (DHAN_PIN + DHAN_TOTP_SECRET) is preferred and selected whenever either is set.
 * A static DHAN_ACCESS_TOKEN is accepted only when no OTP variable is present, so the token
 * source is never ambiguous. Error messages name variables but never echo their values.
 */
function parseDhanAuth(env: Env): DhanAuthConfig {
  const pin = optionalText(env, 'DHAN_PIN');
  const totpSecret = optionalText(env, 'DHAN_TOTP_SECRET');
  const accessToken = optionalText(env, 'DHAN_ACCESS_TOKEN');

  const authority = parseTokenAuthority(env);
  if (authority !== undefined) {
    if (pin !== undefined || totpSecret !== undefined || accessToken !== undefined) {
      throw new Error(
        'DHAN_TOKEN_AUTHORITY_URL conflicts with DHAN_PIN, DHAN_TOTP_SECRET and DHAN_ACCESS_TOKEN; a second login would invalidate the authority\'s token',
      );
    }
    return authority;
  }
  if (pin === undefined && totpSecret === undefined) {
    if (accessToken === undefined) {
      throw new Error('DHAN_ACCESS_TOKEN is required unless DHAN_PIN and DHAN_TOTP_SECRET are set');
    }
    return { kind: 'static', accessToken };
  }
  if (pin === undefined || totpSecret === undefined) {
    throw new Error('DHAN_PIN and DHAN_TOTP_SECRET must be set together');
  }
  if (accessToken !== undefined) {
    throw new Error('DHAN_ACCESS_TOKEN conflicts with DHAN_PIN/DHAN_TOTP_SECRET; remove DHAN_ACCESS_TOKEN so the token source is unambiguous');
  }
  // Authenticator apps show the secret in groups of four, sometimes with padding. Normalise before validating.
  const normalizedSecret = totpSecret.replace(/[\s-]/g, '').replace(/=+$/, '').toUpperCase();
  if (!/^[A-Z2-7]+$/.test(normalizedSecret)) {
    throw new Error('DHAN_TOTP_SECRET must be a base32 secret (letters A-Z and digits 2-7)');
  }
  return { kind: 'otp', pin, totpSecret: normalizedSecret };
}

/**
 * The Rails app owns the Dhan token: any other login invalidates it (DH-906). When these variables are set, this
 * process fetches the token from it and never logs in.
 */
function parseTokenAuthority(env: Env): Extract<DhanAuthConfig, { kind: 'authority' }> | undefined {
  const url = optionalText(env, 'DHAN_TOKEN_AUTHORITY_URL');
  const key = optionalText(env, 'DHAN_TOKEN_AUTHORITY_KEY');
  if (url === undefined && key === undefined) {
    return undefined;
  }
  if (url === undefined || key === undefined) {
    throw new Error('DHAN_TOKEN_AUTHORITY_URL and DHAN_TOKEN_AUTHORITY_KEY must be set together');
  }
  requireHttpsOrLoopback('DHAN_TOKEN_AUTHORITY_URL', url);
  return { kind: 'authority', url, key };
}

/** The URL's reply or request carries credentials, so plain http is accepted only to this machine. */
function requireHttpsOrLoopback(name: string, url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`${name} must be a URL`);
  }
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(parsed.hostname);
  if (parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && loopback)) {
    throw new Error(`${name} must be https, or http on loopback`);
  }
}

function parseUnderlyings(env: Env): AgentConfig['underlyings'] {
  const symbols = text(env, 'UNDERLYINGS', 'NIFTY')
    .split(',')
    .map((symbol) => symbol.trim().toUpperCase())
    .filter((symbol) => symbol.length > 0);
  if (symbols.length === 0) {
    throw new Error('UNDERLYINGS must list at least one index symbol');
  }
  const unique = [...new Set(symbols)];
  return unique.map((symbol) => {
    const optionSegment = KNOWN_UNDERLYINGS[symbol];
    if (optionSegment === undefined) {
      throw new Error(
        `UNDERLYINGS: "${symbol}" is not a supported index (supported: ${Object.keys(KNOWN_UNDERLYINGS).join(', ')})`,
      );
    }
    const freezeKey = `FREEZE_QTY_${symbol}`;
    const freezeQuantity = optionalText(env, freezeKey) === undefined ? undefined : number(env, freezeKey, 0, { min: 1, max: 1e7, integer: true });
    return { symbol, optionSegment, ...(freezeQuantity === undefined ? {} : { freezeQuantity }) };
  });
}

function parsePosture(env: Env): StrategyPosture {
  const raw = (optionalText(env, 'STRATEGY_POSTURE') ?? optionalText(env, 'POSTURE') ?? 'aligned').toLowerCase();
  if ((POSTURES as readonly string[]).includes(raw)) {
    return raw as StrategyPosture;
  }
  throw new Error(`STRATEGY_POSTURE must be one of ${POSTURES.join(', ')}, got "${raw}"`);
}

function parseEnabledStrategies(env: Env): readonly StrategyId[] | undefined {
  const raw = optionalText(env, 'ENABLED_STRATEGIES') ?? optionalText(env, 'STRATEGY_ENABLED');
  if (raw === undefined) {
    return undefined;
  }
  const parts = raw.split(',').map((s) => s.trim().toLowerCase()).filter((s) => s.length > 0) as StrategyId[];
  for (const id of parts) {
    if (!STRATEGY_CATALOG.some((s) => s.id === id)) {
      throw new Error(`Strategy "${id}" is unknown. Supported: ${STRATEGY_CATALOG.map((s) => s.id).join(', ')}`);
    }
  }
  return parts.length > 0 ? parts : undefined;
}

const YAML_ENV_MAP: Readonly<Record<string, string>> = {
  'underlyings': 'UNDERLYINGS',
  'underlying': 'UNDERLYINGS',
  'strategy.enabled_strategies': 'ENABLED_STRATEGIES',
  'strategy.active_strategies': 'ENABLED_STRATEGIES',
  'strategy.strategies': 'ENABLED_STRATEGIES',
  'session.current_posture': 'STRATEGY_POSTURE',
  'session.posture': 'STRATEGY_POSTURE',
  'posture': 'STRATEGY_POSTURE',
  'capital.inr': 'CAPITAL_INR',
  'capital.max_risk_per_trade_pct': 'MAX_RISK_PER_TRADE_PCT',
  'capital.max_daily_loss_pct': 'MAX_DAILY_LOSS_PCT',
  'capital.max_lots_per_order': 'MAX_LOTS_PER_ORDER',
  'limits.max_trades_per_day': 'MAX_TRADES_PER_DAY',
  'limits.cooldown_seconds': 'COOLDOWN_SECONDS',
  'limits.max_open_positions': 'MAX_OPEN_POSITIONS',
  'limits.max_positions_per_underlying': 'MAX_POSITIONS_PER_UNDERLYING',
  'limits.max_positions_per_side': 'MAX_POSITIONS_PER_SIDE',
  'limits.allow_opposing_sides': 'ALLOW_OPPOSING_SIDES',
  'limits.enforce_daily_loss': 'ENFORCE_DAILY_LOSS',
  'limits.all_in_risk_policy': 'ALL_IN_RISK_POLICY',
  'limits.broker_kill_switch_on_breach': 'BROKER_KILL_SWITCH_ON_BREACH',
  'contract.min_days_to_expiry': 'MIN_DAYS_TO_EXPIRY',
  'contract.max_days_to_expiry': 'MAX_DAYS_TO_EXPIRY',
  'timing.entry_start': 'ENTRY_START',
  'timing.entry_end': 'ENTRY_END',
  'timing.expiry_day_cutoff': 'EXPIRY_DAY_ENTRY_CUTOFF',
  'timing.flatten_by': 'FLATTEN_BY',
  'strategy.bar_minutes': 'BAR_MINUTES',
  'strategy.supertrend_period': 'SUPERTREND_PERIOD',
  'strategy.supertrend_multiplier': 'SUPERTREND_MULTIPLIER',
  'strategy.ema_fast': 'EMA_FAST',
  'strategy.ema_slow': 'EMA_SLOW',
  'strategy.orb_minutes': 'ORB_MINUTES',
  'strategy.warmup_days': 'WARMUP_DAYS',
  'strategy.max_bars_since_flip': 'MAX_BARS_SINCE_FLIP',
  'strategy.trend_flip_max_bars': 'MAX_BARS_SINCE_FLIP',
  'strategy.min_distance_atr': 'MIN_DISTANCE_ATR',
  'strategy.st_min_distance_atr': 'MIN_DISTANCE_ATR',
  'exits.stop_loss_pct': 'STOP_LOSS_PCT',
  'exits.target_rr': 'TARGET_RR',
  'exits.max_hold_minutes': 'MAX_HOLD_MINUTES',
  'exits.trailing_jump_pct': 'TRAILING_JUMP_PCT',
  'exits.breakeven_at_rr': 'BREAKEVEN_AT_RR',
  'exits.runner_mode': 'RUNNER_MODE',
  'chain_analysis.enabled': 'CHAIN_ANALYSIS_ENABLED',
  'chain_analysis.min_headroom_pts': 'CHAIN_ANALYSIS_MIN_HEADROOM_PTS',
  'context.enabled': 'CONTEXT_FILTER_ENABLED',
  'context.structure_exit': 'CONTEXT_STRUCTURE_EXIT',
};

/** One leaf of the YAML file: where it was written, the environment name it sets, and its value. */
interface YamlEntry {
  readonly path: string;
  readonly envKey: string;
  readonly value: string;
}

function envKeyForYamlPath(path: string): string {
  const mapped = YAML_ENV_MAP[path];
  if (mapped !== undefined) {
    return mapped;
  }
  if (path.startsWith('limits.freeze_quantity.')) {
    return `FREEZE_QTY_${path.slice('limits.freeze_quantity.'.length).toUpperCase()}`;
  }
  return path.toUpperCase().replace(/\./g, '_');
}

export function parseYamlToEnv(content: string): Record<string, string> {
  return Object.fromEntries(parseYamlEntries(content).map((entry) => [entry.envKey, entry.value]));
}

function parseYamlEntries(content: string): YamlEntry[] {
  const parsed = parseYaml(content);
  const result: YamlEntry[] = [];
  if (parsed === null || typeof parsed !== 'object') {
    return result;
  }

  const walk = (node: unknown, path: string): void => {
    if (node === null || node === undefined) {
      return;
    }
    // Reference descriptions in YAML are skipped so they do not pollute the runtime env
    if (path === 'session.postures' || path === 'postures') {
      return;
    }
    if (typeof node === 'object' && !Array.isArray(node)) {
      for (const [key, val] of Object.entries(node as Record<string, unknown>)) {
        walk(val, path ? `${path}.${key}` : key);
      }
      return;
    }
    result.push({ path, envKey: envKeyForYamlPath(path), value: Array.isArray(node) ? node.map(String).join(',') : String(node) });
  };

  walk(parsed, '');
  return result;
}

export function loadYamlConfig(filePath: string): Record<string, string> {
  return Object.fromEntries(readYamlEntries(filePath).map((entry) => [entry.envKey, entry.value]));
}

function readYamlEntries(filePath: string): YamlEntry[] {
  if (!existsSync(filePath)) {
    throw new Error(`Config file not found: ${filePath}`);
  }
  return parseYamlEntries(readFileSync(filePath, 'utf-8'));
}

function resolveConfigPath(env: Env, explicitPath?: string): string | undefined {
  if (explicitPath !== undefined) {
    return explicitPath;
  }
  const fromEnv = optionalText(env, 'CONFIG_FILE') ?? optionalText(env, 'CONFIG_PATH');
  if (fromEnv !== undefined) {
    return fromEnv;
  }
  const args = process.argv;
  const idx = args.findIndex((arg) => arg === '--config' || arg === '-c');
  if (idx !== -1 && idx + 1 < args.length) {
    return args[idx + 1];
  }
  const eq = args.find((arg) => arg.startsWith('--config='));
  return eq?.split('=')[1];
}

/**
 * Parses and validates the full agent configuration. Every invalid or unsafe
 * value throws before any network call; live mode additionally requires an
 * explicit acknowledgement phrase.
 */
export function loadConfig(env: Env = process.env, configPath?: string): AgentConfig {
  const resolvedPath = resolveConfigPath(env, configPath);
  const yamlEntries = resolvedPath === undefined ? [] : readYamlEntries(resolvedPath);
  // Every name the parse below asks for is noted, so a YAML key that sets a name nothing asked for can be refused.
  const namesRead = new Set<string>();
  const merged: Env = { ...env, ...Object.fromEntries(yamlEntries.map((entry) => [entry.envKey, entry.value])) };
  env = new Proxy(merged, {
    get(target, name) {
      if (typeof name === 'string') {
        namesRead.add(name);
      }
      return Reflect.get(target, name) as string | undefined;
    },
  });
  if (optionalText(env, 'EVENT_LOG_PATH') !== undefined) {
    // A single file grew without bound and was read in full at every start. Refuse rather than ignore it.
    throw new Error('EVENT_LOG_PATH was replaced by EVENT_LOG_DIR (daily journal files); unset EVENT_LOG_PATH');
  }
  const modeText = text(env, 'MODE', 'paper').toLowerCase();
  if (!(TRADING_MODES as readonly string[]).includes(modeText)) {
    throw new Error(`MODE must be one of ${TRADING_MODES.join(', ')}, got "${modeText}"`);
  }
  const mode = modeText as TradingMode;
  if (mode === 'live' && text(env, 'LIVE_TRADING_ACK', '') !== LIVE_ACK_PHRASE) {
    throw new Error(`live mode requires LIVE_TRADING_ACK=${LIVE_ACK_PHRASE}`);
  }
  if (mode === 'live' && riskPolicy(env) === 'enforce' && text(env, 'ALL_IN_RISK_LIVE_ACK', '') !== ALL_IN_LIVE_ACK_PHRASE) {
    throw new Error(`live mode with ALL_IN_RISK_POLICY=enforce requires ALL_IN_RISK_LIVE_ACK=${ALL_IN_LIVE_ACK_PHRASE}`);
  }

  const dhanBaseUrl = optionalText(env, 'DHAN_BASE_URL');
  const config: AgentConfig = {
    mode,
    dhan: {
      clientId: text(env, 'DHAN_CLIENT_ID'),
      auth: parseDhanAuth(env),
      baseUrl: dhanBaseUrl,
      tokenCacheDir: optionalText(env, 'DHAN_TOKEN_CACHE_DIR'),
    },
    sandbox: mode === 'sandbox' ? parseSandbox(env, dhanBaseUrl) : undefined,
    underlyings: parseUnderlyings(env),
    capital: {
      // One ATM lot risks premium × STOP_LOSS_PCT × lot size (₹120 × 30% × 65 ≈ ₹2,340). At 1% risk that needs
      // about ₹2.5L of capital; a smaller default would refuse every ATM entry with RISK_BUDGET_TOO_SMALL.
      inr: number(env, 'CAPITAL_INR', 300_000, { min: 1_000, max: 1e12 }),
      maxRiskPerTradePct: number(env, 'MAX_RISK_PER_TRADE_PCT', 1, { min: 0.01, max: 30 }),
      maxDailyLossPct: number(env, 'MAX_DAILY_LOSS_PCT', 3, { min: 0.01, max: 100 }),
      maxOpenPositions: number(env, 'MAX_OPEN_POSITIONS', 1, { min: 1, max: 20, integer: true }),
      maxPositionsPerUnderlying: number(env, 'MAX_POSITIONS_PER_UNDERLYING', 2, { min: 1, max: 10, integer: true }),
      maxPositionsPerSide: number(env, 'MAX_POSITIONS_PER_SIDE', 1, { min: 1, max: 5, integer: true }),
      allowOpposingSides: flag(env, 'ALLOW_OPPOSING_SIDES', true),
      maxTradesPerDay: number(env, 'MAX_TRADES_PER_DAY', 3, { min: 0, max: 1000, integer: true }),
      maxLotsPerOrder: number(env, 'MAX_LOTS_PER_ORDER', 1, { min: 1, max: 1000, integer: true }),
      enforceDailyLoss: flag(env, 'ENFORCE_DAILY_LOSS', true),
      allInRiskPolicy: riskPolicy(env),
    },
    contract: {
      minDaysToExpiry: number(env, 'MIN_DAYS_TO_EXPIRY', 0, { min: 0, max: 60, integer: true }),
      maxDaysToExpiry: number(env, 'MAX_DAYS_TO_EXPIRY', 4, { min: 0, max: 60, integer: true }),
      expiryDayEntryCutoffMinute: minuteOfDay(env, 'EXPIRY_DAY_ENTRY_CUTOFF', '13:30'),
      strikeOffsetSteps: number(env, 'STRIKE_OFFSET_STEPS', 0, { min: -10, max: 10, integer: true }),
      maxSpreadPct: number(env, 'MAX_SPREAD_PCT', 2, { min: 0.01, max: 20 }),
      minOpenInterest: number(env, 'MIN_OPEN_INTEREST', 10_000, { min: 0, max: 1e12, integer: true }),
      minVolume: number(env, 'MIN_VOLUME', 1_000, { min: 0, max: 1e12, integer: true }),
      entryLimitBufferPct: number(env, 'ENTRY_LIMIT_BUFFER_PCT', 1, { min: 0, max: 10 }),
    },
    exits: {
      stopLossPct: number(env, 'STOP_LOSS_PCT', 30, { min: 1, max: 90 }),
      targetRr: number(env, 'TARGET_RR', 2, { min: 0.5, max: 10 }),
      maxHoldMinutes: number(env, 'MAX_HOLD_MINUTES', 20, { min: 1, max: 390, integer: true }),
      flattenByMinute: minuteOfDay(env, 'FLATTEN_BY', '15:05'),
      cooldownSeconds: number(env, 'COOLDOWN_SECONDS', 300, { min: 0, max: 86_400, integer: true }),
      trailingJumpPct: number(env, 'TRAILING_JUMP_PCT', 0, { min: 0, max: 100 }),
      breakevenAtRr: number(env, 'BREAKEVEN_AT_RR', 1, { min: 0, max: 10 }),
      runnerMode: flag(env, 'RUNNER_MODE', false),
    },
    session: {
      entryStartMinute: minuteOfDay(env, 'ENTRY_START', '09:30'),
      entryEndMinute: minuteOfDay(env, 'ENTRY_END', '14:30'),
      initialPosture: parsePosture(env),
    },
    strategy: {
      barMinutes: number(env, 'BAR_MINUTES', 5, { min: 1, max: 60, integer: true }),
      supertrendPeriod: number(env, 'SUPERTREND_PERIOD', 10, { min: 2, max: 100, integer: true }),
      supertrendMultiplier: number(env, 'SUPERTREND_MULTIPLIER', 3, { min: 0.5, max: 10 }),
      emaFast: number(env, 'EMA_FAST', 9, { min: 2, max: 200, integer: true }),
      emaSlow: number(env, 'EMA_SLOW', 21, { min: 3, max: 400, integer: true }),
      orbMinutes: number(env, 'ORB_MINUTES', 15, { min: 5, max: 60, integer: true }),
      warmupDays: number(env, 'WARMUP_DAYS', 5, { min: 1, max: 30, integer: true }),
      enabledStrategies: parseEnabledStrategies(env),
      maxBarsSinceFlip: number(env, 'MAX_BARS_SINCE_FLIP', 3, { min: 0, max: 50, integer: true }),
      minDistanceAtr: number(env, 'MIN_DISTANCE_ATR', 0.5, { min: 0, max: 20 }),
    },
    chainAnalysis: {
      enabled: flag(env, 'CHAIN_ANALYSIS_ENABLED', false),
      minHeadroomPts: number(env, 'CHAIN_ANALYSIS_MIN_HEADROOM_PTS', 15, { min: 0, max: 1000 }),
    },
    context: {
      enabled: flag(env, 'CONTEXT_FILTER_ENABLED', false),
      structureExit: flag(env, 'CONTEXT_STRUCTURE_EXIT', false),
    },
    feed: {
      staleMs: number(env, 'FEED_STALE_MS', 5_000, { min: 500, max: 60_000, integer: true }),
      istShiftedTimestamps: flag(env, 'DHAN_EPOCH_IST_SHIFTED', false),
      feedIstShifted: flag(env, 'DHAN_FEED_IST_SHIFTED', true),
      marketFeedMode: parseMarketFeedMode(env),
    },
    paper: {
      ...parsePaperBackend(env),
      // Paper exits fill at the last price, but a real SELL meets the bid: about half the spread on liquid ATM index
      // options. Zero made paper results look better than live.
      slippageBps: number(env, 'PAPER_SLIPPAGE_BPS', 25, { min: 0, max: 500 }),
    },
    llm: {
      enabled: flag(env, 'LLM_ADVISOR', false),
      host: text(env, 'OLLAMA_HOST', 'http://127.0.0.1:11434'),
      model: optionalText(env, 'OLLAMA_MODEL'),
      apiKey: optionalText(env, 'OLLAMA_API_KEY'),
      timeoutMs: number(env, 'LLM_TIMEOUT_MS', 8_000, { min: 500, max: 60_000, integer: true }),
    },
    ops: {
      eventLogDir: text(env, 'EVENT_LOG_DIR', 'data/journal'),
      brokerKillSwitchOnBreach: flag(env, 'BROKER_KILL_SWITCH_ON_BREACH', true),
      stalePositionGraceMs: number(env, 'STALE_POSITION_GRACE_MS', 30_000, { min: 5_000, max: 600_000, integer: true }),
      brokerPnlExit: flag(env, 'BROKER_PNL_EXIT', false),
      reconcileIntervalMs: number(env, 'RECONCILE_INTERVAL_MS', 5_000, { min: 1_000, max: 60_000, integer: true }),
      orderTimeoutMs: number(env, 'ORDER_TIMEOUT_MS', 30_000, { min: 1_000, max: 300_000, integer: true }),
      alertWebhookUrl: parseAlertWebhookUrl(env),
      telegram: parseTelegramConfig(env),
    },
    persistence: parsePersistence(env, mode),
  };

  validateCrossFields(config);
  // A misspelt key (max_risk_per_trade_pc) used to set a name nothing reads, and the limit silently kept its default.
  const unread = yamlEntries.filter((entry) => !namesRead.has(entry.envKey));
  if (unread.length > 0) {
    throw new Error(
      `${resolvedPath}: ${unread.map((entry) => `"${entry.path}"`).join(', ')} ${unread.length === 1 ? 'is' : 'are'} not read in this configuration. Check the spelling, or remove ${unread.length === 1 ? 'it' : 'them'}`,
    );
  }
  return config;
}

/**
 * Sandbox order credentials. Client id and token are required together. The base URL is optional, and when set it
 * must be https and must not be the production host: a sandbox run that quietly sent orders to production would be
 * the worst failure this mode can have.
 */
function parseSandbox(env: Env, dhanBaseUrl: string | undefined): SandboxConfig {
  const clientId = optionalText(env, 'DHAN_SANDBOX_CLIENT_ID');
  const accessToken = optionalText(env, 'DHAN_SANDBOX_ACCESS_TOKEN');
  if (clientId === undefined || accessToken === undefined) {
    throw new Error('sandbox mode requires DHAN_SANDBOX_CLIENT_ID and DHAN_SANDBOX_ACCESS_TOKEN');
  }
  const baseUrl = optionalText(env, 'DHAN_SANDBOX_BASE_URL');
  if (baseUrl !== undefined) {
    let host: string;
    try {
      const url = new URL(baseUrl);
      if (url.protocol !== 'https:') {
        throw new Error('not https');
      }
      host = url.hostname.toLowerCase();
    } catch {
      throw new Error('DHAN_SANDBOX_BASE_URL must be an https URL');
    }
    // DHAN_BASE_URL is validated by the SDK when the client is built. Here it only needs to be compared against.
    const marketDataHost = dhanBaseUrl === undefined ? undefined : hostOfUrl(dhanBaseUrl);
    if (host === PRODUCTION_DHAN_HOST || host === marketDataHost) {
      throw new Error(`DHAN_SANDBOX_BASE_URL points at a production host (${host}); sandbox orders must go to the sandbox host`);
    }
  }
  return { clientId, accessToken, baseUrl };
}

function hostOfUrl(url: string): string | undefined {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return undefined;
  }
}

/**
 * Paper order venue. `postgres` simulates fills in the local database. `exchange` sends paper orders to a running
 * paper_exchange server, which keeps the account, margin and ledger on its side. Either way, market data is live.
 */
function parsePaperBackend(env: Env): { backend: 'postgres' | 'exchange'; exchange: PaperExchangeConfig | undefined } {
  const raw = (optionalText(env, 'PAPER_BACKEND') ?? 'postgres').toLowerCase();
  if (raw === 'postgres') {
    return { backend: 'postgres', exchange: undefined };
  }
  if (raw !== 'exchange') {
    throw new Error(`PAPER_BACKEND must be "postgres" or "exchange", got "${raw}"`);
  }
  const url = optionalText(env, 'PAPER_EXCHANGE_URL');
  const apiKey = optionalText(env, 'PAPER_EXCHANGE_API_KEY');
  if (url === undefined || apiKey === undefined) {
    throw new Error('PAPER_BACKEND=exchange requires PAPER_EXCHANGE_URL and PAPER_EXCHANGE_API_KEY');
  }
  requireHttpsOrLoopback('PAPER_EXCHANGE_URL', url);
  const accountId = optionalText(env, 'PAPER_EXCHANGE_ACCOUNT_ID') ?? text(env, 'DHAN_CLIENT_ID');
  return {
    backend: 'exchange',
    exchange: { url: url.replace(/\/+$/, ''), apiKey, accountId },
  };
}

/**
 * Brings persistence settings into the config. Live and sandbox need the ledger (which holds the trading lease)
 * and Redis. Paper needs the ledger too, because its wallet, orders and positions are stored there. Redis is
 * optional for paper.
 */
function parsePersistence(env: Env, mode: TradingMode): AgentConfig['persistence'] {
  const databaseUrl = optionalText(env, 'DATABASE_URL');
  const redisUrl = optionalText(env, 'REDIS_URL');
  if (databaseUrl !== undefined) {
    validatePostgresUrl(databaseUrl);
  }
  if (redisUrl !== undefined) {
    parseRedisUrl(redisUrl);
  }
  if (mode !== 'paper' && (databaseUrl === undefined || redisUrl === undefined)) {
    throw new Error(`${mode} mode requires DATABASE_URL (trading ledger and lease) and REDIS_URL (rate gate and cache)`);
  }
  if (mode === 'paper' && databaseUrl === undefined) {
    throw new Error('paper mode requires DATABASE_URL (the paper wallet, orders and positions are stored there)');
  }
  const sharedRateLimitKey = optionalText(env, 'DHAN_SHARED_RATE_LIMIT_KEY');
  if (sharedRateLimitKey !== undefined && redisUrl === undefined) {
    throw new Error('DHAN_SHARED_RATE_LIMIT_KEY requires REDIS_URL (the shared gate lives in Redis)');
  }
  return {
    databaseUrl,
    redisUrl,
    sharedRateLimitKey,
    instanceId: optionalText(env, 'INSTANCE_ID'),
    leaseTtlMs: number(env, 'LEASE_TTL_MS', 30_000, { min: 5_000, max: 120_000, integer: true }),
    postgresMaxConnections: number(env, 'POSTGRES_MAX_CONNECTIONS', 5, { min: 1, max: 50, integer: true }),
  };
}

function parseAlertWebhookUrl(env: Env): string | undefined {
  const url = optionalText(env, 'ALERT_WEBHOOK_URL');
  if (url !== undefined && !url.startsWith('https://')) {
    throw new Error('ALERT_WEBHOOK_URL must be an https URL');
  }
  return url;
}

function parseTelegramConfig(env: Env): TelegramConfig | undefined {
  const botToken = optionalText(env, 'TELEGRAM_BOT_TOKEN');
  const chatId = optionalText(env, 'TELEGRAM_CHAT_ID');
  if (botToken === undefined && chatId === undefined) {
    return undefined;
  }
  if (botToken === undefined || chatId === undefined) {
    throw new Error('Telegram alerts require both TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID');
  }
  return { botToken, chatId };
}

/**
 * A fingerprint of the trading-relevant configuration, recorded on every run so a ledger row can be
 * tied to the settings that produced it. Secrets and connection strings are excluded by construction:
 * this function only reads the trading sections.
 */
export function configFingerprint(config: AgentConfig): string {
  const { mode, underlyings, capital, contract, exits, session, strategy, feed, paper, chainAnalysis, context } = config;
  return createHash('sha256')
    .update(JSON.stringify({ mode, underlyings, capital, contract, exits, session, strategy, feed, paper, chainAnalysis, context }))
    .digest('hex');
}

function validateCrossFields(config: AgentConfig): void {
  const { session, exits, strategy, contract } = config;
  if (config.ops.stalePositionGraceMs < config.feed.staleMs) {
    throw new Error('STALE_POSITION_GRACE_MS must be at least FEED_STALE_MS: the grace period starts after the stale threshold');
  }
  if (!(session.entryStartMinute < session.entryEndMinute)) {
    throw new Error('ENTRY_START must be earlier than ENTRY_END');
  }
  if (!(session.entryEndMinute <= exits.flattenByMinute)) {
    throw new Error('FLATTEN_BY must not be earlier than ENTRY_END');
  }
  // Dhan squares off intraday F&O itself from about 15:18 IST (its pages say 15:18 to 15:25), with a charge and
  // at its own price. The agent's own flatten must come first.
  if (!(exits.flattenByMinute <= LATEST_FLATTEN_MINUTE)) {
    throw new Error('FLATTEN_BY must be 15:15 IST or earlier, before Dhan auto-squares intraday positions');
  }
  if (![1, 5, 15, 25, 60].includes(strategy.barMinutes)) {
    throw new Error('BAR_MINUTES must be one of 1, 5, 15, 25, 60 (Dhan intraday chart intervals)');
  }
  // The opening range is built from whole bars; 15 minutes of 25-minute bars is no range at all.
  if (strategy.orbMinutes % strategy.barMinutes !== 0) {
    throw new Error(`ORB_MINUTES (${strategy.orbMinutes}) must be a whole number of BAR_MINUTES (${strategy.barMinutes})`);
  }
  if (!(strategy.emaFast < strategy.emaSlow)) {
    throw new Error('EMA_FAST must be shorter than EMA_SLOW');
  }
  if (!(contract.expiryDayEntryCutoffMinute >= session.entryStartMinute)) {
    throw new Error('EXPIRY_DAY_ENTRY_CUTOFF must not precede ENTRY_START');
  }
  if (config.capital.maxRiskPerTradePct > config.capital.maxDailyLossPct) {
    throw new Error('MAX_RISK_PER_TRADE_PCT must not exceed MAX_DAILY_LOSS_PCT');
  }
  if (config.mode === 'live' && config.capital.maxRiskPerTradePct > LIVE_MAX_RISK_PER_TRADE_PCT) {
    throw new Error(`live mode caps MAX_RISK_PER_TRADE_PCT at ${LIVE_MAX_RISK_PER_TRADE_PCT}, got ${config.capital.maxRiskPerTradePct}`);
  }
  if (config.mode === 'live' && config.capital.maxDailyLossPct > LIVE_MAX_DAILY_LOSS_PCT) {
    throw new Error(`live mode caps MAX_DAILY_LOSS_PCT at ${LIVE_MAX_DAILY_LOSS_PCT}, got ${config.capital.maxDailyLossPct}`);
  }
  if (config.mode === 'live' && !config.capital.enforceDailyLoss) {
    throw new Error('live mode requires ENFORCE_DAILY_LOSS=true; daily loss brake cannot be disabled with real money');
  }
}
