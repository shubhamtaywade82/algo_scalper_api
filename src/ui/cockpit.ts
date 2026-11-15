import chalk from 'chalk';
import stringWidth from 'string-width';
import type { LogRecord } from '../ops/logger.js';
import type { AgentView, CockpitSnapshot, FeedStatusView, PositionView } from '../runtime/views.js';
import { formatMinuteOfDay, isMarketSessionOpen, IST_OFFSET_MS, istParts } from '../time/ist.js';
import { CHAIN_PANEL_ROWS, chainWatchLines } from './chainWatchPanel.js';
import { bad, callSide, emphasis, freshness, info, infoBold, label, muted, ok, putSide, range, selectedName, warn } from './palette.js';
import { COCKPIT_KEYS } from './keymap.js';

/**
 * Pure renderer for the operator cockpit. It turns a read-only snapshot into lines of text.
 * It has no state of its own and calls nothing that trades, so it can be tested without a
 * terminal and used without any risk to the trading loop.
 */

const BORDER_COLS = 5;
// Column floors are the widest content each column shows at its normal size
const COL_FLOORS = { c1: 36, c2: 46, c3: 36, c4: 34 } as const;
export const COCKPIT_MIN_COLS = COL_FLOORS.c1 + COL_FLOORS.c2 + COL_FLOORS.c3 + COL_FLOORS.c4 + BORDER_COLS;

const HEADER_ROWS = 3;
const TABLE_FRAME_ROWS = 4;
const DETAIL_ROWS = CHAIN_PANEL_ROWS;
const DETAIL_FRAME_ROWS = 4;
const LOG_FRAME_ROWS = 4;
const FOOTER_ROWS = 2;
const FIXED_ROWS = HEADER_ROWS + TABLE_FRAME_ROWS + DETAIL_FRAME_ROWS + DETAIL_ROWS + LOG_FRAME_ROWS + FOOTER_ROWS;
const BLOCK_ROWS = 6; // one underlying: five content rows and a spacer
const MIN_TABLE_ROWS = BLOCK_ROWS * 3;
const MAX_TABLE_ROWS = BLOCK_ROWS * 8;
const MIN_LOG_ROWS = 3;
export const COCKPIT_MIN_ROWS = FIXED_ROWS + MIN_TABLE_ROWS + MIN_LOG_ROWS;

export interface CockpitLayout {
  readonly cols: readonly [number, number, number, number];
  readonly tableRows: number;
  readonly logRows: number;
}

export function computeCockpitLayout(width: number, height: number): CockpitLayout {
  const extra = Math.max(0, width - COCKPIT_MIN_COLS);
  const c1 = COL_FLOORS.c1 + Math.floor(extra * 0.2);
  const c3 = COL_FLOORS.c3 + Math.floor(extra * 0.2);
  const c4 = COL_FLOORS.c4 + Math.floor(extra * 0.1);
  const c2 = Math.max(0, width - BORDER_COLS - c1 - c3 - c4);
  const available = Math.max(0, height - FIXED_ROWS);
  const tableRows = Math.max(MIN_TABLE_ROWS, Math.min(MAX_TABLE_ROWS, Math.round(available * 0.7)));
  return { cols: [c1, c2, c3, c4], tableRows, logRows: Math.max(MIN_LOG_ROWS, available - tableRows) };
}

export interface CockpitOptions {
  readonly width: number;
  readonly height: number;
  /** Index into snapshot.underlyings; clamped when out of range. */
  readonly selected: number;
  /** Last operator action result or a pending confirmation. */
  readonly notice: string | undefined;
  readonly logs: readonly LogRecord[];
  readonly positionScroll?: number | undefined;
}

const dim = muted;
const cyanBold = infoBold;
const red = bad;
const green = ok;
const yellow = warn;

export { fit } from './terminalFit.js';
import { fit } from './terminalFit.js';

