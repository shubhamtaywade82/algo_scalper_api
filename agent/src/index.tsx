#!/usr/bin/env node
import 'dotenv/config';
import { render } from 'ink';
import { loadConfig } from './config.js';
import { buildRuntime } from './runtime/createRuntime.js';
import { operatorInterrupt } from './runtime/operatorInterrupt.js';
import type { StopKind } from './runtime/orchestrator.js';
import App from './ui/App.js';

/**
 * Entry point. Configuration is validated before any socket opens.
 *
 * On an interactive terminal the operator cockpit runs. Set UI=off, or pipe the output, for plain
 * log lines (useful under a process supervisor). Without the cockpit, SIGINT twice within 2s quits
 * immediately (paper releases the lease for restart) and SIGTERM runs a graceful stop. In the cockpit,
 * Ctrl+C is the graceful stop key, the same as s.
 */
async function main(): Promise<void> {
  const config = loadConfig(process.env);
  const cockpit = process.stdout.isTTY === true && process.env['UI'] !== 'off';
  const runtime = await buildRuntime(config, Date.now, { cockpit });
  const { orchestrator, logger } = runtime;

  let stopping: Promise<void> | undefined;
  const shutdown = (kind: StopKind): void => {
    stopping ??= (async () => {
      logger.warn('shutdown requested', { kind });
      await orchestrator.stop(kind);
      restoreScreen();
      process.exit(0);
    })();
  };

  process.once('SIGTERM', () => shutdown('graceful'));
  process.on('SIGINT', () => {
    if (operatorInterrupt() === 'armed') {
      logger.warn('press Ctrl+C again within 2s to quit immediately (paper: lease released for restart)');
      return;
    }
    shutdown('immediate');
  });

  if (!cockpit) {
    await orchestrator.start();
    return;
  }

  if (process.stdout.isTTY) {
    process.stdout.write('\x1b[?1049h\x1b[?25l\x1b[H');
  }
  const instance = render(<App runtime={runtime} />, { exitOnCtrlC: false });
  await instance.waitUntilExit();
  restoreScreen();
  if (!orchestrator.hasStopped()) {
    await orchestrator.stop('graceful').catch(() => undefined);
  }
}

function restoreScreen(): void {
  if (process.stdout.isTTY) {
    process.stdout.write('\x1b[?25h\x1b[?1049l');
  }
}

main().catch((error: unknown) => {
  restoreScreen();
  console.error('fatal:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
