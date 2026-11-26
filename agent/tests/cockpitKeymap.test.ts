import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { STRATEGY_CATALOG } from '../src/strategy/session.js';
import { COCKPIT_KEYS, STRATEGY_KEYS } from '../src/ui/keymap.js';

describe('cockpit key table', () => {
  it('needs a second press for every key that changes trading or the session, and none for navigation', () => {
    assert.deepEqual(
      COCKPIT_KEYS.filter((key) => key.secondPress).map((key) => key.display).sort(),
      ['1–5', 'c', 'd', 'k', 'p', 'r', 's, Ctrl+C', 't'].sort(),
    );
    assert.deepEqual(
      COCKPIT_KEYS.filter((key) => !key.secondPress).map((key) => key.display).sort(),
      ['?', '[ ]', '← →', '↑ ↓'].sort(),
    );
  });

  it('maps keys 1 to 5 onto the five live strategy families and no research family', () => {
    const live = STRATEGY_CATALOG.filter((strategy) => !('research' in strategy)).map((strategy) => strategy.id);
    assert.deepEqual(Object.keys(STRATEGY_KEYS).sort(), ['1', '2', '3', '4', '5']);
    assert.deepEqual(Object.values(STRATEGY_KEYS).sort(), [...live].sort());
  });

  it('gives every key a distinct display token and help token', () => {
    assert.equal(new Set(COCKPIT_KEYS.map((key) => key.display)).size, COCKPIT_KEYS.length);
    assert.equal(new Set(COCKPIT_KEYS.map((key) => key.help)).size, COCKPIT_KEYS.length);
  });
});
