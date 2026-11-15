import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import stringWidth from 'string-width';
import {
  COCKPIT_MIN_COLS,
  COCKPIT_MIN_ROWS,
  computeCockpitLayout,
  fit,
  formatInr,
  formatInrWhole,
  formatSignedInr,
  renderOptionsCockpit,
  resizeNotice,
  wrap,
} from '../src/ui/cockpit.js';
import type { LogRecord } from '../src/ops/logger.js';
import { istEpoch, SESSION_DAY } from './support/fixtures.js';
import type { ChainWatchView } from '../src/runtime/views.js';
import { agentView, snapshot } from './support/views.js';

const plain = (line: string) => line.replace(/\x1b\[[0-9;]*m/g, '');

const position = {
  contractSymbol: 'NIFTY 22450 CE',
  optionType: 'CE' as const,
  strike: 22_450,
  expiry: '2026-10-15',
  quantity: 75,
  averagePrice: 101,
  stopLossPrice: 70.7,
  targetPrice: 161.6,
  mark: 118.45,
  unrealizedInr: 1283.75,
  openedAt: istEpoch(SESSION_DAY, '10:00'),
  heldMinutes: 30,
  exitRequested: false,
};

const logs: LogRecord[] = [
  { ts: istEpoch(SESSION_DAY, '10:00'), level: 'info', message: 'position open', data: { underlying: 'NIFTY', quantity: 75 } },
  { ts: istEpoch(SESSION_DAY, '10:12'), level: 'warn', message: 'entry rejected', data: undefined },
];

const sampleChainWatch: ChainWatchView = {
  symbol: 'NIFTY',
  spot: 22_461.5,
  expiry: '2026-10-15',
  atmStrike: 22_450,
  bullishEntryStrike: 22_450,
  bearishEntryStrike: 22_450,
  fetchedAgeMs: 800,
  status: 'ready',
  error: undefined,
  maxOpenInterest: 500_000,
  strikeScroll: 0,
  strikeScrollMin: -2,
  strikeScrollMax: 2,
  marketBias: 'BULLISH',
  rows: [
    {
      strike: 22_450,
      markers: ['ATM', 'CE_ENTRY', 'PE_ENTRY'],
      call: { bid: 100, ask: 101, spreadPct: 1, openInterest: 500_000, passesGate: true },
      put: { bid: 40, ask: 41, spreadPct: 2.4, openInterest: 80_000, passesGate: false },
    },
  ],
};

const rich = snapshot({
  chainWatch: sampleChainWatch,
  underlyings: [
    agentView({
      symbol: 'NIFTY',
      state: 'RISK_MANAGEMENT_ACTIVE',
      position,
      lastSignal: {
        direction: 'BULLISH',
        barTime: istEpoch(SESSION_DAY, '10:00'),
        spot: 22_461.5,
        reasons: ['ORB high 22465.00 broken by close 22461.50', 'SuperTrend UP (line 22401.10)'],
        at: istEpoch(SESSION_DAY, '10:00'),
      },
      lastCandidate: {
        contractSymbol: 'NIFTY 22450 CE',
        optionType: 'CE',
        strike: 22_450,
        expiry: '2026-10-15',
        entryReference: 101,
        bid: 100.5,
        spreadPct: 0.5,
        openInterest: 500_000,
        lots: 1,
        quantity: 75,
        stopLossPrice: 70.7,
        targetPrice: 161.6,
        riskInr: 2272.5,
        at: istEpoch(SESSION_DAY, '10:00'),
      },
    }),
    agentView({
      symbol: 'BANKNIFTY',
      state: 'HALTED',
      halted: 'entry unconfirmed (ENT-1): timeout',
      lastDrop: { code: 'SPREAD_TOO_WIDE', detail: 'spread 3.10% exceeds 2% on BANKNIFTY 48000 CE', at: istEpoch(SESSION_DAY, '10:12') },
    }),
  ],
  day: { dayKey: SESSION_DAY, realizedPnlInr: -1200, unrealizedPnlInr: 1283.75, dayPnlInr: 83.75, tradesToday: 2, openUnderlyings: ['NIFTY'], openPositions: 1, killSwitchReason: undefined },
});

describe('cockpit layout', () => {
  it('never draws a line wider than the terminal, at every size from the minimum up', () => {
    for (const width of [COCKPIT_MIN_COLS, COCKPIT_MIN_COLS + 7, 190, 240]) {
      for (const height of [COCKPIT_MIN_ROWS, COCKPIT_MIN_ROWS + 9, 70]) {
        for (const shot of [rich, snapshot({ underlyings: [] }), snapshot({ phase: 'FAILED', phaseDetail: 'broker reports 1 open option position(s) before start; close or adopt them before starting the agent' })]) {
          const lines = renderOptionsCockpit(shot, { width, height, selected: 0, notice: 'press c again within 5s', logs });
          for (const line of lines) {
            assert.ok(stringWidth(line) <= width, `line ${stringWidth(line)} > ${width}: ${plain(line).slice(0, 60)}`);
          }
        }
      }
    }
  });

  it('keeps the frame height at the terminal height so nothing scrolls', () => {
    const height = 48;
    const lines = renderOptionsCockpit(rich, { width: 170, height, selected: 0, notice: undefined, logs });
    assert.equal(lines.length, height);
  });

  it('gives the minimum terminal enough rows for every fixed section plus the table and log minimums', () => {
    const layout = computeCockpitLayout(COCKPIT_MIN_COLS, COCKPIT_MIN_ROWS);
    assert.ok(layout.tableRows >= 15);
    assert.ok(layout.logRows >= 3);
    assert.equal(layout.cols.reduce((sum, width) => sum + width, 5), COCKPIT_MIN_COLS);
  });

  it('explains the minimum size instead of drawing a broken frame', () => {
    const text = resizeNotice(100, 30).map(plain).join('\n');
    assert.match(text, new RegExp(`${COCKPIT_MIN_COLS} columns`));
    assert.match(text, new RegExp(`${COCKPIT_MIN_ROWS} rows`));
  });
});

describe('cockpit content', () => {
  it('shows the selected underlying signal, rejection, candidate and open position', () => {
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /OPTION CHAIN · NIFTY/);
    assert.match(text, /CE▸/);
    assert.match(text, /100\.0/);
    assert.match(text, /5\.0L/);
    assert.match(text, /40\.0/);
    assert.match(text, /straddle 141\.0/);
    assert.match(text, /window centered/);
    assert.doesNotMatch(text, /22,450 ATM CE…/);
    assert.match(text, /SELECTED NIFTY/);
    assert.match(text, /BULLISH at 10:00:00 IST/);
    assert.match(text, /NIFTY 22450 CE 2026-10-15/);
    assert.match(text, /SL 70\.70 TP 161\.60/);
    assert.match(text, /held 30m of 20m/);
  });

  it('moves the detail with the selection and clamps a stale selection', () => {
    const second = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 1, notice: undefined, logs }).map(plain).join('\n');
    assert.match(second, /SELECTED BANKNIFTY/);
    assert.match(second, /SPREAD_TOO_WIDE/);
    const clamped = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 99, notice: undefined, logs }).map(plain).join('\n');
    assert.match(clamped, /SELECTED BANKNIFTY/);
  });

  it('shows open positions across all underlyings even when another underlying is selected', () => {
    // BANKNIFTY is selected (selected: 1), but NIFTY has an open position
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 1, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /POSITIONS \(1\)/);
    assert.match(text, /NIFTY 22450 CE/);
    assert.match(text, /qty 75 avg 101\.00/);
  });

  it('scrolls positions when positionScroll is set', () => {
    const multi = snapshot({
      underlyings: [
        agentView({
          symbol: 'NIFTY',
          state: 'RISK_MANAGEMENT_ACTIVE',
          positions: [
            { ...position, contractSymbol: 'NIFTY 22450 CE' },
            { ...position, contractSymbol: 'NIFTY 22500 CE' },
          ],
        }),
        agentView({
          symbol: 'BANKNIFTY',
          state: 'RISK_MANAGEMENT_ACTIVE',
          positions: [
            { ...position, contractSymbol: 'BANKNIFTY 48000 PE', optionType: 'PE' },
            { ...position, contractSymbol: 'BANKNIFTY 48100 PE', optionType: 'PE' },
          ],
        }),
      ],
    });
    const scrolled = renderOptionsCockpit(multi, { width: 170, height: 48, selected: 0, notice: undefined, logs, positionScroll: 2 }).map(plain).join('\n');
    assert.match(scrolled, /POSITIONS \(4\)/);
    assert.match(scrolled, /▲ 2 more above/);
  });

  it('marks a halted underlying and explains that it stays blocked until restart', () => {
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 1, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /BANKNIFTY\s+HALTED/);
    assert.match(text, /BANKNIFTY HALTED: entry unconfirmed/);
    assert.match(text, /until restart after review/);
  });

  it('reports the entry state and the kill-switch reason in the header and risk column', () => {
    const open = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(open, /entries OPEN/);
    assert.match(open, /kill switch off/);
    const blocked = snapshot({
      day: { ...rich.day, killSwitchReason: 'operator entry block (2026-10-12T10:20:00.000Z)' },
    });
    const text = renderOptionsCockpit(blocked, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /entries BLOCKED/);
    assert.match(text, /kill switch ON/);
    assert.match(text, /operator entry block/);

    const pastWindow = snapshot({
      at: istEpoch(SESSION_DAY, '14:30'),
      entryStartMinute: 9 * 60 + 15,
      entryEndMinute: 14 * 60,
    });
    const closedText = renderOptionsCockpit(pastWindow, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(closedText, /entries CLOSED \(14:00\)/);
  });

  it('reports the live capital and balance breakdown in the risk column', () => {
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /init capital\s+₹3,00,000/);
    assert.match(text, /current bal\s+₹3,00,000/);
    assert.match(text, /allocated\s+₹0/);
    assert.match(text, /available\s+₹3,00,000/);
    assert.match(text, /live equity\s+₹3,00,000/);
    assert.match(text, /risk\/trade\s+₹3,000/);
  });

  it('shows a failed start with its reason rather than an empty dashboard', () => {
    const failed = snapshot({ phase: 'FAILED', phaseDetail: 'broker reports 1 open option position(s)', underlyings: [] });
    const text = renderOptionsCockpit(failed, { width: 170, height: 48, selected: 0, notice: undefined, logs: [] }).map(plain).join('\n');
    assert.match(text, /FAILED/);
    assert.match(text, /start failed: broker reports 1 open option position/);
    assert.match(text, /chain watch pauses until RUNNING/);
    assert.match(text, /no underlying selected/);
  });

  it('shows the pending confirmation in the footer', () => {
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 0, notice: 'press c again within 5s to close the NIFTY position', logs }).map(plain).join('\n');
    assert.match(text, /press c again within 5s to close the NIFTY position/);
  });

  it('lists the newest log record first', () => {
    const text = renderOptionsCockpit(rich, { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain);
    const logStart = text.findIndex((line) => line.includes('EVENT LOG'));
    assert.match(text[logStart + 2] ?? '', /10:00:00 IST INFO position open/);
    assert.match(text[logStart + 3] ?? '', /10:12:00 IST WARN entry rejected/);
  });
});

