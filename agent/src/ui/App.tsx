import { useEffect, useState } from 'react';
import { Box, Text, useApp, useInput, useStdout } from 'ink';
import type { Runtime } from '../runtime/createRuntime.js';
import { STRATEGY_CATALOG } from '../strategy/session.js';
import { COCKPIT_KEYS, STRATEGY_KEYS } from './keymap.js';
import { COCKPIT_MIN_COLS, COCKPIT_MIN_ROWS, renderOptionsCockpit, resizeNotice } from './cockpit.js';

/** Destructive or outward actions need a second press within this window. */
export const CONFIRM_WINDOW_MS = 5000;
const DEFAULT_COLS = 160;
const DEFAULT_ROWS = 50;

type Action = 'close' | 'block' | 'stop' | 'reset_drawdown' | 'toggle_brake' | 'posture' | 'strategy' | 'test_trade';
interface Pending {
  readonly action: Action;
  readonly symbol: string | undefined;
  readonly expiresAt: number;
}

/**
 * True when `pending` is the same action on the same target and its window is still open at `now`.
 * Callers pass the press time, because a render can be up to a timer tick old.
 */
export function isConfirmation(pending: Pending | undefined, action: Action, symbol: string | undefined, now: number): boolean {
  return pending !== undefined && pending.expiresAt > now && pending.action === action && pending.symbol === symbol;
}

function confirmPrompt(pending: Pending): string {
  switch (pending.action) {
    case 'close':
      return `press c again within 5s to close the ${pending.symbol ?? ''} position through the normal exit path`;
    case 'block':
      return 'press k again within 5s to toggle the entry block';
    case 'stop':
      return 'press s or Ctrl+C again within 5s to stop: open positions are flattened first';
    case 'reset_drawdown':
      return 'press r again within 5s to confirm reset of daily drawdown threshold';
    case 'toggle_brake':
      return 'press d again within 5s to toggle daily loss brake';
    case 'posture':
      return 'press p again within 5s to cycle the strategy posture';
    case 'strategy': {
      const family = STRATEGY_CATALOG.find((strategy) => strategy.id === STRATEGY_KEYS[pending.symbol ?? '']);
      return `press ${pending.symbol ?? ''} again within 5s to toggle ${family?.label ?? 'the strategy family'}`;
    }
    case 'test_trade':
      return `press t again within 5s to start a test trade on ${pending.symbol ?? ''}`;
  }
}

/**
 * Operator cockpit. It shows the state the orchestrator reports. Every key that changes trading or the
 * session needs a second press, so one stray key cannot trade (the key table is ./keymap.ts). Ctrl+C is the
 * same stop as `s`, and it does not unmount the app, because `c` is also the close key.
 */
