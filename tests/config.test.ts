import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LIVE_ACK_PHRASE, loadConfig } from '../src/config.js';

const SANDBOX = {
  DHAN_SANDBOX_CLIENT_ID: 'SANDBOX-CLIENT',
  DHAN_SANDBOX_ACCESS_TOKEN: 'sandbox-token',
  DHAN_SANDBOX_BASE_URL: 'https://sandbox.example.test/v2',
};

const BASE = {
  DHAN_CLIENT_ID: '1100000001',
  DHAN_ACCESS_TOKEN: 'token',
  DATABASE_URL: 'postgres://paper.test.invalid/agent',
  REDIS_URL: 'redis://cache.test.invalid:6379/0',
};

describe('loadConfig', () => {
  it('loads paper-mode defaults that trade NIFTY with one lot and a 1% risk budget', () => {
    const config = loadConfig(BASE);
    assert.equal(config.mode, 'paper');
    assert.deepEqual(config.underlyings, [{ symbol: 'NIFTY', optionSegment: 'NSE_FNO' }]);
    assert.equal(config.capital.maxRiskPerTradePct, 1);
    assert.equal(config.llm.enabled, false);
    assert.equal(config.feed.istShiftedTimestamps, false);
    assert.equal(config.feed.feedIstShifted, true, 'Dhan stamps WebSocket LTT in IST wall-clock');
  });

  it('requires Dhan credentials even in paper mode, because market data is live', () => {
    assert.throws(() => loadConfig({}), /DHAN_CLIENT_ID is required/);
  });

  it('refuses live mode without the explicit acknowledgement phrase', () => {
    assert.throws(() => loadConfig({ ...BASE, MODE: 'live' }), /LIVE_TRADING_ACK/);
    assert.throws(() => loadConfig({ ...BASE, MODE: 'live', LIVE_TRADING_ACK: 'yes' }), /LIVE_TRADING_ACK/);
    const live = { ...BASE, MODE: 'live', DATABASE_URL: 'postgres://ledger.internal/agent', REDIS_URL: 'redis://cache.internal:6379/0' };
    assert.equal(loadConfig({ ...live, LIVE_TRADING_ACK: LIVE_ACK_PHRASE }).mode, 'live');
  });

  it('refuses live risk above the real-money ceilings, whatever .env says', () => {
    const live = { ...BASE, MODE: 'live', LIVE_TRADING_ACK: LIVE_ACK_PHRASE, DATABASE_URL: 'postgres://ledger.internal/agent', REDIS_URL: 'redis://cache.internal:6379/0' };
    assert.throws(() => loadConfig({ ...live, MAX_RISK_PER_TRADE_PCT: '30', MAX_DAILY_LOSS_PCT: '50' }), /caps MAX_RISK_PER_TRADE_PCT at 2/);
    assert.throws(() => loadConfig({ ...live, MAX_DAILY_LOSS_PCT: '10' }), /caps MAX_DAILY_LOSS_PCT at 6/);
    assert.throws(() => loadConfig({ ...live, MAX_RISK_PER_TRADE_PCT: '2', MAX_DAILY_LOSS_PCT: '6', ENFORCE_DAILY_LOSS: 'off' }), /requires ENFORCE_DAILY_LOSS=true/);
    assert.equal(loadConfig({ ...live, MAX_RISK_PER_TRADE_PCT: '2', MAX_DAILY_LOSS_PCT: '6' }).capital.maxRiskPerTradePct, 2);
    assert.equal(loadConfig({ ...BASE, MAX_RISK_PER_TRADE_PCT: '30', MAX_DAILY_LOSS_PCT: '50' }).capital.maxRiskPerTradePct, 30, 'paper is not capped');
    assert.equal(loadConfig({ ...BASE, ENFORCE_DAILY_LOSS: 'off' }).capital.enforceDailyLoss, false);
  });

  it('accepts exactly three modes: live, sandbox and paper', () => {
    const sandbox = { ...BASE, MODE: 'sandbox', ...SANDBOX };
    assert.equal(loadConfig({ ...BASE, MODE: 'paper' }).mode, 'paper');
    assert.equal(loadConfig({ ...BASE, MODE: 'PAPER' }).mode, 'paper');
    assert.equal(loadConfig(sandbox).mode, 'sandbox');
    assert.throws(() => loadConfig({ ...BASE, MODE: 'backtest' }), /MODE must be one of live, sandbox, paper/);
  });

  it('gives sandbox its own order credentials and keeps market-data credentials separate', () => {
    const config = loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX });
    assert.deepEqual(config.sandbox, { clientId: 'SANDBOX-CLIENT', accessToken: 'sandbox-token', baseUrl: 'https://sandbox.example.test/v2' });
    assert.equal(config.dhan.clientId, '1100000001', 'market data keeps the live client id');
    assert.equal(config.sandbox === undefined, false);
    assert.equal(loadConfig(BASE).sandbox, undefined, 'only sandbox mode carries sandbox credentials');
  });

  it('refuses sandbox mode without all three sandbox settings, and never names a token in the error', () => {
    assert.throws(() => loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX, DHAN_SANDBOX_ACCESS_TOKEN: undefined }), /DHAN_SANDBOX_ACCESS_TOKEN/);
    assert.equal(loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX, DHAN_SANDBOX_BASE_URL: undefined }).sandbox?.baseUrl, undefined, 'the SDK default host is used');
    assert.throws(
      () => loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX, DHAN_SANDBOX_BASE_URL: 'http://sandbox.example.test/v2' }),
      /must be an https URL/,
    );
  });

  it('refuses a sandbox base URL that is the production host, so sandbox orders cannot reach production', () => {
    assert.throws(
      () => loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX, DHAN_SANDBOX_BASE_URL: 'https://api.dhan.co/v2' }),
      /production host/,
    );
    assert.throws(
      () => loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX, DHAN_BASE_URL: 'https://gateway.example.test', DHAN_SANDBOX_BASE_URL: 'https://gateway.example.test/sandbox' }),
      /production host/,
    );
  });

  it('needs the ledger and Redis for sandbox, as for live, and does not need the live acknowledgement', () => {
    const noStores = { ...BASE, DATABASE_URL: undefined, MODE: 'sandbox', ...SANDBOX };
    assert.throws(() => loadConfig(noStores), /sandbox mode requires DATABASE_URL.*REDIS_URL/);
    assert.equal(loadConfig({ ...BASE, MODE: 'sandbox', ...SANDBOX }).mode, 'sandbox');
  });

  it('selects the paper venue: the PostgreSQL venue by default, or a paper_exchange server', () => {
    assert.equal(loadConfig({ ...BASE, MODE: 'paper' }).paper.backend, 'postgres');
    assert.equal(loadConfig({ ...BASE, MODE: 'paper' }).paper.exchange, undefined);
    assert.throws(() => loadConfig({ ...BASE, MODE: 'paper', PAPER_BACKEND: 'memory' }), /must be "postgres" or "exchange"/);
  });

  it('requires the paper_exchange URL and API key when that backend is chosen, and never echoes the key', () => {
    assert.throws(() => loadConfig({ ...BASE, MODE: 'paper', PAPER_BACKEND: 'exchange' }), /PAPER_EXCHANGE_URL and PAPER_EXCHANGE_API_KEY/);
    assert.throws(
      () => {
        try {
          loadConfig({ ...BASE, MODE: 'paper', PAPER_BACKEND: 'exchange', PAPER_EXCHANGE_URL: 'not a url', PAPER_EXCHANGE_API_KEY: 'k-secret' });
        } catch (error) {
          assert.ok(!(error as Error).message.includes('k-secret'));
          throw error;
        }
      },
      /must be a URL/,
    );
  });

  it('accepts paper_exchange over https, or over http on loopback only, and defaults the account to the Dhan client id', () => {
    const exchange = { ...BASE, MODE: 'paper', PAPER_BACKEND: 'exchange', PAPER_EXCHANGE_API_KEY: 'k' };
    const local = loadConfig({ ...exchange, PAPER_EXCHANGE_URL: 'http://127.0.0.1:3100/' });
    assert.deepEqual(local.paper.exchange, { url: 'http://127.0.0.1:3100', apiKey: 'k', accountId: BASE.DHAN_CLIENT_ID });
    assert.equal(loadConfig({ ...exchange, PAPER_EXCHANGE_URL: 'https://paper.example.test' }).paper.backend, 'exchange');
    assert.throws(() => loadConfig({ ...exchange, PAPER_EXCHANGE_URL: 'http://paper.example.test' }), /https, or http on loopback/);
    assert.equal(loadConfig({ ...exchange, PAPER_EXCHANGE_URL: 'http://127.0.0.1:3100', PAPER_EXCHANGE_ACCOUNT_ID: 'paper-1' }).paper.exchange?.accountId, 'paper-1');
  });

  it('rejects unknown modes and unsupported underlyings', () => {
    assert.throws(() => loadConfig({ ...BASE, MODE: 'sim' }), /MODE must be/);
    assert.throws(() => loadConfig({ ...BASE, UNDERLYINGS: 'BTC' }), /not a supported index/);
  });

  it('maps SENSEX to the BSE derivatives segment and de-duplicates the list', () => {
    const config = loadConfig({ ...BASE, UNDERLYINGS: 'nifty, sensex, NIFTY' });
    assert.deepEqual(config.underlyings, [
      { symbol: 'NIFTY', optionSegment: 'NSE_FNO' },
      { symbol: 'SENSEX', optionSegment: 'BSE_FNO' },
    ]);
  });

  it('rejects numbers outside their bounds and non-integers where integers are required', () => {
    assert.throws(() => loadConfig({ ...BASE, MAX_RISK_PER_TRADE_PCT: '50' }), /within/);
    assert.throws(() => loadConfig({ ...BASE, MAX_TRADES_PER_DAY: '2.5' }), /integer/);
    assert.throws(() => loadConfig({ ...BASE, CAPITAL_INR: 'lots' }), /must be a number/);
  });

  it('rejects flags that are not explicit booleans', () => {
    assert.equal(loadConfig(BASE).feed.marketFeedMode, 'ticker');
    assert.throws(() => loadConfig({ ...BASE, DHAN_MARKET_FEED_MODE: 'depth' }), /DHAN_MARKET_FEED_MODE/);
    assert.throws(() => loadConfig({ ...BASE, LLM_ADVISOR: 'maybe' }), /boolean flag/);
    assert.equal(loadConfig({ ...BASE, LLM_ADVISOR: 'on' }).llm.enabled, true);
  });

  it('names a decision model only when asked, and bounds the ENTER threshold', () => {
    assert.equal(loadConfig(BASE).llm.decisionModel, undefined);
    assert.equal(loadConfig(BASE).llm.decisionEnterThreshold, 0.5);
    const decision = loadConfig({ ...BASE, OLLAMA_DECISION_MODEL: 'clef', LLM_DECISION_ENTER_THRESHOLD: '0.7' }).llm;
    assert.equal(decision.decisionModel, 'clef');
    assert.equal(decision.decisionEnterThreshold, 0.7);
    assert.throws(() => loadConfig({ ...BASE, LLM_DECISION_ENTER_THRESHOLD: '1.5' }), /LLM_DECISION_ENTER_THRESHOLD/);
    assert.throws(() => loadConfig({ ...BASE, LLM_DECISION_ENTER_THRESHOLD: '0' }), /LLM_DECISION_ENTER_THRESHOLD/);
    assert.throws(() => loadConfig({ ...BASE, LLM_DECISION_ENTER_THRESHOLD: 'likely' }), /LLM_DECISION_ENTER_THRESHOLD/);
  });

  it('rejects bar sizes that Dhan intraday charts do not offer', () => {
    assert.throws(() => loadConfig({ ...BASE, BAR_MINUTES: '3' }), /BAR_MINUTES/);
    assert.equal(loadConfig({ ...BASE, BAR_MINUTES: '15' }).strategy.barMinutes, 15);
    assert.throws(() => loadConfig({ ...BASE, BAR_MINUTES: '25' }), /ORB_MINUTES/, 'a 15-minute range cannot be built from 25-minute bars');
    assert.throws(() => loadConfig({ ...BASE, BAR_MINUTES: '15', ORB_MINUTES: '20' }), /ORB_MINUTES/);
  });

  it('enforces the session ordering: entry window, then flatten, before the close', () => {
    assert.throws(() => loadConfig({ ...BASE, ENTRY_START: '10:00', ENTRY_END: '09:30' }), /ENTRY_START/);
    assert.throws(() => loadConfig({ ...BASE, ENTRY_END: '15:10', FLATTEN_BY: '15:05' }), /FLATTEN_BY/);
    assert.equal(loadConfig(BASE).paper.slippageBps, 25, 'paper exits pay about half the spread by default');
    assert.throws(() => loadConfig({ ...BASE, FLATTEN_BY: '15:45' }), /15:15/);
    assert.throws(() => loadConfig({ ...BASE, FLATTEN_BY: '15:16' }), /before Dhan auto-squares/);
    assert.equal(loadConfig({ ...BASE, FLATTEN_BY: '15:15' }).exits.flattenByMinute, 15 * 60 + 15);
  });

  it('never lets a single trade risk more than the daily loss budget allows', () => {
    assert.throws(
      () => loadConfig({ ...BASE, MAX_RISK_PER_TRADE_PCT: '5', MAX_DAILY_LOSS_PCT: '3' }),
      /must not exceed/,
    );
  });
});

