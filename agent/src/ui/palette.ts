import chalk from 'chalk';

/** Semantic colors for the cockpit. Meaning always stays in the words; color only speeds scanning. */

export const muted = (text: string) => chalk.gray(text);
export const emphasis = (text: string) => chalk.white.bold(text);
export const label = (text: string) => chalk.gray.bold(text);
export const ok = (text: string) => chalk.green(text);
export const bad = (text: string) => chalk.red(text);
export const warn = (text: string) => chalk.yellow(text);
export const info = (text: string) => chalk.cyan(text);
export const infoBold = (text: string) => chalk.cyan.bold(text);
export const callSide = (text: string) => chalk.green.bold(text);
export const putSide = (text: string) => chalk.red.bold(text);
export const range = (text: string) => chalk.blue(text);
export const selectedName = (text: string) => chalk.bgCyan.black.bold(` ${text} `);

export function freshness(text: string, ageMs: number | undefined, staleMs: number): string {
  if (ageMs === undefined || ageMs > staleMs) {
    return bad(text);
  }
  if (ageMs > staleMs / 2) {
    return warn(text);
  }
  return ok(text);
}
