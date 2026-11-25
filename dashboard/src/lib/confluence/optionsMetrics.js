const IST_DATE = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' });
const LADDER_STRIKES_EACH_SIDE = 3;

export function daysToExpiry(expiry, now = new Date()) {
  return Math.round((Date.parse(expiry) - Date.parse(IST_DATE.format(now))) / 864e5);
}

const legAt = (legs, strike, type) => legs.find((l) => l.strike === strike && l.type === type) || null;
const totalOi = (legs, type) => legs.filter((l) => l.type === type).reduce((sum, l) => sum + (l.oi || 0), 0);

function oiWall(legs, type) {
  let best = null;
  for (const leg of legs) if (leg.type === type && (!best || leg.oi > best.oi)) best = { strike: leg.strike, oi: leg.oi };
  return best;
}

function nearestStrike(strikes, spot) {
  return strikes.reduce((best, s) => (Math.abs(s - spot) < Math.abs(best - spot) ? s : best), strikes[0]);
}

function buildLadder(legs, strikes, atm) {
  const at = strikes.indexOf(atm);
  return strikes.slice(Math.max(0, at - LADDER_STRIKES_EACH_SIDE), at + LADDER_STRIKES_EACH_SIDE + 1)
    .map((strike) => ({ strike, isAtm: strike === atm, ce: legAt(legs, strike, 'CE'), pe: legAt(legs, strike, 'PE') }));
}

/**
 * Reduces an option-chain snapshot to what an options buyer reads off a chart:
 * ATM premiums, straddle-implied move, breakevens, OI walls, PCR and a short strike ladder.
 */
export function deriveOptionsView(chain, now = new Date()) {
  if (!chain?.legs?.length) return null;
  const legs = chain.legs, strikes = [...new Set(legs.map((l) => l.strike))].sort((a, b) => a - b);
  const atm = chain.atm_strike ?? nearestStrike(strikes, chain.spot);
  const ce = legAt(legs, atm, 'CE'), pe = legAt(legs, atm, 'PE');
  const straddle = ce?.ltp > 0 && pe?.ltp > 0 ? ce.ltp + pe.ltp : null;
  const ceOi = totalOi(legs, 'CE');
  return {
    spot: chain.spot, atm, ce, pe, straddle, expiry: chain.expiry, dte: daysToExpiry(chain.expiry, now), stale: !!chain.chain_stale,
    impliedMove: straddle ? { up: chain.spot + straddle, down: chain.spot - straddle } : null,
    breakeven: { ce: ce?.ltp > 0 ? atm + ce.ltp : null, pe: pe?.ltp > 0 ? atm - pe.ltp : null },
    callWall: oiWall(legs, 'CE'), putWall: oiWall(legs, 'PE'),
    pcr: ceOi > 0 ? totalOi(legs, 'PE') / ceOi : null,
    ladder: buildLadder(legs, strikes, atm)
  };
}

/** Price levels worth drawing on the index chart for an options buyer. */
export function optionLevels(view) {
  if (!view) return [];
  const levels = [{ price: view.atm, label: `ATM ${view.atm}`, color: '#E9EFFA', dash: [2, 4] }];
  const add = (price, label, color, dash) => { if (Number.isFinite(price)) levels.push({ price, label, color, dash }); };
  add(view.breakeven.ce, `CE BE ${Math.round(view.breakeven.ce)}`, '#19E3B1', [6, 4]);
  add(view.breakeven.pe, `PE BE ${Math.round(view.breakeven.pe)}`, '#FF4D6D', [6, 4]);
  add(view.impliedMove?.up, `EM+ ${Math.round(view.impliedMove?.up)}`, '#FFB224', [1, 4]);
  add(view.impliedMove?.down, `EM- ${Math.round(view.impliedMove?.down)}`, '#FFB224', [1, 4]);
  add(view.callWall?.strike, `CW ${view.callWall?.strike}`, '#FF4D6D', []);
  add(view.putWall?.strike, `PW ${view.putWall?.strike}`, '#19E3B1', []);
  return levels;
}
