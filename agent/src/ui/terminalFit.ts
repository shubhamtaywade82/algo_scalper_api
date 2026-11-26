import stringWidth from 'string-width';

const graphemes = (text: string): string[] => [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)].map((part) => part.segment);

/** Fits a line to exactly `width` terminal columns, including ANSI styling. */
export function fit(text: string, width: number): string {
  if (width <= 0) {
    return '';
  }
  const visible = stringWidth(text);
  if (visible === width) {
    return text;
  }
  if (visible < width) {
    return text + ' '.repeat(width - visible);
  }
  const plainText = text.replace(/\x1b\[[0-9;]*m/g, '');
  let out = '';
  let used = 0;
  for (const cell of graphemes(plainText)) {
    const cellWidth = stringWidth(cell);
    if (used + cellWidth > width - 1) {
      break;
    }
    out += cell;
    used += cellWidth;
  }
  return out + '…' + ' '.repeat(Math.max(0, width - used - 1));
}