/** Splits text into lines no wider than `width`, breaking on spaces; an oversize word is cut. */
export function wrap(text: string, width: number, maxLines: number): string[] {
  const words = text.split(/\s+/).filter((word) => word.length > 0);
  const lines: string[] = [];
  let current = '';
  for (const word of words) {
    const candidate = current === '' ? word : `${current} ${word}`;
    if (stringWidth(candidate) <= width) {
      current = candidate;
      continue;
    }
    if (current !== '') {
      lines.push(current);
    }
    current = word;
  }
  if (current !== '') {
    lines.push(current);
  }
  const bounded = lines.slice(0, maxLines).map((line) => fit(line, width));
  if (lines.length > maxLines && bounded.length > 0) {
    bounded[bounded.length - 1] = fit(`${lines[maxLines - 1] ?? ''} …`, width);
  }
  return bounded;
}

const istClockHms = (epochMs: number): string => {
  const parts = istParts(epochMs);
  const seconds = Math.floor(((epochMs + IST_OFFSET_MS) % 60_000) / 1000);
  return `${formatMinuteOfDay(parts.minuteOfDay)}:${String(seconds).padStart(2, '0')}`;
};

export function formatIstClock(epochMs: number): string {
  return `${istClockHms(epochMs)} IST`;
}

export function formatInr(value: number): string {
  return `₹${value.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function formatInrWhole(value: number): string {
  return `₹${value.toLocaleString('en-IN', { maximumFractionDigits: 0 })}`;
}

export function formatSignedInr(value: number): string {
  const text = formatInr(Math.abs(value));
  const sign = value < 0 ? '-' : '+';
  const colored = value < 0 ? red : green;
  return colored(`${sign}${text}`);
}

function price(value: number | undefined): string {
  return value === undefined ? '—' : value.toFixed(2);
}

export function feedStatusText(
  ms: number | undefined,
  staleMs: number,
  marketOpen = true,
  feedStatus?: FeedStatusView['status'],
): string {
  if (!marketOpen) {
    return dim('■ CLOSED');
  }
  if (feedStatus === 'disconnected') {
    return bad('✖ WS DOWN');
  }
  if (feedStatus === 'reconnecting') {
    return warn('◐ RECONNECTING');
  }
  if (feedStatus === 'connecting') {
    return warn('◐ CONNECTING');
  }
  if (ms === undefined) {
    return bad('○ NO TICK');
  }
  if (ms > staleMs) {
    return bad('✖ STALE');
  }
  if (ms > staleMs / 2) {
    return warn('◐ DELAYED');
  }
  return ok('● LIVE');
}

function feedHeaderTag(feed: FeedStatusView | undefined): string {
  if (feed === undefined) {
    return '';
  }
  switch (feed.status) {
    case 'connected':
      return ok(`● FEED (${feed.subscribedCount} subs, ${feed.totalTicks} ticks)`);
    case 'connecting':
      return warn('◐ FEED CONNECTING');
    case 'reconnecting': {
      const reason = feed.disconnectReason !== undefined ? ` [${feed.disconnectReason}]` : '';
      return warn(`◐ FEED RECONNECTING${reason}`);
    }
    case 'disconnected': {
      const reason = feed.disconnectReason !== undefined ? ` [${feed.disconnectReason}]` : '';
      return bad(`✖ FEED DOWN${reason}`);
    }
  }
}

function stateText(state: AgentView['state']): string {
  if (state === 'HALTED') {
    return red(state);
  }
  if (state === 'IDLE') {
    return dim(state);
  }
  return yellow(state);
}

function phaseTag(snapshot: CockpitSnapshot): string {
  switch (snapshot.phase) {
    case 'RUNNING':
      return green('● RUNNING');
    case 'STARTING':
      return yellow('◐ STARTING');
    case 'STOPPING':
      return yellow('◐ STOPPING');
    case 'FAILED':
      return red('✖ FAILED');
    case 'STOPPED':
      return dim('■ STOPPED');
    case 'IDLE':
      return dim('○ IDLE');
  }
}

function boxed(title: string, lines: readonly string[], width: number): string[] {
  const inner = Math.max(0, width - 2);
  const cyan = (text: string) => chalk.cyan(text);
  return [
    cyan(`┌${'─'.repeat(inner)}┐`),
    cyan('│') + fit(` ${cyanBold(title)}`, inner) + cyan('│'),
    cyan(`├${'─'.repeat(inner)}┤`),
    ...lines.map((line) => cyan('│') + fit(line, inner) + cyan('│')),
    cyan(`└${'─'.repeat(inner)}┘`),
  ];
}

function header(snapshot: CockpitSnapshot, width: number): string[] {
  const inner = width - 2;
  const tag =
    snapshot.mode === 'paper'
      ? chalk.yellow.bold('◉ PAPER')
      : snapshot.mode === 'sandbox'
        ? chalk.cyan.bold('◎ SANDBOX')
        : chalk.green.bold('● LIVE');
  const strat = snapshot.strategy === undefined ? '' : `  ${chalk.magenta.bold(snapshot.strategy.posture.toUpperCase())} ${dim(snapshot.strategy.strategies.filter((s) => s.on).map((s) => s.label).join('+') || 'none')}`;
  const feedTag = feedHeaderTag(snapshot.feed);
  const left = ` ${chalk.green.bold('⬡ NSE INDEX OPTIONS')}${dim(' v0.1.0 ')}${tag}  ${chalk.cyan.bold('◆ DHAN')}  ${phaseTag(snapshot)}${feedTag ? `  ${feedTag}` : ''}${strat}`;
  const sessionOpen = isMarketSessionOpen(snapshot.at);
  const minute = istParts(snapshot.at).minuteOfDay;
  const inWindow =
    snapshot.entryStartMinute === undefined ||
    snapshot.entryEndMinute === undefined ||
    (minute >= snapshot.entryStartMinute && minute < snapshot.entryEndMinute);
  const statusTag = !sessionOpen
    ? dim('market CLOSED')
    : snapshot.day.killSwitchReason !== undefined
      ? red('entries BLOCKED')
      : !inWindow
        ? yellow(`entries CLOSED (${formatMinuteOfDay(snapshot.entryEndMinute!)})`)
        : green('entries OPEN');
  const right = `${dim(formatIstClock(snapshot.at))} ${statusTag} `;
  const gap = Math.max(1, inner - stringWidth(left) - stringWidth(right));
  return [
    chalk.cyan(`╭${'─'.repeat(inner)}╮`),
    chalk.cyan('│') + fit(left + ' '.repeat(gap) + right, inner) + chalk.cyan('│'),
    chalk.cyan(`╰${'─'.repeat(inner)}╯`),
  ];
}

interface UnderlyingBlockOpts {
  readonly staleMs: number;
  readonly marketOpen?: boolean | undefined;
  readonly feedStatus?: FeedStatusView['status'] | undefined;
}

function underlyingBlock(
  agent: AgentView,
  selected: boolean,
  width: number,
  opts: UnderlyingBlockOpts,
): string[] {
  const { staleMs, marketOpen = true, feedStatus } = opts;
  const marker = selected ? info('▸') : ' ';
  const name = selected ? selectedName(agent.symbol) : emphasis(agent.symbol);
  const halt = agent.halted === undefined ? '' : ` ${bad('HALT')}`;
  const { emaFast, emaSlow, supertrend, supertrendLine, orbHigh, orbLow } = agent.indicators;
  const trend =
    supertrend === undefined
      ? muted('ST —')
      : supertrend === 'UP'
        ? ok(`ST UP ${price(supertrendLine)}`)
        : bad(`ST DOWN ${price(supertrendLine)}`);
  const alignment =
    emaFast === undefined || emaSlow === undefined ? muted('EMA warming up') : emaFast > emaSlow ? ok('EMA up') : bad('EMA down');
  const orb =
    orbHigh === undefined || orbLow === undefined ? muted('ORB forming') : range(`ORB ${price(orbLow)}–${price(orbHigh)}`);
  const spot = freshness(price(agent.spot), agent.spotAgeMs, staleMs);
  return [
    fit(`${marker} ${name} ${stateText(agent.state)}${halt}`, width),
    fit(`  ${muted('spot')} ${spot}  ${feedStatusText(agent.spotAgeMs, staleMs, marketOpen, feedStatus)}`, width),
    fit(`  ${trend}  ${alignment}`, width),
    fit(`  ${orb}`, width),
    fit(`  ${contextText(agent.context)}`, width),
    fit('', width),
  ];
}

function leanArrow(lean: 'BULLISH' | 'BEARISH' | 'NEUTRAL'): string {
  return lean === 'BULLISH' ? ok('↑') : lean === 'BEARISH' ? bad('↓') : muted('→');
}

/** One line of market context: day trend in ATRs, regime with its efficiency, structure and the last shift. */
function contextText(context: AgentView['context']): string {
  if (context === undefined) {
    return muted('context warming up');
  }
  const regime = context.regime === 'TRENDING' ? ok(`TREND ${context.efficiency}`) : warn(`RANGE ${context.efficiency}`);
  const { shift } = context.structure;
  const shiftText = shift === undefined ? muted('no MSS') : `MSS${leanArrow(shift.direction)} ${formatIstClock(shift.barTime).slice(0, 5)}`;
  return `${muted('day')}${leanArrow(context.dayTrend)}${context.dayMoveAtr}  ${regime}  ${muted('struct')}${leanArrow(context.structure.trend)} ${shiftText}`;
}

function underlyingColumn(snapshot: CockpitSnapshot, selected: number, width: number, rows: number): string[] {
  const lines: string[] = [];
  const blocks = snapshot.underlyings.length;
  const visibleBlocks = Math.max(1, Math.floor(rows / BLOCK_ROWS));
  const shown = blocks > visibleBlocks ? visibleBlocks - 1 : blocks;
  const marketOpen = isMarketSessionOpen(snapshot.at);
  const opts: UnderlyingBlockOpts = {
    staleMs: snapshot.staleMs,
    marketOpen,
    feedStatus: snapshot.feed?.status,
  };
  for (let index = 0; index < shown; index += 1) {
    const agent = snapshot.underlyings[index];
    if (agent !== undefined) {
      lines.push(...underlyingBlock(agent, index === selected, width, opts));
    }
  }
  if (shown < blocks) {
    lines.push(fit(dim(`+${blocks - shown} more underlying(s)`), width));
  }
  return lines;
}

function signalColumn(agent: AgentView | undefined, width: number): string[] {
  if (agent === undefined) {
    return [fit(dim('no underlying selected'), width)];
  }
  const lines: string[] = [fit(infoBold(`SELECTED ${agent.symbol}`), width), fit(label('LAST SIGNAL'), width)];
  if (agent.lastSignal === undefined) {
    lines.push(fit(dim('  none this session'), width));
  } else {
    const signal = agent.lastSignal;
    const direction = signal.direction === 'BULLISH' ? callSide('BULLISH') : putSide('BEARISH');
    lines.push(fit(`  ${direction} at ${formatIstClock(signal.at)} close ${price(signal.spot)}`, width));
    for (const reason of signal.reasons.slice(0, 2)) {
      lines.push(fit(`    ${dim(reason)}`, width));
    }
  }
  lines.push(fit(label('LAST REJECTION'), width));
  if (agent.lastDrop === undefined) {
    lines.push(fit(dim('  none'), width));
  } else {
    lines.push(fit(`  ${yellow(agent.lastDrop.code)} at ${formatIstClock(agent.lastDrop.at)}`, width));
    for (const line of wrap(agent.lastDrop.detail, Math.max(10, width - 4), 2)) {
      lines.push(fit(`    ${dim(line)}`, width));
    }
  }
  lines.push(fit(label('LAST CANDIDATE'), width));
  if (agent.lastCandidate === undefined) {
    const hint =
      agent.lastSignal === undefined
        ? '  none yet — contract, spread, OI and brackets appear after a signal'
        : '  none kept — see LAST REJECTION or the event log';
    lines.push(fit(dim(hint), width));
  } else {
    const c = agent.lastCandidate;
    const side = c.optionType === 'CE' ? callSide(c.contractSymbol) : putSide(c.contractSymbol);
    lines.push(fit(`  ${side} ${muted(c.expiry)}`, width));
    lines.push(fit(`    ask ${emphasis(price(c.entryReference))} bid ${price(c.bid)} spread ${warn(`${c.spreadPct.toFixed(2)}%`)}`, width));
    lines.push(fit(`    OI ${c.openInterest.toLocaleString('en-IN')} lots ${emphasis(String(c.lots))} qty ${c.quantity}`, width));
    lines.push(fit(`    SL ${bad(price(c.stopLossPrice))} TP ${ok(price(c.targetPrice))} risk ${formatInr(c.riskInr)}`, width));
  }
  return lines;
}

interface ScopedPosition {
  readonly position: PositionView;
  readonly isSelected: boolean;
}

function allOpenPositions(snapshot: CockpitSnapshot, selectedIndex: number): ScopedPosition[] {
  const selectedSymbol = snapshot.underlyings[selectedIndex]?.symbol;
  const list: ScopedPosition[] = [];
  for (const agent of snapshot.underlyings) {
    const poses = agent.positions && agent.positions.length > 0 ? agent.positions : (agent.position ? [agent.position] : []);
    for (const pos of poses) {
      list.push({ position: pos, isSelected: agent.symbol === selectedSymbol });
    }
  }
  return list;
}

function positionLines(position: PositionView, maxHoldMinutes: number, width: number, isSelected = false): string[] {
  const pnl = position.unrealizedInr === undefined ? dim('—') : formatSignedInr(position.unrealizedInr);
  const symbol = position.optionType === 'CE' ? callSide(position.contractSymbol) : putSide(position.contractSymbol);
  const markPrefix = isSelected ? chalk.cyan('▸ ') : '  ';
  return [
    fit(`${markPrefix}${ok('OPEN')} ${symbol}`, width),
    fit(`    qty ${emphasis(String(position.quantity))} avg ${price(position.averagePrice)}`, width),
    fit(`    mark ${emphasis(price(position.mark))} P&L ${pnl}`, width),
    fit(`    SL ${bad(price(position.stopLossPrice))} TP ${ok(price(position.targetPrice))}${position.protection === 'CLIENT_SIDE' ? muted(' client-side') : ''}`, width),
    fit(`    held ${position.heldMinutes}m of ${maxHoldMinutes}m${position.exitRequested ? yellow(' close requested') : ''}`, width),
  ];
}

interface PositionColumnInput {
  readonly snapshot: CockpitSnapshot;
  readonly selectedIndex: number;
  readonly width: number;
  readonly maxHoldMinutes: number;
  readonly maxRows: number;
  readonly scroll?: number | undefined;
}

function positionColumn(input: PositionColumnInput): string[] {
  const { snapshot, selectedIndex, width, maxHoldMinutes, maxRows, scroll = 0 } = input;
  const positions = allOpenPositions(snapshot, selectedIndex);
  if (positions.length === 0) {
    const agent = snapshot.underlyings[selectedIndex];
    const lines: string[] = [fit(dim('  flat (all)'), width), fit(label('LAST EXIT'), width)];
    const exitAgent = agent?.lastExit !== undefined ? agent : snapshot.underlyings.find((u) => u.lastExit !== undefined);
    if (exitAgent?.lastExit === undefined) {
      lines.push(fit(dim('  none this session'), width));
    } else {
      lines.push(fit(`  ${exitAgent.symbol} ${exitAgent.lastExit.reason} ${formatSignedInr(exitAgent.lastExit.pnlInr)}`, width));
      lines.push(fit(dim(`  at ${formatIstClock(exitAgent.lastExit.at)}`), width));
    }
    return lines;
  }
  const allLines: string[] = [];
  let first = true;
  for (const pos of positions) {
    if (!first) allLines.push(fit('', width));
    first = false;
    allLines.push(...positionLines(pos.position, maxHoldMinutes, width, pos.isSelected));
  }
  if (allLines.length <= maxRows) return allLines;
  const maxScroll = Math.max(0, allLines.length - maxRows);
  const clamped = Math.max(0, Math.min(scroll, maxScroll));
  const visible = allLines.slice(clamped, clamped + maxRows);
  if (clamped > 0 && visible.length > 0) {
    visible[0] = fit(dim(`▲ ${clamped} more above ([/])`), width);
  }
  if (clamped < maxScroll && visible.length > 0) {
    visible[visible.length - 1] = fit(dim(`▼ ${maxScroll - clamped} more below ([/])`), width);
  }
  return visible;
}

function riskBar(lossUsedPct: number, cells: number): string {
  const filled = Math.min(cells, Math.max(0, Math.round((lossUsedPct / 100) * cells)));
  const color = lossUsedPct >= 100 ? red : lossUsedPct >= 60 ? yellow : green;
  return color('█'.repeat(filled)) + dim('░'.repeat(cells - filled));
}

function capitalLines(snapshot: CockpitSnapshot, width: number): string[] {
  const initCap = snapshot.initialCapitalInr ?? snapshot.capitalInr;
  const currentBal = snapshot.currentBalanceInr ?? initCap;
  const realTimeBal = snapshot.realTimeBalanceInr ?? (initCap + snapshot.day.dayPnlInr);
  const eqColor = realTimeBal >= initCap ? green : red;
  return [
    fit(`init capital  ${formatInrWhole(initCap)}`, width),
    fit(`current bal   ${formatInrWhole(currentBal)}`, width),
    fit(`allocated     ${formatInrWhole(snapshot.allocatedBalanceInr ?? 0)}`, width),
    fit(`available     ${formatInrWhole(snapshot.availableBalanceInr ?? initCap)}`, width),
    fit(`live equity   ${eqColor(formatInrWhole(realTimeBal))}`, width),
    fit(`risk/trade    ${formatInrWhole(snapshot.riskBudgetInr)}`, width),
  ];
}

function cooldownLines(snapshot: CockpitSnapshot, width: number): string[] {
  return snapshot.underlyings
    .filter((agent) => agent.cooldownUntil !== undefined && agent.cooldownUntil > snapshot.at)
    .map((agent) => {
      const remaining = Math.ceil(((agent.cooldownUntil ?? 0) - snapshot.at) / 1000);
      const mm = String(Math.floor(remaining / 60)).padStart(2, '0');
      const ss = String(remaining % 60).padStart(2, '0');
      return fit(warn(`cooldown ${agent.symbol} ${mm}:${ss}`), width);
    });
}

/** Peak day P&L and how much of it is gone, so a giveback is visible before it becomes a loss. */
function peakLines(snapshot: CockpitSnapshot, width: number): string[] {
  const peak = snapshot.dayPeakPnlInr ?? 0;
  if (peak <= 0) {
    return [];
  }
  const givenBack = Math.max(0, peak - snapshot.day.dayPnlInr);
  const pct = (givenBack / peak) * 100;
  const color = pct >= 50 ? red : pct >= 25 ? yellow : dim;
  return [
    fit(`  peak +${formatInrWhole(peak)}`, width),
    fit(`  ${color(`gave back ${formatInrWhole(givenBack)} (${pct.toFixed(0)}%)`)}`, width),
  ];
}

function riskColumn(snapshot: CockpitSnapshot, width: number): string[] {
  const day = snapshot.day;
  const effectiveLoss = day.effectiveDayPnlInr ?? day.dayPnlInr;
  const lossUsedPct = effectiveLoss < 0 && snapshot.dailyLossLimitInr > 0 ? (-effectiveLoss / snapshot.dailyLossLimitInr) * 100 : 0;
  const openCount = day.openPositions ?? day.openUnderlyings.length;
  const tradesStr = snapshot.maxTradesPerDay > 0
    ? (day.tradesToday >= snapshot.maxTradesPerDay ? bad(`${day.tradesToday}/${snapshot.maxTradesPerDay}`) : `${day.tradesToday}/${snapshot.maxTradesPerDay}`)
    : `${day.tradesToday} (unlimited)`;
  const lossLine = day.dailyLossBrakeEnabled === false
    ? fit(warn('loss [BRAKE OFF: UNLIMITED]'), width)
    : snapshot.dailyLossLimitInr >= snapshot.currentBalanceInr
      ? fit(warn('loss limit ≥ capital: no daily stop'), width)
      : fit(
          `loss ${riskBar(lossUsedPct, 12)} ${lossUsedPct.toFixed(0)}% of ${formatInrWhole(snapshot.dailyLossLimitInr)}${day.dailyLossBaselineInr ? ` [reset @ ${formatInrWhole(day.dailyLossBaselineInr)}]` : ''}`,
          width,
        );
  return [
    fit(cyanBold(`DAY ${day.dayKey}`), width),
    fit(`P&L ${formatSignedInr(day.dayPnlInr)}`, width),
    fit(`  realised ${formatSignedInr(day.realizedPnlInr)}`, width),
    fit(`  open P&L ${formatSignedInr(day.unrealizedPnlInr)}`, width),
    ...peakLines(snapshot, width),
    lossLine,
    fit(`trades ${tradesStr}  open ${openCount}/${snapshot.maxOpenPositions}`, width),
    ...capitalLines(snapshot, width),
    ...(day.killSwitchReason === undefined
      ? [fit(`kill switch ${green('off')}`, width)]
      : [fit(`kill switch ${red('ON')}`, width), fit(dim(`  ${day.killSwitchReason}`), width)]),
    ...cooldownLines(snapshot, width),
  ];
}

function table(snapshot: CockpitSnapshot, options: CockpitOptions, layout: CockpitLayout): string[] {
  const [c1, c2, c3, c4] = layout.cols;
  const selected = Math.max(0, Math.min(options.selected, snapshot.underlyings.length - 1));
  const agent = snapshot.underlyings[selected];
  const openCount = snapshot.underlyings.reduce(
    (count, u) => count + (u.positions && u.positions.length > 0 ? u.positions.length : (u.position ? 1 : 0)),
    0,
  );
  const columns: [string[], string[], string[], string[]] = [
    underlyingColumn(snapshot, selected, c1, layout.tableRows),
    signalColumn(agent, c2),
    positionColumn({
      snapshot,
      selectedIndex: selected,
      width: c3,
      maxHoldMinutes: snapshot.maxHoldMinutes,
      maxRows: layout.tableRows,
      scroll: options.positionScroll,
    }),
    riskColumn(snapshot, c4),
  ];
  const rows = layout.tableRows;
  const pad = (lines: string[], width: number) => {
    const out = lines.slice(0, rows);
    while (out.length < rows) {
      out.push(' '.repeat(width));
    }
    return out;
  };
  const cells = columns.map((lines, index) => pad(lines, layout.cols[index] ?? 0));
  const titles = [
    infoBold(`UNDERLYINGS (${snapshot.underlyings.length})`),
    chalk.magenta.bold('SIGNAL & CONTRACT'),
    chalk.white.bold(openCount > 0 ? `POSITIONS (${openCount})` : 'POSITION'),
    warn('RISK & DAY'),
  ];
  const cyan = (text: string) => chalk.cyan(text);
  const bar = (left: string, middle: string, right: string) =>
    cyan(left + [c1, c2, c3, c4].map((width) => '─'.repeat(width)).join(middle) + right);
  const titleRow =
    cyan('│') +
    [c1, c2, c3, c4].map((width, index) => fit(` ${titles[index] ?? ''}`, width)).join(cyan('│')) +
    cyan('│');
  const out = [bar('┌', '┬', '┐'), titleRow, bar('├', '┼', '┤')];
  for (let row = 0; row < rows; row += 1) {
    out.push(cyan('│') + cells.map((column) => column[row] ?? '').join(cyan('│')) + cyan('│'));
  }
  out.push(bar('└', '┴', '┘'));
  return out;
}

function chainPanel(snapshot: CockpitSnapshot, options: CockpitOptions): string[] {
  const index = Math.max(0, Math.min(options.selected, snapshot.underlyings.length - 1));
  const agent = snapshot.underlyings[index];
  const inner = Math.max(10, options.width - 4);
  const watch = agent === undefined || snapshot.chainWatch?.symbol !== agent.symbol ? undefined : snapshot.chainWatch;
  const content = chainWatchLines(watch, agent, inner, snapshot.contractMaxSpreadPct, snapshot.contractMinOpenInterest);
  if (snapshot.phase === 'FAILED') {
    content[1] = red(fit(`  start failed: ${snapshot.phaseDetail ?? 'unknown'}`, inner));
    content[2] = dim(fit('  fix the cause and restart — chain watch pauses until RUNNING', inner));
  } else if (agent?.halted !== undefined) {
    content[1] = red(fit(`  ${agent.symbol} HALTED: ${agent.halted}`, inner));
    content[2] = dim(fit('  new entries stay blocked until restart after review', inner));
  }
  return boxed('CHAIN WATCH', content, options.width);
}

function logLine(record: LogRecord, width: number): string {
  const time = dim(formatIstClock(record.ts));
  const level = record.level === 'error' ? bad('ERR ') : record.level === 'warn' ? warn('WARN') : info('INFO');
  const data = record.data === undefined ? '' : ` ${dim(JSON.stringify(record.data))}`;
  return fit(`${time} ${level} ${record.message}${data}`, width);
}

function logBox(logs: readonly LogRecord[], rows: number, width: number): string[] {
  const inner = Math.max(0, width - 2);
  const content: string[] = [];
  for (let index = 0; index < rows; index += 1) {
    const record = logs[index];
    content.push(record === undefined ? fit('', inner) : logLine(record, inner));
  }
  return boxed('EVENT LOG (newest first)', content, width);
}

function footer(options: CockpitOptions): string[] {
  const keys = dim(` ${COCKPIT_KEYS.filter((key) => key.display !== '?').map((key) => key.help).join('   ')}`);
  const notice = options.notice === undefined ? '' : ` ${options.notice}`;
  return [fit(keys, options.width), fit(chalk.cyan(notice), options.width)];
}

/** Lines that fit the terminal. Callers show a resize notice below the minimum instead. */
export function renderOptionsCockpit(snapshot: CockpitSnapshot, options: CockpitOptions): string[] {
  const width = Math.max(COCKPIT_MIN_COLS, options.width);
  const height = Math.max(COCKPIT_MIN_ROWS, options.height);
  const layout = computeCockpitLayout(width, height);
  return [
    ...header(snapshot, width),
    ...table(snapshot, { ...options, width, height }, layout),
    ...chainPanel(snapshot, { ...options, width, height }),
    ...logBox(options.logs, layout.logRows, width),
    ...footer({ ...options, width }),
  ];
}

export function resizeNotice(width: number, height: number): string[] {
  return [
    chalk.yellow.bold('Terminal too small for the operator cockpit'),
    dim(`need ${COCKPIT_MIN_COLS} columns × ${COCKPIT_MIN_ROWS} rows; have ${width} × ${height}`),
    dim('enlarge the window, or run with UI=off for plain log output'),
  ];
}
