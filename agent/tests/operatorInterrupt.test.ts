import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { OPERATOR_INTERRUPT_ARM_MS, operatorInterrupt, resetOperatorInterrupt } from '../src/runtime/operatorInterrupt.js';

describe('operatorInterrupt', () => {
  it('arms then confirms inside the window', () => {
    resetOperatorInterrupt();
    assert.equal(operatorInterrupt(1_000), 'armed');
    assert.equal(operatorInterrupt(1_000), 'armed', 'duplicate same-ms is ignored');
    assert.equal(operatorInterrupt(1_500), 'confirmed');
  });

  it('re-arms after the window elapses', () => {
    resetOperatorInterrupt();
    assert.equal(operatorInterrupt(0), 'armed');
    assert.equal(operatorInterrupt(OPERATOR_INTERRUPT_ARM_MS + 1), 'armed');
  });
});
