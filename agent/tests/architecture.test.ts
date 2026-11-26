import { strict as assert } from 'node:assert';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

/**
 * The plane boundary from docs/DECISIONS.md (ADR-001): research and the pure market/strategy/options code must never
 * reach the broker, execution or runtime layers, and only the two venue adapters may write to the broker.
 */
const SRC = fileURLToPath(new URL('../src', import.meta.url));

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      return sourceFiles(path);
    }
    return name.endsWith('.ts') || name.endsWith('.tsx') ? [path] : [];
  });
}

const relPath = (path: string): string => relative(SRC, path).split('\\').join('/');
const filesUnder = (folders: readonly string[]) => sourceFiles(SRC).filter((path) => folders.some((folder) => relPath(path).startsWith(`${folder}/`)));

/** Any relative import that climbs out of a folder into the broker, execution or runtime layers. */
const FORBIDDEN_IMPORT = /from\s+['"](?:\.\.\/)+(?:dhan|execution|runtime)\//;
/** A write to the broker through the SDK's order, super-order or trader-control clients. */
const BROKER_WRITE = /\b(?:orders|superOrders|traderControls)\.(?:place|cancel|modify|setKillSwitch)\(/;
const VENUE_ADAPTERS = ['dhan/liveExecution.ts', 'dhan/sandboxGateway.ts'];

describe('plane boundary (ADR-001)', () => {
  it('research, strategy, options and market code never import the broker, execution or runtime layers', () => {
    const offenders = filesUnder(['research', 'strategy', 'options', 'market'])
      .filter((path) => FORBIDDEN_IMPORT.test(readFileSync(path, 'utf8')))
      .map(relPath);
    assert.deepEqual(offenders, []);
  });

  it('only the venue adapters write to the broker', () => {
    const writers = sourceFiles(SRC)
      .filter((path) => BROKER_WRITE.test(readFileSync(path, 'utf8')))
      .map(relPath)
      .sort();
    assert.deepEqual(writers, [...VENUE_ADAPTERS].sort());
  });

  it('the boundary patterns match real code, so the checks above cannot pass by matching nothing', () => {
    assert.ok(filesUnder(['research']).length > 0, 'research sources were found');
    assert.ok(
      sourceFiles(SRC).some((path) => FORBIDDEN_IMPORT.test(readFileSync(path, 'utf8'))),
      'the import pattern matches at least one layer that is allowed to import the broker',
    );
    for (const adapter of VENUE_ADAPTERS) {
      assert.ok(BROKER_WRITE.test(readFileSync(join(SRC, adapter), 'utf8')), `${adapter} contains a broker write`);
    }
  });
});
