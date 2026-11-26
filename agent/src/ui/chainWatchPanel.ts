import type { AgentView, ChainWatchLegView, ChainWatchRowView, ChainWatchView } from '../runtime/views.js';
import type { ChainAnalysis } from '../options/chainAnalyzer.js';
import { bad, callSide, infoBold, muted, ok, putSide, warn } from './palette.js';
import { fit } from './terminalFit.js';

export const CHAIN_PANEL_ROWS = 9;

const STRIKE_W = 8;
const MARKS_W = 16;
const PX_W = 7;
const SPR_W = 6;
const BAR_W = 10;
const OI_W = 6;

function price(value: number | undefined): string {
  return value === undefined ? '—' : value.toFixed(1);
}

function compactOi(oi: number | undefined): string {
  if (oi === undefined) {
    return '—';
  }
  if (oi >= 100_000) {
    return `${(oi / 100_000).toFixed(1)}L`;
  }
  if (oi >= 1_000) {
    return `${(oi / 1_000).toFixed(0)}k`;
  }
  return String(oi);
}

function oiBar(oi: number | undefined, maxOi: number): string {
  if (oi === undefined || oi <= 0 || maxOi <= 0) {
    return muted('·'.repeat(BAR_W));
  }
  const filled = Math.max(1, Math.min(BAR_W, Math.round((oi / maxOi) * BAR_W)));
  return ok('▮'.repeat(filled)) + muted('▯'.repeat(BAR_W - filled));
}

function marks(markers: ChainWatchRowView['markers']): string {
  const parts: string[] = [];
  if (markers.includes('ATM')) {
    parts.push(warn('ATM'));
  }
  if (markers.includes('CE_ENTRY')) {
    parts.push(callSide('CE▸'));
  }
  if (markers.includes('PE_ENTRY')) {
    parts.push(putSide('PE▸'));
  }
  if (markers.includes('RES')) {
    parts.push(bad('RES'));
  }
  if (markers.includes('SUP')) {
    parts.push(ok('SUP'));
  }
  if (markers.includes('OPEN')) {
    parts.push(infoBold('OPEN'));
  }
  return fit(parts.length === 0 ? muted('·') : parts.join(' '), MARKS_W);
}

function strikeCell(row: ChainWatchRowView): string {
  const text = row.strike.toLocaleString('en-IN');
  return fit(row.markers.includes('ATM') ? warn(text) : text, STRIKE_W);
}

function tone(text: string, passes: boolean): string {
  return passes ? ok(text) : bad(text);
}

function quoteCells(leg: ChainWatchLegView, maxOi: number): string[] {
  return [
    fit(tone(price(leg.bid), leg.passesGate), PX_W),
    fit(tone(price(leg.ask), leg.passesGate), PX_W),
    fit(tone(leg.spreadPct === undefined ? '—' : `${leg.spreadPct.toFixed(1)}%`, leg.passesGate), SPR_W),
    oiBar(leg.openInterest, maxOi),
    fit(tone(compactOi(leg.openInterest), leg.passesGate), OI_W),
  ];
}

function quoteHead(side: 'call' | 'put'): string[] {
  const bid = side === 'call' ? callSide('BID') : putSide('BID');
  return [fit(bid, PX_W), fit(muted('ASK'), PX_W), fit(muted('SPR'), SPR_W), fit(muted('OI'), BAR_W), fit('', OI_W)];
}

function headerCells(side: 'call' | 'put' | 'both'): string[] {
  const lead = [fit(muted('STRIKE'), STRIKE_W), fit(muted('MARKS'), MARKS_W)];
  if (side === 'both') {
    return [...lead, ...quoteHead('call'), ...quoteHead('put')];
  }
  return [...lead, ...quoteHead(side)];
}

function biasLensLabel(watch: ChainWatchView): string {
  if (watch.marketBias === 'BULLISH') {
    return callSide(' CE lens · ST↑ EMA↑');
  }
  if (watch.marketBias === 'BEARISH') {
    return putSide(' PE lens · ST↓ EMA↓');
  }
  return muted(' CE + PE · trend mixed');
}

