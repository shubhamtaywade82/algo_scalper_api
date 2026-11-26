export interface RunScope {
  readonly mode: string;
  readonly clientId: string;
}

/**
 * The journal lines of one mode and client, from a day's file. A line that predates tagging cannot be
 * attributed to a mode, so its presence throws: restoring from it could mix paper and live state.
 */
export function scopeJournalLines(text: string, scope: RunScope, dayKey: string): string[] {
  const kept: string[] = [];
  let untagged = 0;
  text.split('\n').forEach((line, index) => {
    if (line.trim() === '') {
      return;
    }
    let event: { mode?: unknown; client?: unknown };
    try {
      event = JSON.parse(line) as typeof event;
    } catch {
      throw new Error(`journal line ${index + 1} is malformed; inspect it before restarting`);
    }
    if (typeof event.mode !== 'string' || typeof event.client !== 'string') {
      untagged += 1;
      return;
    }
    if (event.mode === scope.mode && event.client === scope.clientId) {
      kept.push(line);
    }
  });
  if (untagged > 0) {
    throw new Error(`${untagged} journal line(s) for ${dayKey} predate mode and client tags and cannot be attributed; move them aside before restoring`);
  }
  return kept;
}
