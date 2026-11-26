import type { Signal } from '../domain/types.js';
import type { EntryObserver } from './replay.js';

/**
 * What first-match did on the entry bars a replay looked at (OTA-307). `hidden` counts the families whose signal was
 * dropped because an earlier family in the catalogue fired on the same bar. That is the bias the isolated replay removes.
 */
export interface ShadowTally {
  entryBars: number;
  /** Entry bars where two or more enabled families signalled. */
  multiSignalBars: number;
  credited: Record<string, number>;
  hidden: Record<string, number>;
}

export function createShadowTally(): ShadowTally {
  return { entryBars: 0, multiSignalBars: 0, credited: {}, hidden: {} };
}

const bump = (counts: Record<string, number>, key: string): void => {
  counts[key] = (counts[key] ?? 0) + 1;
};

export function shadowObserver(tally: ShadowTally): EntryObserver {
  return {
    onEntryBar(candidates: readonly Signal[], credited: Signal | undefined): void {
      tally.entryBars += 1;
      if (candidates.length < 2) {
        return;
      }
      tally.multiSignalBars += 1;
      const creditedName = credited?.strategy ?? 'unknown';
      bump(tally.credited, creditedName);
      for (const candidate of candidates) {
        const name = candidate.strategy ?? 'unknown';
        if (name !== creditedName) {
          bump(tally.hidden, name);
        }
      }
    },
  };
}
