import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

const target = process.argv[2] || 'all';

if (target === 'glossary' || target === 'all') {
  const glossaryPath = path.join(rootDir, 'GLOSSARY.md');
  assert.ok(fs.existsSync(glossaryPath), 'AssertionError: GLOSSARY.md must exist at repository root');
  const content = fs.readFileSync(glossaryPath, 'utf8');
  assert.ok(content.includes('## Underlyings'), 'AssertionError: GLOSSARY.md must define Underlyings');
  assert.ok(content.includes('## Regimes'), 'AssertionError: GLOSSARY.md must define Regimes');
  assert.ok(content.includes('## Postures'), 'AssertionError: GLOSSARY.md must define Postures');
  assert.ok(content.includes('## Trade Intents'), 'AssertionError: GLOSSARY.md must define Trade Intents');
  assert.ok(content.includes('## Risk Stops'), 'AssertionError: GLOSSARY.md must define Risk Stops');
  console.log('✓ GLOSSARY.md verification passed');
}

if (target === 'adrs' || target === 'all') {
  const adrDir = path.join(rootDir, 'docs/adr');
  assert.ok(fs.existsSync(adrDir), 'AssertionError: docs/adr directory must exist');
  const adrFiles = ['ADR-001-polyglot-signal-execution-split.md', 'ADR-002-intraday-session-cutoffs.md', 'ADR-003-option-long-time-stop-invariant.md'];
  for (const f of adrFiles) {
    const full = path.join(adrDir, f);
    assert.ok(fs.existsSync(full), `AssertionError: ${f} must exist in docs/adr`);
    const content = fs.readFileSync(full, 'utf8');
    assert.ok(content.includes('## Context'), `AssertionError: ${f} must have Context`);
    assert.ok(content.includes('## Decision'), `AssertionError: ${f} must have Decision`);
    assert.ok(content.includes('## Consequences'), `AssertionError: ${f} must have Consequences`);
  }
  console.log('✓ ADRs verification passed');
}
