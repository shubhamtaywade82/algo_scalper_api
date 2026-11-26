import { strict as assert } from 'node:assert';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { loadYamlConfig } from '../src/config.js';
import { TRADE_STATES, TRANSITIONS } from '../src/domain/fsm.js';
import { COCKPIT_KEYS } from '../src/ui/keymap.js';

/**
 * The docs are checked against the code they describe, so a key table, a default, a state diagram or a
 * script name cannot drift from the behaviour without a test failing. Each check reads source text; none runs
 * the agent or touches the network.
 */
const ROOT = fileURLToPath(new URL('..', import.meta.url));
const read = (path: string): string => readFileSync(join(ROOT, path), 'utf8');

function markdownUnder(dir: string): string[] {
  const found: string[] = [];
  for (const name of readdirSync(join(ROOT, dir))) {
    const path = join(dir, name);
    if (statSync(join(ROOT, path)).isDirectory()) {
      found.push(...markdownUnder(path));
    } else if (name.endsWith('.md')) {
      found.push(path);
    }
  }
  return found;
}

const DOCS = ['README.md', 'CLAUDE.md', ...markdownUnder('docs')];

/** The text under a heading, up to the next heading of the same or a higher level. */
function section(markdown: string, heading: string): string {
  const lines = markdown.split('\n');
  const start = lines.findIndex((line) => line === heading);
  assert.notEqual(start, -1, `heading not found: ${heading}`);
  const level = /^#+/.exec(heading)?.[0].length ?? 2;
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => {
    const match = /^(#+) /.exec(line);
    return match !== null && (match[1] ?? '').length <= level;
  });
  return (end === -1 ? rest : rest.slice(0, end)).join('\n');
}

/** Body rows of the first markdown table in a section, as trimmed cells. The header row is dropped. */
function tableRows(text: string): string[][] {
  return text
    .split('\n')
    .filter((line) => line.startsWith('|') && !/^\|\s*-+/.test(line))
    .map((line) => line.split('|').slice(1, -1).map((cell) => cell.trim()))
    .slice(1);
}