export default function App({ runtime }: { runtime: Runtime }) {
  const { orchestrator, records } = runtime;
  const { exit } = useApp();
  const { stdout } = useStdout();
  const [size, setSize] = useState({ cols: stdout.columns || DEFAULT_COLS, rows: stdout.rows || DEFAULT_ROWS });
  const [, setRefresh] = useState(0);
  const [selected, setSelected] = useState(0);
  const [positionScroll, setPositionScroll] = useState(0);
  const [pending, setPending] = useState<Pending | undefined>(undefined);
  const [notice, setNotice] = useState<string | undefined>(undefined);

  useEffect(() => {
    const onResize = () => setSize({ cols: stdout.columns || DEFAULT_COLS, rows: stdout.rows || DEFAULT_ROWS });
    stdout.on('resize', onResize);
    return () => {
      stdout.off('resize', onResize);
    };
  }, [stdout]);

  useEffect(() => {
    // A failed start is recorded in the snapshot (phase FAILED) and the log; the screen stays up.
    // Redraw when the start settles so the phase shows at once rather than on the next timer tick.
    orchestrator
      .start()
      .catch(() => undefined)
      .finally(() => setRefresh((n) => n + 1));
  }, [orchestrator]);

  useEffect(() => orchestrator.onViewUpdate(() => setRefresh((n) => n + 1)), [orchestrator]);

  // Age text and the header clock still advance when the feed is quiet (no ticks).
  useEffect(() => {
    const timer = setInterval(() => setRefresh((n) => n + 1), 1000);
    return () => clearInterval(timer);
  }, []);

  const snapshot = orchestrator.snapshot();
  const count = snapshot.underlyings.length;
  const index = Math.max(0, Math.min(selected, count - 1));
  const selectedSymbol = snapshot.underlyings[index]?.symbol;

  useEffect(() => {
    orchestrator.setCockpitFocus(selectedSymbol);
  }, [orchestrator, selectedSymbol]);
  const armed = pending !== undefined && pending.expiresAt > Date.now() ? pending : undefined;

  const stopAndExit = async (): Promise<void> => {
    setNotice('stopping: flattening open positions before exit');
    await orchestrator.stop('graceful');
    exit();
  };

  const execute = (action: Action, symbol: string | undefined): void => {
    if (action === 'close' && symbol !== undefined) {
      setNotice(orchestrator.requestManualExit(symbol));
    } else if (action === 'block') {
      setNotice(orchestrator.toggleEntryBlock());
    } else if (action === 'stop') {
      void stopAndExit();
    } else if (action === 'reset_drawdown') {
      setNotice(orchestrator.resetDailyDrawdown());
    } else if (action === 'toggle_brake') {
      setNotice(orchestrator.toggleDailyLossBrake());
    } else if (action === 'posture') {
      setNotice(orchestrator.cyclePosture());
    } else if (action === 'strategy' && symbol !== undefined) {
      const id = STRATEGY_KEYS[symbol];
      if (id !== undefined) {
        setNotice(orchestrator.toggleStrategy(id));
      }
    } else if (action === 'test_trade' && symbol !== undefined) {
      setNotice(orchestrator.triggerTestTrade(symbol));
    }
  };

  const request = (action: Action, symbol: string | undefined): void => {
    const now = Date.now();
    if (isConfirmation(pending, action, symbol, now)) {
      setPending(undefined);
      execute(action, symbol);
      return;
    }
    const next: Pending = { action, symbol, expiresAt: now + CONFIRM_WINDOW_MS };
    setPending(next);
    setNotice(confirmPrompt(next));
  };

  useInput((input, key) => {
    if (key.ctrl && input === 'c') {
      request('stop', undefined);
      return;
    }
    if (key.upArrow) {
      setSelected(Math.max(0, index - 1));
      return;
    }
    if (key.downArrow) {
      setSelected(Math.min(Math.max(0, count - 1), index + 1));
      return;
    }
    if (key.leftArrow) {
      if (!orchestrator.nudgeCockpitChainScroll(-1)) {
        setNotice('chain window at lowest strikes');
      }
      return;
    }
    if (key.rightArrow) {
      if (!orchestrator.nudgeCockpitChainScroll(1)) {
        setNotice('chain window at highest strikes');
      }
      return;
    }
    if (input === 'p') {
      request('posture', undefined);
      return;
    }
    if (Object.prototype.hasOwnProperty.call(STRATEGY_KEYS, input)) {
      request('strategy', input);
      return;
    }
    if (input === 't') {
      if (selectedSymbol === undefined) {
        setNotice('no underlying selected');
        return;
      }
      request('test_trade', selectedSymbol);
      return;
    }
    if (input === 'c') {
      const openUnderlyings = snapshot.underlyings.filter(
        (u) => (u.positions && u.positions.length > 0) || u.position !== undefined,
      );
      let target = selectedSymbol;
      const selectedHasPosition = openUnderlyings.some((u) => u.symbol === selectedSymbol);
      if (!selectedHasPosition && openUnderlyings.length === 1 && openUnderlyings[0] !== undefined) {
        target = openUnderlyings[0].symbol;
      }
      if (target === undefined) {
        setNotice('no underlying selected or open');
        return;
      }
      request('close', target);
      return;
    }
    if (input === '[') {
      setPositionScroll((s) => Math.max(0, s - 2));
      return;
    }
    if (input === ']') {
      setPositionScroll((s) => s + 2);
      return;
    }
    if (key.pageUp) {
      setPositionScroll((s) => Math.max(0, s - 5));
      return;
    }
    if (key.pageDown) {
      setPositionScroll((s) => s + 5);
      return;
    }
    if (input === 'k') {
      request('block', undefined);
      return;
    }
    if (input === 's') {
      request('stop', undefined);
      return;
    }
    if (input === 'r') {
      request('reset_drawdown', undefined);
      return;
    }
    if (input === 'd') {
      request('toggle_brake', undefined);
      return;
    }
    if (input === '?') {
      setNotice(COCKPIT_KEYS.map((key) => key.help).join(' · '));
    }
  });

  if (size.cols < COCKPIT_MIN_COLS || size.rows < COCKPIT_MIN_ROWS) {
    return (
      <Box flexDirection="column">
        {resizeNotice(size.cols, size.rows).map((line, i) => (
          <Text key={i}>{line}</Text>
        ))}
      </Box>
    );
  }

  const lines = renderOptionsCockpit(snapshot, {
    width: size.cols,
    // One row short of the terminal: a frame as tall as the screen makes Ink redraw everything
    height: size.rows - 1,
    selected: index,
    notice: armed === undefined ? notice : confirmPrompt(armed),
    logs: records?.newest(200) ?? [],
    positionScroll,
  });

  return (
    <Box flexDirection="column">
      {lines.map((line, i) => (
        <Text key={i}>{line}</Text>
      ))}
    </Box>
  );
}