describe('loadConfig shared rate limit', () => {
  const WITH_REDIS = { ...BASE, REDIS_URL: 'redis://127.0.0.1:6379/0' };

  it('is off unless asked for, so the agent keeps its own per-account gate', () => {
    assert.equal(loadConfig(WITH_REDIS).persistence.sharedRateLimitKey, undefined);
  });

  it('takes the key the Rails app reserves slots under', () => {
    const config = loadConfig({ ...WITH_REDIS, DHAN_SHARED_RATE_LIMIT_KEY: 'dhan:rate_limit:option_chain' });
    assert.equal(config.persistence.sharedRateLimitKey, 'dhan:rate_limit:option_chain');
  });

  it('needs Redis, because the other process can only be reached through it', () => {
    const { REDIS_URL: _redis, ...withoutRedis } = BASE;
    assert.throws(() => loadConfig({ ...withoutRedis, DHAN_SHARED_RATE_LIMIT_KEY: 'dhan:rate_limit:option_chain' }), /DHAN_SHARED_RATE_LIMIT_KEY requires REDIS_URL/);
  });
});

describe('loadConfig Dhan authentication', () => {
  const OTP = { DHAN_CLIENT_ID: '1100000001', DHAN_PIN: '4321', DHAN_TOTP_SECRET: 'JBSWY3DPEHPK3PXP', DATABASE_URL: 'postgres://paper.test.invalid/agent' };

  it('uses a static access token when no OTP variable is set', () => {
    assert.deepEqual(loadConfig(BASE).dhan.auth, { kind: 'static', accessToken: 'token' });
  });

  it('selects PIN + TOTP login without requiring a static access token', () => {
    assert.deepEqual(loadConfig(OTP).dhan.auth, { kind: 'otp', pin: '4321', totpSecret: 'JBSWY3DPEHPK3PXP' });
  });

  it('normalises a TOTP secret copied from an authenticator app (spaces, dashes, lowercase, padding)', () => {
    const config = loadConfig({ ...OTP, DHAN_TOTP_SECRET: 'jbsw y3dp-ehpk3pxp==' });
    assert.deepEqual(config.dhan.auth, { kind: 'otp', pin: '4321', totpSecret: 'JBSWY3DPEHPK3PXP' });
  });

  it('requires DHAN_PIN and DHAN_TOTP_SECRET together', () => {
    assert.throws(() => loadConfig({ DHAN_CLIENT_ID: '1', DHAN_PIN: '4321' }), /must be set together/);
    assert.throws(() => loadConfig({ DHAN_CLIENT_ID: '1', DHAN_TOTP_SECRET: 'JBSWY3DPEHPK3PXP' }), /must be set together/);
  });

  it('refuses a static token alongside OTP variables, so the token source is never ambiguous', () => {
    assert.throws(() => loadConfig({ ...OTP, DHAN_ACCESS_TOKEN: 'stale' }), /conflicts with DHAN_PIN/);
  });

  it('rejects a TOTP secret that is not base32, without echoing it', () => {
    const bad = 'NOT-BASE32!0189';
    assert.throws(() => loadConfig({ ...OTP, DHAN_TOTP_SECRET: bad }), (error: Error) => {
      assert.match(error.message, /base32/);
      assert.equal(error.message.includes(bad), false);
      return true;
    });
  });

  it('names the accepted credential sources when neither a token nor OTP variables are set', () => {
    assert.throws(() => loadConfig({ DHAN_CLIENT_ID: '1' }), /DHAN_ACCESS_TOKEN is required unless DHAN_PIN/);
  });

  it('still requires DHAN_CLIENT_ID for OTP login', () => {
    assert.throws(() => loadConfig({ DHAN_PIN: '4321', DHAN_TOTP_SECRET: 'JBSWY3DPEHPK3PXP' }), /DHAN_CLIENT_ID is required/);
  });

  describe('token authority', () => {
    const AUTHORITY = {
      DHAN_CLIENT_ID: '1100000001',
      DHAN_TOKEN_AUTHORITY_URL: 'http://127.0.0.1:3011/api/dhan/token',
      DHAN_TOKEN_AUTHORITY_KEY: 'operator-key',
      DATABASE_URL: 'postgres://paper.test.invalid/agent',
    };

    it('selects the authority as the token source, so this process never logs in', () => {
      assert.deepEqual(loadConfig(AUTHORITY).dhan.auth, {
        kind: 'authority',
        url: 'http://127.0.0.1:3011/api/dhan/token',
        key: 'operator-key',
      });
    });

    it('requires the URL and the key together', () => {
      const { DHAN_TOKEN_AUTHORITY_KEY: _key, ...urlOnly } = AUTHORITY;
      assert.throws(() => loadConfig(urlOnly), /DHAN_TOKEN_AUTHORITY_URL and DHAN_TOKEN_AUTHORITY_KEY must be set together/);
    });

    it('refuses a second token source alongside the authority, because two logins invalidate each other', () => {
      assert.throws(() => loadConfig({ ...AUTHORITY, DHAN_ACCESS_TOKEN: 'stale' }), /DHAN_TOKEN_AUTHORITY_URL conflicts with/);
      assert.throws(
        () => loadConfig({ ...AUTHORITY, DHAN_PIN: '4321', DHAN_TOTP_SECRET: 'JBSWY3DPEHPK3PXP' }),
        /DHAN_TOKEN_AUTHORITY_URL conflicts with/,
      );
    });

    it('accepts plain http to a host the operator names as trusted, such as a container on a private network', () => {
      const config = loadConfig({
        ...AUTHORITY,
        DHAN_TOKEN_AUTHORITY_URL: 'http://asa-web:3011/api/dhan/token',
        DHAN_TOKEN_AUTHORITY_TRUSTED_HOSTS: 'asa-web',
      });

      assert.deepEqual(config.dhan.auth, { kind: 'authority', url: 'http://asa-web:3011/api/dhan/token', key: 'operator-key' });
    });

    it('matches trusted hosts exactly and ignores case, so a lookalike host is still refused', () => {
      assert.doesNotThrow(() =>
        loadConfig({ ...AUTHORITY, DHAN_TOKEN_AUTHORITY_URL: 'http://ASA-Web:3011/x', DHAN_TOKEN_AUTHORITY_TRUSTED_HOSTS: ' other , asa-web ' }),
      );
      assert.throws(
        () => loadConfig({ ...AUTHORITY, DHAN_TOKEN_AUTHORITY_URL: 'http://asa-web.evil.example/x', DHAN_TOKEN_AUTHORITY_TRUSTED_HOSTS: 'asa-web' }),
        /must be https, or http on loopback or a trusted host/,
      );
    });

    it('accepts https, or http only on loopback, since the reply carries a live-order token', () => {
      assert.throws(() => loadConfig({ ...AUTHORITY, DHAN_TOKEN_AUTHORITY_URL: 'http://rails.internal/api/dhan/token' }), /must be https, or http on loopback or a trusted host/);
      assert.doesNotThrow(() => loadConfig({ ...AUTHORITY, DHAN_TOKEN_AUTHORITY_URL: 'https://rails.internal/api/dhan/token' }));
    });
  });
});

