import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

/**
 * OTA-312. The broker SDK is pinned exactly, and the docs name the version that is installed. A broker behaviour
 * assumed from one SDK version must not be documented against another.
 */
const ROOT = fileURLToPath(new URL('..', import.meta.url));
const read = (path: string): string => readFileSync(join(ROOT, path), 'utf8');

describe('SDK pin and documentation (OTA-312)', () => {
  it('pins the DhanHQ SDK exactly, and the pin matches the installed package', () => {
    const declared = (JSON.parse(read('package.json')) as { dependencies: Record<string, string> }).dependencies['@nemesis-oss/dhanhq-sdk'];
    assert.match(declared ?? '', /^\d+\.\d+\.\d+$/, `expected an exact version, found ${declared}`);
    const installed = (JSON.parse(readFileSync(join(ROOT, 'node_modules/@nemesis-oss/dhanhq-sdk/package.json'), 'utf8')) as { version: string }).version;
    assert.equal(declared, installed);
  });

  it('does not document 1.3.0 as the installed SDK', () => {
    for (const path of ['README.md', 'docs/PERSISTENCE.md']) {
      assert.doesNotMatch(read(path), /1\.3\.0/, `${path} still names 1.3.0`);
    }
  });

  it('describes the rolling-option endpoint with the version it was written against, and names the installed one', () => {
    const timeMachine = read('docs/TIME_MACHINE.md');
    assert.match(timeMachine, /1\.3\.0-era/);
    assert.match(timeMachine, /2\.0\.1/);
  });

  it('does not describe the adaptive SuperTrend as ML-based', () => {
    assert.doesNotMatch(read('src/market/indicators.ts'), /ML-based/);
  });
});
