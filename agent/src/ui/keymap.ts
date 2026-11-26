import type { StrategyId } from '../strategy/session.js';

/**
 * Every key the operator cockpit answers to. The README key table, the on-screen footer and the in-app key
 * line are built from or checked against this list, so they cannot drift from what the keys do.
 *
 * `secondPress` means the action runs only on a second press inside the confirmation window. A first press
 * shows the prompt and changes nothing. Navigation keys never change trading state and never ask.
 */
export interface CockpitKey {
  /** How the key is written in the README key table (backticks and spaces are ignored when matching). */
  readonly display: string;
  /** Short label for the footer and the in-app key line. Unique across the table. */
  readonly help: string;
  readonly secondPress: boolean;
}

export const COCKPIT_KEYS: readonly CockpitKey[] = [
  { display: '↑ ↓', help: '↑↓ select', secondPress: false },
  { display: '← →', help: '←→ chain', secondPress: false },
  { display: '[ ]', help: '[] pos', secondPress: false },
  { display: 'p', help: 'p posture', secondPress: true },
  { display: '1–5', help: '1-5 strat', secondPress: true },
  { display: 't', help: 't test', secondPress: true },
  { display: 'c', help: 'c close', secondPress: true },
  { display: 'k', help: 'k block', secondPress: true },
  { display: 's, Ctrl+C', help: 's/Ctrl+C stop', secondPress: true },
  { display: 'r', help: 'r reset dd', secondPress: true },
  { display: 'd', help: 'd brake', secondPress: true },
  { display: '?', help: '? help', secondPress: false },
];

/** Keys 1 to 5 toggle the five live strategy families. The research family prev_day is not on a key. */
export const STRATEGY_KEYS: Readonly<Record<string, StrategyId>> = {
  '1': 'range',
  '2': 'trend',
  '3': 'ema_cross',
  '4': 'momentum',
  '5': 'continuation',
};
