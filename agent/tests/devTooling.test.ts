import { strict as assert } from 'node:assert';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

/**
 * ADR-012. Development tooling is dev-only, exactly pinned and read-first. A code-intelligence server must not gain
 * a runtime dependency, float to an unpinned version, or write to the tree without a permission prompt.
 */
const ROOT = fileURLToPath(new URL('..', import.meta.url));
const read = (path: string): string => readFileSync(join(ROOT, path), 'utf8');
const readJson = <T>(path: string): T => JSON.parse(read(path)) as T;

const SERVER = 'ts-language-mcp';

function sourceFiles(dir: string): string[] {
  return readdirSync(join(ROOT, dir)).flatMap((name) => {
    const path = join(ROOT, dir, name);
    if (statSync(path).isDirectory()) {
      return sourceFiles(relative(ROOT, path));
    }
    return name.endsWith('.ts') || name.endsWith('.tsx') ? [path] : [];
  });
}

describe('development tooling (ADR-012)', () => {
  it('pins the code-intelligence server exactly as a dev dependency, and the pin is the installed version', () => {
    const pkg = readJson<{ dependencies?: Record<string, string>; devDependencies?: Record<string, string> }>('package.json');
    const declared = pkg.devDependencies?.[SERVER];
    assert.match(declared ?? '', /^\d+\.\d+\.\d+$/, `expected an exact version, found ${declared}`);
    assert.equal(pkg.dependencies?.[SERVER], undefined, 'the server is not a runtime dependency');
    assert.equal(readJson<{ version: string }>(`node_modules/${SERVER}/package.json`).version, declared);
  });

  it('starts the server from the installed package, with no floating npx download', () => {
    const { mcpServers } = readJson<{ mcpServers: Record<string, { command: string; args: string[] }> }>('.mcp.json');
    const server = mcpServers[SERVER];
    assert.ok(server, `${SERVER} is configured in .mcp.json`);
    const invocation = [server.command, ...server.args].join(' ');
    assert.doesNotMatch(invocation, /\bnpx\b|@latest/);
    assert.match(invocation, new RegExp(`node_modules/${SERVER}/dist/index\\.js`));
  });

  it('keeps the server and the MCP SDK out of the application and the scripts', () => {
    const offenders = [...sourceFiles('src'), ...sourceFiles('scripts')].filter((path) =>
      /from\s+['"](?:ts-language-mcp|@modelcontextprotocol\/)/.test(readFileSync(path, 'utf8')),
    );
    assert.deepEqual(offenders.map((path) => relative(ROOT, path)), []);
  });

  it('keeps the per-folder tsconfigs that let the server analyse tests and scripts', () => {
    for (const dir of ['tests', 'scripts']) {
      assert.equal(readJson<{ extends?: string }>(`${dir}/tsconfig.json`).extends, '../tsconfig.typecheck.json');
    }
  });

  it('keeps personal Claude settings and the codebase graph out of git', () => {
    const ignore = read('.gitignore');
    assert.match(ignore, /^\.claude\/settings\.local\.json$/m);
    assert.match(ignore, /^graphify-out\/$/m);
  });

  it('pins the codebase graph to one release and runs it offline (ADR-013)', () => {
    const script = read('scripts/graphify.sh');
    assert.match(script, /^GRAPHIFY_VERSION="\d+\.\d+\.\d+"$/m, 'the wrapper pins an exact graphifyy version');
    assert.match(script, /--from "graphifyy==\$\{GRAPHIFY_VERSION\}"/);
    assert.match(script, /^export GRAPHIFY_BACKEND=none$/m);
    assert.doesNotMatch(script, /@latest/);
  });

  it('allows only the offline graphify commands, and extract only with --code-only', () => {
    const script = read('scripts/graphify.sh');
    const allowed = (/^ALLOWED="([^"]+)"$/m.exec(script)?.[1] ?? '').split(' ');
    const offline = ['extract', 'update', 'cluster-only', 'query', 'path', 'explain', 'god-nodes', 'affected'];
    assert.deepEqual([...allowed].sort(), [...offline].sort());
    assert.match(script, /extract must pass --code-only/);
  });

  it('gives every repository skill a name that matches its folder, and a description', () => {
    const folders = readdirSync(join(ROOT, '.claude/skills'));
    assert.ok(folders.length > 0, 'at least one skill is present');
    for (const folder of folders) {
      const frontMatter = /^---\n([\s\S]*?)\n---/.exec(read(`.claude/skills/${folder}/SKILL.md`))?.[1] ?? '';
      assert.match(frontMatter, new RegExp(`^name: ${folder}$`, 'm'), `${folder}: name matches the folder`);
      assert.match(frontMatter, /^description: \S/m, `${folder}: has a description`);
    }
  });
});