function scrollHint(watch: ChainWatchView): string {
  if (watch.strikeScrollMin === watch.strikeScrollMax) {
    return '';
  }
  if (watch.strikeScroll === 0) {
    return muted(' · window centered');
  }
  const atMin = watch.strikeScroll <= watch.strikeScrollMin;
  const atMax = watch.strikeScroll >= watch.strikeScrollMax;
  const pos = watch.strikeScroll > 0 ? ` · +${watch.strikeScroll} strikes` : ` · ${watch.strikeScroll} strikes`;
  const edge = atMin ? ' ⟨' : atMax ? ' ⟩' : '';
  return muted(`${pos}${edge}`);
}

function statusLine(watch: ChainWatchView, agent: AgentView | undefined, inner: number): string {
  if (watch.status === 'loading' || watch.status === 'idle') {
    return muted(fit('fetching option chain from Dhan…', inner));
  }
  if (watch.status === 'waiting_spot') {
    return muted(fit('waiting for a live index tick before anchoring strikes', inner));
  }
  if (watch.status === 'error') {
    return bad(fit(watch.error ?? 'chain unavailable', inner));
  }
  const age =
    watch.fetchedAgeMs === undefined ? '' : watch.fetchedAgeMs < 2000 ? ok(' fresh') : warn(` ${Math.round(watch.fetchedAgeMs / 1000)}s ago`);
  const spot = watch.spot === undefined ? '—' : emphasisSpot(watch.spot);
  const signal =
    agent?.lastSignal?.direction === 'BULLISH' ? callSide(' last signal ↑') : agent?.lastSignal?.direction === 'BEARISH' ? putSide(' last signal ↓') : '';
  return fit(`spot ${spot}   ATM ${warn(watch.atmStrike?.toLocaleString('en-IN') ?? '—')}   ${watch.expiry ?? '—'}${age}${biasLensLabel(watch)}${scrollHint(watch)}${signal}`, inner);
}

function emphasisSpot(spot: number): string {
  return ok(spot.toFixed(2));
}

function legend(inner: number, maxSpread: number, minOi: number): string {
  return muted(fit(`green quote passes spread ≤${maxSpread}% and OI ≥${minOi.toLocaleString('en-IN')} · right side is the other wing · ←→ scroll`, inner));
}

const LADDER_W = 70;
const DUAL_W = 111;
const OPPOSITE_W = 40;
const STAT_W = 22;

function legMid(leg: ChainWatchLegView): number | undefined {
  if (leg.bid === undefined || leg.ask === undefined) {
    return undefined;
  }
  return (leg.bid + leg.ask) / 2;
}

function analysisReadings(watch: ChainWatchView, analysis: ChainAnalysis): string[] {
  const scoreText = analysis.sentimentScore >= 0 ? `+${analysis.sentimentScore}` : `${analysis.sentimentScore}`;
  const biasColor = analysis.bias === 'BULLISH' ? callSide : analysis.bias === 'BEARISH' ? putSide : muted;
  return [
    `straddle ${analysis.straddlePremium.toFixed(1)}`,
    analysis.pcr >= 1 ? putSide(`PCR ${analysis.pcr.toFixed(2)} (${analysis.atmPcr.toFixed(2)})`) : callSide(`PCR ${analysis.pcr.toFixed(2)} (${analysis.atmPcr.toFixed(2)})`),
    `R ${analysis.callResistance.strike} (+${Math.max(0, analysis.headroomCe).toFixed(0)})`,
    `S ${analysis.putSupport.strike} (-${Math.max(0, analysis.headroomPe).toFixed(0)})`,
    biasColor(`Score ${scoreText} ${analysis.bias}`),
  ];
}

