import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { IllegalTransitionError, TRADE_EVENTS, TRADE_STATES, TRANSITIONS, TradeStateMachine } from '../src/domain/fsm.js';

describe('TradeStateMachine', () => {
  it('walks the full winning lifecycle to IDLE', () => {
    const fsm = new TradeStateMachine(() => 1);
    const path = [
      'SIGNAL_FOUND',
      'ENTRY_SUBMITTED',
      'ENTRY_FILLED',
      'PROTECTION_ARMED',
      'EXIT_SUBMITTED',
      'EXIT_FILLED',
      'CLOSE_ACKNOWLEDGED',
    ] as const;
    for (const event of path) {
      fsm.dispatch(event);
    }
    assert.equal(fsm.state, 'IDLE');
    assert.equal(fsm.history().length, path.length);
  });

  it('throws on any transition the table does not define', () => {
    const fsm = new TradeStateMachine();
    assert.throws(() => fsm.dispatch('ENTRY_FILLED'), IllegalTransitionError);
    assert.equal(fsm.state, 'IDLE', 'a rejected transition must not change state');
  });

  it('rejects an EXIT_FILLED that arrives before an exit was submitted', () => {
    const fsm = new TradeStateMachine();
    fsm.dispatch('SIGNAL_FOUND');
    fsm.dispatch('ENTRY_SUBMITTED');
    fsm.dispatch('ENTRY_FILLED');
    fsm.dispatch('PROTECTION_ARMED');
    assert.throws(() => fsm.dispatch('EXIT_FILLED'), IllegalTransitionError);
  });

  it('sends ambiguous outcomes to HALTED, and only RESET leaves it', () => {
    const fsm = new TradeStateMachine();
    fsm.dispatch('SIGNAL_FOUND');
    fsm.dispatch('ENTRY_SUBMITTED');
    fsm.dispatch('ENTRY_UNCONFIRMED');
    assert.equal(fsm.state, 'HALTED');
    assert.equal(fsm.can('SIGNAL_FOUND'), false);
    assert.equal(fsm.can('HALT'), false, 'HALT in HALTED is not a legal no-op');
    fsm.dispatch('RESET');
    assert.equal(fsm.state, 'IDLE');
  });

  it('allows HALT from every active state and never from HALTED', () => {
    for (const state of TRADE_STATES.filter((candidate) => candidate !== 'HALTED')) {
      assert.equal(TRANSITIONS[state].HALT, 'HALTED', `${state} must be haltable`);
    }
    assert.equal(TRANSITIONS.HALTED.HALT, undefined);
  });

  it('declares a transition target for every state in the table', () => {
    for (const state of TRADE_STATES) {
      assert.ok(TRANSITIONS[state] !== undefined, `missing row for ${state}`);
      for (const [event, target] of Object.entries(TRANSITIONS[state])) {
        assert.ok((TRADE_EVENTS as readonly string[]).includes(event), `unknown event ${event}`);
        assert.ok((TRADE_STATES as readonly string[]).includes(target as string), `unknown target ${target}`);
      }
    }
  });

  it('never allows a rejected exit to skip risk management', () => {
    assert.equal(TRANSITIONS.EXIT_PENDING.EXIT_REJECTED, 'RISK_MANAGEMENT_ACTIVE');
  });
});