describe('loadConfig journal location', () => {
  it('defaults to a directory of daily journal files', () => {
    assert.equal(loadConfig(BASE).ops.eventLogDir, 'data/journal');
  });

  it('refuses the removed single-file EVENT_LOG_PATH instead of ignoring it', () => {
    assert.throws(() => loadConfig({ ...BASE, EVENT_LOG_PATH: 'data/events.jsonl' }), /replaced by EVENT_LOG_DIR/);
  });
});

describe('loadConfig posture and YAML loading', () => {
  it('defaults initial posture to aligned', () => {
    assert.equal(loadConfig(BASE).session.initialPosture, 'aligned');
  });

  it('accepts configured initial posture from env', () => {
    assert.equal(loadConfig({ ...BASE, STRATEGY_POSTURE: 'scout' }).session.initialPosture, 'scout');
    assert.equal(loadConfig({ ...BASE, POSTURE: 'confirmed' }).session.initialPosture, 'confirmed');
  });

  it('rejects unknown posture values', () => {
    assert.throws(() => loadConfig({ ...BASE, STRATEGY_POSTURE: 'yolo' }), /STRATEGY_POSTURE must be one of/);
  });

  it('loads paper YAML configuration and applies scout posture, 10L capital, and daily risk brakes', () => {
    const config = loadConfig(BASE, 'config.paper.yml');
    assert.deepEqual(config.underlyings.map((u) => u.symbol), ['NIFTY', 'BANKNIFTY', 'SENSEX']);
    assert.equal(config.session.initialPosture, 'scout');
    assert.equal(config.capital.inr, 1_000_000);
    assert.equal(config.capital.maxRiskPerTradePct, 2.0);
    assert.equal(config.capital.maxDailyLossPct, 4.0);
    assert.equal(config.capital.maxLotsPerOrder, 15);
    assert.equal(config.capital.maxTradesPerDay, 0);
    assert.equal(config.exits.cooldownSeconds, 900);
    assert.equal(config.capital.maxOpenPositions, 6);
    assert.equal(config.capital.maxPositionsPerSide, 1);
    assert.equal(config.session.entryStartMinute, 9 * 60 + 15);
    assert.equal(config.session.entryEndMinute, 14 * 60);
    assert.equal(config.exits.flattenByMinute, 15 * 60 + 15);
    assert.equal(config.ops.brokerKillSwitchOnBreach, false);
    assert.equal(config.strategy.maxBarsSinceFlip, 4);
    assert.equal(config.strategy.minDistanceAtr, 0.2);
    assert.equal(config.contract.minDaysToExpiry, 0);
    assert.equal(config.contract.maxDaysToExpiry, 6);
    assert.equal(config.chainAnalysis.enabled, true);
    assert.equal(config.chainAnalysis.minHeadroomPts, 15);
  });
});