function fallbackReadings(watch: ChainWatchView): string[] {
  const atm = watch.rows.find((row) => row.markers.includes('ATM'));
  const callMid = atm === undefined ? undefined : legMid(atm.call);
  const putMid = atm === undefined ? undefined : legMid(atm.put);
  const straddle = callMid === undefined || putMid === undefined ? undefined : callMid + putMid;
  const callOi = watch.rows.reduce((sum, row) => sum + (row.call.openInterest ?? 0), 0);
  const putOi = watch.rows.reduce((sum, row) => sum + (row.put.openInterest ?? 0), 0);
  const pcr = callOi > 0 ? putOi / callOi : undefined;
  const delta = watch.spot !== undefined && watch.atmStrike !== undefined ? watch.spot - watch.atmStrike : undefined;
  const entryStrike = watch.marketBias === 'BEARISH' ? watch.bearishEntryStrike : watch.bullishEntryStrike;
  const entry = watch.rows.find((row) => row.strike === entryStrike);
  const entryLeg = watch.marketBias === 'BEARISH' ? entry?.put : entry?.call;
  const vsAtm = delta === undefined ? 'vs ATM —' : delta < 0 ? putSide(`vs ATM ${delta.toFixed(1)}`) : callSide(`vs ATM +${delta.toFixed(1)}`);
  return [
    straddle === undefined ? 'straddle —' : `straddle ${straddle.toFixed(1)}`,
    pcr === undefined ? 'PCR —' : pcr >= 1 ? putSide(`PCR ${pcr.toFixed(2)}`) : callSide(`PCR ${pcr.toFixed(2)}`),
    vsAtm,
    entryLeg === undefined ? 'entry —' : entryLeg.passesGate ? ok('entry pass') : bad('entry fail'),
    `OI win ${compactOi(Math.max(callOi, putOi))}`,
  ];
}

function readings(watch: ChainWatchView): string[] {
  return watch.analysis !== undefined ? analysisReadings(watch, watch.analysis) : fallbackReadings(watch);
}

function appendLadder(lines: string[], watch: ChainWatchView, inner: number): void {
  const lens = watch.marketBias === 'BULLISH' ? 'call' : watch.marketBias === 'BEARISH' ? 'put' : 'both';
  const other = lens === 'call' ? 'put' : lens === 'put' ? 'call' : undefined;
  const stats = readings(watch);
  const midHead = other === undefined ? '' : quoteHead(other).join(' ');
  lines.push(pane(headerCells(lens).join(' '), midHead, muted('READING'), inner, other !== undefined));
  watch.rows.forEach((row, index) => {
    const leg = lens === 'put' ? row.put : row.call;
    const left =
      lens === 'both'
        ? [strikeCell(row), marks(row.markers), ...quoteCells(row.call, watch.maxOpenInterest), ...quoteCells(row.put, watch.maxOpenInterest)]
        : [strikeCell(row), marks(row.markers), ...quoteCells(leg, watch.maxOpenInterest)];
    const mid = other === undefined ? '' : quoteCells(other === 'call' ? row.call : row.put, watch.maxOpenInterest).join(' ');
    lines.push(pane(left.join(' '), mid, stats[index] ?? '', inner, other !== undefined));
  });
}

function pane(left: string, mid: string, stat: string, inner: number, singleWing: boolean): string {
  const rule = muted(' │ ');
  const leftW = singleWing ? LADDER_W : DUAL_W;
  const body = singleWing ? fit(left, leftW) + rule + fit(mid, OPPOSITE_W) : fit(left, leftW);
  // Spare width stays after the reading so the column is not pushed to the far edge.
  return fit(body + rule + fit(stat, STAT_W), inner);
}

export function chainWatchLines(
  watch: ChainWatchView | undefined,
  agent: AgentView | undefined,
  inner: number,
  maxSpreadPct: number,
  minOpenInterest: number,
): string[] {
  const title = watch === undefined ? 'OPTION CHAIN' : `OPTION CHAIN · ${watch.symbol}`;
  const lines: string[] = [fit(infoBold(title), inner)];
  if (watch === undefined) {
    lines.push(muted(fit('select an underlying with ↑↓', inner)));
    while (lines.length < CHAIN_PANEL_ROWS) {
      lines.push(fit('', inner));
    }
    return lines;
  }
  lines.push(statusLine(watch, agent, inner));
  if (watch.status === 'ready' && watch.rows.length > 0) {
    appendLadder(lines, watch, inner);
    lines.push(legend(inner, maxSpreadPct, minOpenInterest));
  } else {
    lines.push(muted(fit('ladder appears once the chain loads', inner)));
  }
  while (lines.length < CHAIN_PANEL_ROWS) {
    lines.push(fit('', inner));
  }
  return lines.slice(0, CHAIN_PANEL_ROWS);
}
