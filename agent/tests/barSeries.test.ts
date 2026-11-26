import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { BarSeries, CandleBuilder } from '../src/market/barSeries.js';
import { bar, istEpoch } from './support/fixtures.js';

describe('CandleBuilder', () => {
  const FIVE_MIN = 5 * 60_000;

  it('aligns bucket starts to IST wall-clock boundaries', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    assert.equal(builder.bucketStart(istEpoch('2026-10-12', '09:17')), istEpoch('2026-10-12', '09:15'));
    assert.equal(builder.bucketStart(istEpoch('2026-10-12', '09:20')), istEpoch('2026-10-12', '09:20'));
  });

  it('closes the previous bar only when a tick opens the next bucket', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    assert.equal(builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:15') + 1_000 }), undefined);
    assert.equal(builder.onTick({ ltp: 103, ltt: istEpoch('2026-10-12', '09:16') }), undefined);
    assert.equal(builder.onTick({ ltp: 98, ltt: istEpoch('2026-10-12', '09:18') }), undefined);
    const closed = builder.onTick({ ltp: 101, ltt: istEpoch('2026-10-12', '09:20') });
    assert.deepEqual(closed, {
      time: istEpoch('2026-10-12', '09:15'),
      open: 100,
      high: 103,
      low: 98,
      close: 98,
      volume: 0,
    });
  });

  it('drops out-of-order ticks instead of corrupting the open bar', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:20') });
    assert.equal(builder.onTick({ ltp: 50, ltt: istEpoch('2026-10-12', '09:16') }), undefined);
    assert.equal(builder.droppedLateTicks, 1);
    const closed = builder.onTick({ ltp: 101, ltt: istEpoch('2026-10-12', '09:25') });
    assert.equal(closed?.low, 100);
  });

  it('ignores non-positive or non-finite prices', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    assert.equal(builder.onTick({ ltp: 0, ltt: istEpoch('2026-10-12', '09:15') }), undefined);
    assert.equal(builder.onTick({ ltp: Number.NaN, ltt: istEpoch('2026-10-12', '09:15') }), undefined);
    assert.equal(builder.flush(istEpoch('2026-10-12', '09:30')), undefined);
  });

  it('flushes a quiet bar once wall-clock time passes its end', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:15') });
    assert.equal(builder.flush(istEpoch('2026-10-12', '09:19')), undefined);
    assert.equal(builder.flush(istEpoch('2026-10-12', '09:20'))?.close, 100);
    assert.equal(builder.flush(istEpoch('2026-10-12', '09:25')), undefined, 'a flushed bar is not emitted twice');
  });

  it('should anchor 25- and 60-minute buckets at the 09:15 open, as Dhan history does', () => {
    const twentyFive = new CandleBuilder(25 * 60_000);
    assert.equal(twentyFive.bucketStart(istEpoch('2026-10-12', '09:39')), istEpoch('2026-10-12', '09:15'));
    assert.equal(twentyFive.bucketStart(istEpoch('2026-10-12', '09:40')), istEpoch('2026-10-12', '09:40'));
    const hourly = new CandleBuilder(60 * 60_000);
    assert.equal(hourly.bucketStart(istEpoch('2026-10-12', '10:14')), istEpoch('2026-10-12', '09:15'));
    assert.equal(hourly.bucketStart(istEpoch('2026-10-12', '15:20')), istEpoch('2026-10-12', '15:15'));
  });

  it('should ignore pre-open and post-close ticks', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    assert.equal(builder.onTick({ ltp: 99, ltt: istEpoch('2026-10-12', '09:08') }), undefined);
    builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:15') });
    const first = builder.onTick({ ltp: 101, ltt: istEpoch('2026-10-12', '09:20') });
    assert.equal(first?.time, istEpoch('2026-10-12', '09:15'));
    assert.equal(first?.open, 100, 'the 09:08 pre-open value is not part of the first bar');
    builder.onTick({ ltp: 102, ltt: istEpoch('2026-10-12', '15:29') });
    assert.equal(builder.onTick({ ltp: 103, ltt: istEpoch('2026-10-12', '15:31') }), undefined, 'no post-close bar opens');
  });

  it('should drop a tick stamped inside an already flushed bar', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:15') });
    builder.onTick({ ltp: 120, ltt: istEpoch('2026-10-12', '09:17') });
    builder.onTick({ ltp: 90, ltt: istEpoch('2026-10-12', '09:18') });
    const flushed = builder.flush(istEpoch('2026-10-12', '09:20') + 100);
    assert.deepEqual([flushed?.high, flushed?.low, flushed?.close], [120, 90, 90]);

    // Stamped 09:19:59, received after the flush.
    assert.equal(builder.onTick({ ltp: 105, ltt: istEpoch('2026-10-12', '09:20') - 1_000 }), undefined);
    assert.equal(builder.droppedLateTicks, 1);
    builder.onTick({ ltp: 106, ltt: istEpoch('2026-10-12', '09:20') + 2_000 });
    const next = builder.onTick({ ltp: 107, ltt: istEpoch('2026-10-12', '09:25') + 1_000 });
    assert.equal(next?.time, istEpoch('2026-10-12', '09:20'), 'the next bar closes, not a second copy of 09:15');
    assert.equal(next?.open, 106);
  });

  it('should drop a tick stamped inside a bar closed by a newer tick', () => {
    const builder = new CandleBuilder(FIVE_MIN);
    builder.onTick({ ltp: 100, ltt: istEpoch('2026-10-12', '09:15') });
    builder.onTick({ ltp: 101, ltt: istEpoch('2026-10-12', '09:20') });
    builder.flush(istEpoch('2026-10-12', '09:25'));
    assert.equal(builder.onTick({ ltp: 99, ltt: istEpoch('2026-10-12', '09:16') }), undefined);
    assert.equal(builder.droppedLateTicks, 1);
  });
});

describe('BarSeries', () => {
  it('replaces a bar that re-arrives at the same open time', () => {
    const series = new BarSeries();
    series.upsert(bar(1, 10, 11, 9, 10));
    series.upsert(bar(1, 10, 12, 9, 11));
    assert.equal(series.length, 1);
    assert.equal(series.last?.high, 12);
  });

  it('refuses bars older than the newest stored bar', () => {
    const series = new BarSeries();
    series.upsert(bar(2, 10, 11, 9, 10));
    assert.equal(series.upsert(bar(1, 10, 11, 9, 10)), false);
    assert.equal(series.length, 1);
  });

  it('bounds memory by capacity, keeping the newest bars', () => {
    const series = new BarSeries(3);
    for (let t = 1; t <= 5; t += 1) {
      series.upsert(bar(t, 1, 1, 1, 1));
    }
    assert.deepEqual(series.all().map((candle) => candle.time), [3, 4, 5]);
  });
});