describe('YAML keys the agent does not read', () => {
  function yamlFile(body: string): string {
    const path = join(mkdtempSync(join(tmpdir(), 'agent-config-')), 'config.yml');
    writeFileSync(path, body);
    return path;
  }

  it('should refuse a misspelt risk key instead of falling back to the default', () => {
    const path = yamlFile('capital:\n  max_risk_per_trade_pc: 0.5\n');
    assert.throws(() => loadConfig(BASE, path), /capital\.max_risk_per_trade_pc/);
  });

  it('should refuse a key under an unknown section', () => {
    assert.throws(() => loadConfig(BASE, yamlFile('risk:\n  stop_loss_pct: 20\n')), /risk\.stop_loss_pct/);
  });

  it('should accept a key that maps onto an environment name the agent reads', () => {
    const config = loadConfig(BASE, yamlFile('paper:\n  slippage_bps: 40\ncapital:\n  max_risk_per_trade_pct: 0.5\n'));
    assert.equal(config.paper.slippageBps, 40);
    assert.equal(config.capital.maxRiskPerTradePct, 0.5);
  });
});

describe('exchange freeze quantity', () => {
  it('should be unset unless the operator gives one for the underlying', () => {
    assert.equal(loadConfig(BASE).underlyings[0]?.freezeQuantity, undefined);
  });

  it('should read FREEZE_QTY_<SYMBOL> for each configured underlying', () => {
    const config = loadConfig({ ...BASE, UNDERLYINGS: 'NIFTY,SENSEX', FREEZE_QTY_NIFTY: '1800' });
    assert.deepEqual(config.underlyings.map((u) => u.freezeQuantity), [1800, undefined]);
  });

  it('should refuse a freeze quantity that is not a positive whole number', () => {
    assert.throws(() => loadConfig({ ...BASE, FREEZE_QTY_NIFTY: '0' }), /FREEZE_QTY_NIFTY/);
    assert.throws(() => loadConfig({ ...BASE, FREEZE_QTY_NIFTY: '12.5' }), /FREEZE_QTY_NIFTY/);
  });
});