/** A key or value written the way a reader writes it: no backticks, no spaces. */
const token = (text: string): string => text.replace(/[`\s]/g, '');

type Setting = string | number | boolean;

/** Reads a raw setting the way config.ts reads a value of the same type, so 'off' and false compare equal. */
function asSetting(raw: string, expected: Setting): Setting {
  if (typeof expected === 'boolean') {
    if (['true', '1', 'on', 'yes'].includes(raw.toLowerCase())) return true;
    if (['false', '0', 'off', 'no'].includes(raw.toLowerCase())) return false;
    return raw;
  }
  if (typeof expected === 'number') return raw === '' ? Number.NaN : Number(raw);
  return raw;
}

/** Every default that config.ts gives a setting read through text, optionalText, number, flag or minuteOfDay. */
function codeDefaults(): Map<string, Setting> {
  const source = read('src/config.ts');
  const defaults = new Map<string, Setting>();
  for (const match of source.matchAll(/\b(number|flag|text|minuteOfDay)\(env, '([A-Z][A-Z0-9_]+)', (?:'([^']*)'|([^,)\s]+))/g)) {
    const kind = match[1] ?? '';
    const key = match[2] ?? '';
    const literal = match[3] ?? match[4] ?? '';
    if (kind === 'flag') {
      defaults.set(key, literal === 'true');
    } else if (kind === 'number') {
      defaults.set(key, Number(literal.replace(/_/g, '')));
    } else {
      defaults.set(key, literal);
    }
  }
  // The posture default is a chain of fallbacks, not a single call, so it is read by its own pattern.
  const posture = /optionalText\(env, 'STRATEGY_POSTURE'\) \?\? optionalText\(env, 'POSTURE'\) \?\? '([a-z]+)'/.exec(source);
  if (posture !== null) {
    defaults.set('STRATEGY_POSTURE', posture[1] ?? '');
  }
  return defaults;
}

/** The settings .env.example names: uncommented (active) or commented (documented, not set). */
function exampleSettings(): Map<string, { commented: boolean; value: string }> {
  const settings = new Map<string, { commented: boolean; value: string }>();
  for (const line of read('.env.example').split('\n')) {
    const match = /^(#\s*)?([A-Z][A-Z0-9_]+)\s*=(.*)$/.exec(line);
    if (match === null) continue;
    settings.set(match[2] ?? '', { commented: match[1] !== undefined, value: (match[3] ?? '').split('#')[0]?.trim() ?? '' });
  }
  return settings;
}

describe('documentation matches the repository', () => {
  it('names only npm scripts that package.json defines', () => {
    const scripts = Object.keys((JSON.parse(read('package.json')) as { scripts: Record<string, string> }).scripts);
    for (const doc of DOCS) {
      for (const match of read(doc).matchAll(/npm run ([A-Za-z0-9:_.-]+)/g)) {
        assert.ok(scripts.includes(match[1] ?? ''), `${doc} names npm run ${match[1]}, which package.json does not define`);
      }
    }
  });

  it('names only repository paths that exist, apart from the ones it describes as pending or removed', () => {
    const described = new Set([
      'docs/sandbox', // OTA-106b: recordings land here once Dhan sandbox credentials exist
      'src/binance', 'src/coindcx', 'src/strategies/smc-ml', 'src/minicpm', 'src/learning', 'src/backtesting',
      'src/agents', 'src/decision', 'src/position', // removed from crypto-trading-agent (README "What was removed")
    ]);
    const pathPattern = /(?:^|[\s`(["'])((?:src|tests|scripts|docs)\/[A-Za-z0-9_./-]*[A-Za-z0-9_-]|\.mcp\.json|\.env\.example|docker-compose\.yml)/g;
    for (const doc of DOCS) {
      for (const match of read(doc).matchAll(pathPattern)) {
        const path = match[1] ?? '';
        if (described.has(path)) continue;
        assert.ok(existsSync(join(ROOT, path)), `${doc} names ${path}, which does not exist`);
      }
    }
  });

  it('lists in .env.example every setting the code reads, and nothing the code does not read', () => {
    const codeKeys = new Set([...read('src/config.ts').matchAll(/(?:text|optionalText|number|flag|minuteOfDay)\(env, '([A-Z][A-Z0-9_]+)'/g)].map((m) => m[1] ?? ''));
    // Accepted names kept for compatibility: they are not documented as settings.
    const aliases = new Set(['CONFIG_PATH', 'POSTURE', 'STRATEGY_ENABLED', 'EVENT_LOG_PATH']);
    const example = exampleSettings();
    for (const key of codeKeys) {
      if (aliases.has(key)) continue;
      assert.ok(example.has(key), `the code reads ${key}, and .env.example does not list it`);
    }
    for (const key of example.keys()) {
      assert.ok(codeKeys.has(key) || key === 'UI' || key === 'POSTGRES_PASSWORD', `.env.example lists ${key}, which the code does not read`);
    }
  });

  it('sets each uncommented .env.example value to the code default, where the code has one', () => {
    const defaults = codeDefaults();
    for (const [key, setting] of exampleSettings()) {
      if (setting.commented || !defaults.has(key)) continue;
      const expected = defaults.get(key);
      assert.ok(expected !== undefined);
      assert.equal(
        asSetting(setting.value, expected),
        expected,
        `.env.example sets ${key}=${setting.value}; the code default is ${String(expected)}`,
      );
    }
  });

  it('states in README the code default and the paper-profile value of each setting it lists', () => {
    const defaults = codeDefaults();
    const profile = loadYamlConfig(join(ROOT, 'config.paper.yml'));
    const rows = tableRows(section(read('README.md'), '### Defaults and the paper profile'));
    assert.ok(rows.length >= 20, 'the defaults table should list the main settings');
    for (const cells of rows) {
      const [, envCell = '', defaultCell = '', paperCell = ''] = cells;
      const key = token(envCell);
      assert.ok(defaults.has(key), `README names ${key}, which config.ts gives no default`);
      const expected = defaults.get(key);
      assert.ok(expected !== undefined);
      assert.equal(asSetting(token(defaultCell), expected), expected, `README gives ${key} the default ${defaultCell}; config.ts uses ${String(expected)}`);
      const profileValue = profile[key];
      if (paperCell === '—') {
        assert.equal(profileValue, undefined, `README says the paper profile does not set ${key}, but config.paper.yml sets it`);
      } else {
        assert.ok(profileValue !== undefined, `README gives ${key} a paper value, but config.paper.yml does not set it`);
        assert.equal(
          asSetting(token(paperCell), expected),
          asSetting(profileValue, expected),
          `README gives ${key} the paper value ${paperCell}; config.paper.yml sets ${profileValue}`,
        );
      }
    }
  });

  it('lists in README every cockpit key, with the second-press rule the code applies', () => {
    const rows = tableRows(section(read('README.md'), '## Operator cockpit'));
    assert.equal(rows.length, COCKPIT_KEYS.length, 'the README key table and src/ui/keymap.ts list different keys');
    for (const key of COCKPIT_KEYS) {
      const row = rows.find((cells) => token(cells[0] ?? '') === token(key.display));
      assert.ok(row !== undefined, `README does not list the key ${key.display}`);
      const readmeSaysSecondPress = (row?.[2] ?? '').toLowerCase() === 'yes';
      assert.equal(readmeSaysSecondPress, key.secondPress, `README says ${key.display} needs a second press: ${row?.[2]}; the code says ${key.secondPress}`);
    }
  });

  it('draws the trade lifecycle in ARCHITECTURE.md with exactly the transitions in src/domain/fsm.ts', () => {
    const block = /```mermaid\n(stateDiagram-v2\n[\s\S]*?)```/.exec(read('docs/ARCHITECTURE.md'))?.[1] ?? '';
    assert.ok(block.length > 0, 'the state diagram is missing from docs/ARCHITECTURE.md');
    const drawn: string[] = [];
    for (const line of block.split('\n')) {
      const match = /^\s*(\[\*\]|[A-Z_]+)\s*-->\s*([A-Z_]+)(?:\s*:\s*(.*))?$/.exec(line);
      if (match === null || match[1] === '[*]') continue;
      const label = (match[3] ?? '').replace(/\(.*?\)/g, '').trim();
      for (const event of label.split(' / ')) {
        drawn.push(`${match[1]}|${event.trim()}|${match[2]}`);
      }
    }
    const declared: string[] = [];
    for (const [from, events] of Object.entries(TRANSITIONS)) {
      for (const [event, to] of Object.entries(events)) {
        declared.push(`${from}|${event}|${String(to)}`);
      }
    }
    assert.deepEqual([...drawn].sort(), [...declared].sort(), 'the diagram and the transition table differ');
    assert.deepEqual(Object.keys(TRANSITIONS).sort(), [...TRADE_STATES].sort());
  });

  it('does not repeat the statements that were checked against the code and found wrong', () => {
    const stale: Record<string, string[]> = {
      'README.md': ['has been calibrated against data here', 'default full packet mode', 'only reads state, except for these three actions', 'two venues'],
      'docs/ARCHITECTURE.md': ['Three operator actions'],
      'docs/TRAILING_STOPS.md': ['implemented on branch `feat/trailing-stop-research`'],
      'docs/ROADMAP.md': ['ccr-e5f824c3-nhd407'],
    };
    for (const [doc, phrases] of Object.entries(stale)) {
      for (const phrase of phrases) {
        assert.ok(!read(doc).includes(phrase), `${doc} still says: ${phrase}`);
      }
    }
  });

  it('writes no test counts into prose', () => {
    for (const doc of DOCS) {
      assert.doesNotMatch(read(doc), /\b\d{3,}\s+(tests?|passing|passed)\b/i, `${doc} writes a test count`);
    }
  });
});
