import type { Direction } from '../domain/types.js';
import { minStrikeStep, nearestAtmStrike, type ChainSnapshot } from './selector.js';

export interface OiWall {
  readonly strike: number;
  readonly oi: number;
  readonly distance: number;
}

export interface ChainAnalysis {
  readonly spot: number;
  readonly atmStrike: number;
  readonly pcr: number;
  readonly atmPcr: number;
  readonly callResistance: OiWall;
  readonly putSupport: OiWall;
  readonly headroomCe: number;
  readonly headroomPe: number;
  readonly straddlePremium: number;
  readonly expectedRange: { readonly lower: number; readonly upper: number };
  readonly sentimentScore: number;
  readonly bias: 'BULLISH' | 'BEARISH' | 'NEUTRAL';
  readonly verdict: string;
}

export interface ConfluenceCheckResult {
  readonly ok: boolean;
  readonly reason?: string | undefined;
}

function analyzePcr(chain: ChainSnapshot, atmStrike: number, strikeStep: number): { pcr: number; atmPcr: number; callVolume: number; putVolume: number } {
  let callOi = 0;
  let putOi = 0;
  let atmCallOi = 0;
  let atmPutOi = 0;
  let callVolume = 0;
  let putVolume = 0;
  const atmRadius = strikeStep * 3;

  for (const s of chain.strikes) {
    const cOi = s.call?.oi ?? 0;
    const pOi = s.put?.oi ?? 0;
    callOi += cOi;
    putOi += pOi;
    callVolume += s.call?.volume ?? 0;
    putVolume += s.put?.volume ?? 0;

    if (Math.abs(s.strike - atmStrike) <= atmRadius) {
      atmCallOi += cOi;
      atmPutOi += pOi;
    }
  }

  const pcr = callOi > 0 ? Number((putOi / callOi).toFixed(2)) : 1.0;
  const atmPcr = atmCallOi > 0 ? Number((atmPutOi / atmCallOi).toFixed(2)) : pcr;
  return { pcr, atmPcr, callVolume, putVolume };
}

function findOiWalls(chain: ChainSnapshot, spot: number): { callResistance: OiWall; putSupport: OiWall } {
  let maxCallStrike = spot;
  let maxCallOi = 0;
  let maxPutStrike = spot;
  let maxPutOi = 0;

  for (const s of chain.strikes) {
    const cOi = s.call?.oi ?? 0;
    const pOi = s.put?.oi ?? 0;
    if (cOi > maxCallOi) {
      maxCallOi = cOi;
      maxCallStrike = s.strike;
    }
    if (pOi > maxPutOi) {
      maxPutOi = pOi;
      maxPutStrike = s.strike;
    }
  }

  return {
    callResistance: { strike: maxCallStrike, oi: maxCallOi, distance: Number((maxCallStrike - spot).toFixed(1)) },
    putSupport: { strike: maxPutStrike, oi: maxPutOi, distance: Number((spot - maxPutStrike).toFixed(1)) },
  };
}

function calculateStraddle(chain: ChainSnapshot, atmStrike: number): number {
  const row = chain.strikes.find((s) => s.strike === atmStrike);
  if (!row) return 0;
  const callMid = (row.call?.bid !== undefined && row.call?.ask !== undefined) ? (row.call.bid + row.call.ask) / 2 : (row.call?.ltp ?? 0);
  const putMid = (row.put?.bid !== undefined && row.put?.ask !== undefined) ? (row.put.bid + row.put.ask) / 2 : (row.put?.ltp ?? 0);
  return Number((callMid + putMid).toFixed(1));
}