describe('all-in risk budget flag (OTA-311)', () => {
  it('is off unless ALL_IN_RISK_BUDGET is set, so live sizing is unchanged by default', () => {
    assert.equal(loadConfig(BASE).capital.allInRiskPolicy, 'off');
    assert.equal(loadConfig({ ...BASE, ALL_IN_RISK_POLICY: 'shadow' }).capital.allInRiskPolicy, 'shadow');
  });

  it('is on in the paper config, where it runs first and waits for operator sign-off before live', () => {
    const paper = loadConfig({ ...BASE, MODE: 'paper' }, 'config.paper.yml');
    assert.equal(paper.capital.allInRiskPolicy, 'shadow');
  });
});

describe('telegram configuration', () => {
  it('loads Telegram credentials when both bot token and chat ID are provided', () => {
    const config = loadConfig({ ...BASE, TELEGRAM_BOT_TOKEN: '123456:ABC-DEF', TELEGRAM_CHAT_ID: '-100123456789' });
    assert.deepEqual(config.ops.telegram, { botToken: '123456:ABC-DEF', chatId: '-100123456789' });
  });

  it('leaves telegram undefined when neither variable is set', () => {
    assert.equal(loadConfig(BASE).ops.telegram, undefined);
  });

  it('throws an actionable error when only one Telegram credential is set', () => {
    assert.throws(
      () => loadConfig({ ...BASE, TELEGRAM_BOT_TOKEN: '123456:ABC-DEF' }),
      /Telegram alerts require both TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID/,
    );
    assert.throws(
      () => loadConfig({ ...BASE, TELEGRAM_CHAT_ID: '-100123456789' }),
      /Telegram alerts require both TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID/,
    );
  });
});

describe('stale-position grace and broker P&L exit settings', () => {
  const STALE_ENV = { DHAN_CLIENT_ID: '1', DHAN_ACCESS_TOKEN: 't', DATABASE_URL: 'postgres://paper.test.invalid/agent' };

  it('defaults the stale-position grace to 30 seconds and keeps the broker P&L exit off', () => {
    const config = loadConfig(STALE_ENV);
    assert.equal(config.ops.stalePositionGraceMs, 30_000);
    assert.equal(config.ops.brokerPnlExit, false);
  });

  it('refuses a grace period shorter than the feed stale threshold', () => {
    assert.throws(() => loadConfig({ ...STALE_ENV, FEED_STALE_MS: '8000', STALE_POSITION_GRACE_MS: '6000' }), /STALE_POSITION_GRACE_MS must be at least FEED_STALE_MS/);
  });

  it('turns the broker P&L exit on from BROKER_PNL_EXIT', () => {
    assert.equal(loadConfig({ ...STALE_ENV, BROKER_PNL_EXIT: 'on' }).ops.brokerPnlExit, true);
  });
});