describe('cockpit helpers', () => {
  it('fits text to an exact width, truncating with an ellipsis when needed', () => {
    assert.equal(stringWidth(fit('abc', 10)), 10);
    assert.equal(stringWidth(fit('a very long line of text that will not fit', 12)), 12);
    assert.equal(fit('anything', 0), '');
  });

  it('wraps on words and marks truncation when the text exceeds the line budget', () => {
    const lines = wrap('one two three four five six seven eight nine ten', 12, 2).map(plain);
    assert.equal(lines.length, 2);
    assert.ok(lines[1]?.trimEnd().endsWith('…'));
    assert.deepEqual(wrap('short', 20, 3).map(plain).map((line) => line.trimEnd()), ['short']);
  });

  it('formats money with Indian grouping and an explicit sign on P&L', () => {
    assert.equal(formatInr(300_000), '₹300,000.00'.replace('300,000', '3,00,000'));
    assert.equal(formatInrWhole(3_000), '₹3,000');
    assert.match(plain(formatSignedInr(-1200)), /^-₹1,200\.00$/);
    assert.match(plain(formatSignedInr(83.75)), /^\+₹83\.75$/);
  });
});

describe('cockpit: context and giveback', () => {
  const render = (shot: ReturnType<typeof snapshot>) =>
    plain(renderOptionsCockpit(shot, { width: 200, height: 50, selected: 0, notice: undefined, logs: [] }).join('\n'));

  it('should show day trend, regime and the last structure shift for each underlying', () => {
    const context = {
      dayTrend: 'BEARISH' as const,
      dayMoveAtr: -4.4,
      regime: 'RANGING' as const,
      efficiency: 0.18,
      structure: { trend: 'BULLISH' as const, lastSwingHigh: 1, lastSwingLow: 1, shift: { direction: 'BULLISH' as const, barTime: istEpoch(SESSION_DAY, '13:35'), barsAgo: 1 } },
    };
    const screen = render(snapshot({ underlyings: [agentView({ symbol: 'NIFTY', context })] }));
    assert.match(screen, /day↓-4\.4 {2}RANGE 0\.18 {2}struct↑ MSS↑ 13:35/);
  });

  it('should show how much of the day peak has been given back, and warn when there is no daily stop', () => {
    const base = snapshot();
    const screen = render(
      snapshot({ dayPeakPnlInr: 29_505.52, dailyLossLimitInr: 2_000_000, day: { ...base.day, dayPnlInr: -31_364.41, realizedPnlInr: -31_364.41 } }),
    );
    assert.match(screen, /peak \+₹29,506/);
    assert.match(screen, /gave back ₹60,870 \(206%\)/);
    assert.match(screen, /no daily stop/);
  });
});

describe('position protection label', () => {
  const withProtection = (protection: 'EXCHANGE_BRACKET' | 'CLIENT_SIDE') => ({
    ...rich,
    underlyings: rich.underlyings.map((u) => ({ ...u, positions: (u.positions ?? []).map((p) => ({ ...p, protection })) })),
  });

  it('says the stop and target are client-side where the venue holds no bracket', () => {
    const text = renderOptionsCockpit(withProtection('CLIENT_SIDE'), { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.match(text, /client-side/);
  });

  it('does not say client-side for a position whose stop is held at the exchange', () => {
    const text = renderOptionsCockpit(withProtection('EXCHANGE_BRACKET'), { width: 170, height: 48, selected: 0, notice: undefined, logs }).map(plain).join('\n');
    assert.doesNotMatch(text, /client-side/);
  });
});