function computeSentiment(
  pcr: number,
  atmPcr: number,
  walls: { callResistance: OiWall; putSupport: OiWall },
  vol: { callVolume: number; putVolume: number },
): { score: number; bias: 'BULLISH' | 'BEARISH' | 'NEUTRAL'; verdict: string } {
  let score = 0;
  if (pcr >= 1.2) score += 25; else if (pcr >= 1.0) score += 10; else if (pcr <= 0.7) score -= 25; else if (pcr <= 0.9) score -= 10;
  if (atmPcr >= 1.2) score += 20; else if (atmPcr <= 0.8) score -= 20;

  if (walls.callResistance.distance <= 0) score += 20;
  else if (walls.callResistance.distance > 50) score += 15;
  else if (walls.callResistance.distance < 15) score -= 25;

  if (walls.putSupport.distance <= 0) score -= 20;
  else if (walls.putSupport.distance > 50) score -= 15;
  else if (walls.putSupport.distance < 15) score += 25;

  if (vol.callVolume > vol.putVolume * 1.3) score += 15;
  if (vol.putVolume > vol.callVolume * 1.3) score -= 15;

  score = Math.max(-100, Math.min(100, score));
  const bias: 'BULLISH' | 'BEARISH' | 'NEUTRAL' = score >= 20 ? 'BULLISH' : score <= -20 ? 'BEARISH' : 'NEUTRAL';
  const verdict = `${bias} (score ${score > 0 ? '+' : ''}${score}, PCR ${pcr}, ATM PCR ${atmPcr})`;
  return { score, bias, verdict };
}

export function analyzeOptionChain(chain: ChainSnapshot, spot: number): ChainAnalysis {
  const strikes = [...new Set(chain.strikes.map((s) => s.strike))].sort((a, b) => a - b);
  const atmStrike = nearestAtmStrike(spot, strikes) ?? spot;
  const step = minStrikeStep(strikes) ?? 50;
  const pcrData = analyzePcr(chain, atmStrike, step);
  const walls = findOiWalls(chain, spot);
  const straddlePremium = calculateStraddle(chain, atmStrike);
  const sentiment = computeSentiment(pcrData.pcr, pcrData.atmPcr, walls, pcrData);

  return {
    spot,
    atmStrike,
    pcr: pcrData.pcr,
    atmPcr: pcrData.atmPcr,
    callResistance: walls.callResistance,
    putSupport: walls.putSupport,
    headroomCe: walls.callResistance.distance,
    headroomPe: walls.putSupport.distance,
    straddlePremium,
    expectedRange: {
      lower: Number((atmStrike - straddlePremium).toFixed(1)),
      upper: Number((atmStrike + straddlePremium).toFixed(1)),
    },
    sentimentScore: sentiment.score,
    bias: sentiment.bias,
    verdict: sentiment.verdict,
  };
}

export function checkOptionBuyingConfluence(
  analysis: ChainAnalysis,
  direction: Direction,
  minHeadroomPts = 15,
): ConfluenceCheckResult {
  if (minHeadroomPts > 0) {
    if (direction === 'BULLISH') {
      if (analysis.headroomCe > 0 && analysis.headroomCe < minHeadroomPts) {
        return { ok: false, reason: `spot ${analysis.spot} is only ${analysis.headroomCe.toFixed(1)} pts below major Call resistance at ${analysis.callResistance.strike} (min headroom: ${minHeadroomPts} pts)` };
      }
    } else {
      if (analysis.headroomPe > 0 && analysis.headroomPe < minHeadroomPts) {
        return { ok: false, reason: `spot ${analysis.spot} is only ${analysis.headroomPe.toFixed(1)} pts above major Put support at ${analysis.putSupport.strike} (min headroom: ${minHeadroomPts} pts)` };
      }
    }
  }

  if (direction === 'BULLISH') {
    if (analysis.pcr < 0.55) {
      return { ok: false, reason: `PCR ${analysis.pcr.toFixed(2)} is severely depressed; heavy call writing overhead` };
    }
    return { ok: true };
  }

  if (analysis.pcr > 1.8) {
    return { ok: false, reason: `PCR ${analysis.pcr.toFixed(2)} is extremely elevated; heavy put writing support` };
  }
  return { ok: true };
}
