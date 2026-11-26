import { readFile, truncate, writeFile } from 'node:fs/promises';

export interface TornTailRepair {
  /** 'none' when the file ends cleanly. 'completed' when the last line was whole but missing its newline. 'quarantined' when it was not. */
  readonly outcome: 'none' | 'completed' | 'quarantined';
  readonly bytes: number;
  readonly quarantinedTo?: string;
}

/**
 * Repairs the end of a journal file after a crash. A process that died mid-write leaves an unterminated last line.
 * If that line is a whole event, its newline is added. If it is not, its bytes are moved to a sibling file and the
 * journal is cut back to the last complete line. Nothing is deleted, and an operator can read the moved bytes.
 */
export async function repairTornTail(file: string, now: number): Promise<TornTailRepair> {
  let text: string;
  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      return { outcome: 'none', bytes: 0 };
    }
    throw error;
  }
  if (text === '' || text.endsWith('\n')) {
    return { outcome: 'none', bytes: 0 };
  }
  const cut = text.lastIndexOf('\n') + 1;
  const tail = text.slice(cut);
  if (isWholeEvent(tail)) {
    await writeFile(file, '\n', { flag: 'a' });
    return { outcome: 'completed', bytes: tail.length };
  }
  const quarantinedTo = `${file}.torn-${now}`;
  await writeFile(quarantinedTo, tail, { flag: 'wx' });
  await truncate(file, Buffer.byteLength(text.slice(0, cut), 'utf8'));
  return { outcome: 'quarantined', bytes: tail.length, quarantinedTo };
}

function isWholeEvent(text: string): boolean {
  try {
    const parsed = JSON.parse(text) as unknown;
    return parsed !== null && typeof parsed === 'object';
  } catch {
    return false;
  }
}
