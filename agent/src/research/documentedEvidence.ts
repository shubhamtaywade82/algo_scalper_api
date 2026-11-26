import { UNKNOWN, type LedgerBody } from './experimentLedger.js';

/**
 * Research evidence that already exists in the repository's documents, written into the ledger once (roadmap priority 2).
 * Each entry cites the document it comes from. Nothing here is re-run. Results are kept as the documents state them,
 * including windows that were spent before they were used for confirmation. A Spent window stays Spent.
 *
 * Fields the documents do not give are UNKNOWN, not inferred. `variants_evaluated` counts what the document says was
 * run; where it gives no count, the count is a floor, and the note says so.
 */

const BACKFILLED_ON = '2026-11-03T00:00:00Z';
const NO_PROVENANCE = { sdk_version: UNKNOWN, parser_version: UNKNOWN, response_schema_version: UNKNOWN };

export interface DocumentedEvidence {
  readonly evidence_id: string;
  readonly body: LedgerBody;
}

const base = {
  record_kind: 'backfill',
  hypothesis_id: null,
  parameter_fingerprint: UNKNOWN,
  dataset_hash: UNKNOWN,
  costs_fingerprint: UNKNOWN,
  provenance: NO_PROVENANCE,
  created_at: BACKFILLED_ON,
} as const;

export const DOCUMENTED_EVIDENCE: readonly DocumentedEvidence[] = [
  {
    evidence_id: 'doc:TIME_MACHINE.md:first-pass-2026-11-02',
    body: {
      ...base,
      strategy_id: 'configured-set',
      underlying: 'NIFTY',
      date_range: { from: null, to: null, label: 'NIFTY 2025H' },
      overlap_group: 'DOC-NIFTY-2025H',
      experiment_type: 'discovery',
      holdout_status: 'NotHoldout',
      cells: 60,
      variants_evaluated: 1,
      result: {
        documented_on: '2026-11-02',
        cells_passed: 0,
        best_cells: [
          { key: 'trend | trendAlignment=WITH', probability_mean_r_nonpositive: 0.0145 },
          { key: 'trend | regime=TRENDING', probability_mean_r_nonpositive: 0.019 },
        ],
        verdict_at_0_25_percent_half_spread: 'EDGE_SUPPORTED',
        verdict_at_one_percent_half_spread: 'NO_TRADE',
        note: 'first context-cell pass, 60 cells, none passed the family-wise bar. Discovery, not confirmation.',
      },
      source: 'docs/TIME_MACHINE.md, section Context cells, and docs/ROADMAP.md OTA-304',
    } as LedgerBody,
  },
  {
    evidence_id: 'doc:TIME_MACHINE.md:confirmation-2026H-spent',
    body: {
      ...base,
      strategy_id: 'configured-set',
      underlying: 'NIFTY',
      // The 2026H window is inside the exit-test window below, so it shares that overlap group.
      date_range: { from: null, to: null, label: 'NIFTY 2026H' },
      overlap_group: 'DOC-NIFTY-2025-10-2026-09',
      experiment_type: 'confirmation',
      // Preserved as evidence. It was spent before this confirmation: exit sweeps had already run on it.
      holdout_status: 'Spent',
      cells: 2,
      variants_evaluated: 1,
      result: {
        documented_on: '2026-11-02',
        confirmed_cells: [
          { key: 'trend | trendAlignment=WITH', mean_net_r: -0.02, verdict: 'NO_TRADE' },
          { key: 'trend | regime=TRENDING', mean_net_r: -0.04, verdict: 'NO_TRADE' },
        ],
        note: 'checked once on NIFTY 2026H. This window is not an untouched holdout: exit-rule sweeps used NIFTY 2025-10..2026-09, which contains it. Kept as the historical record, and never relabelled Frozen.',
      },
      source: 'docs/TIME_MACHINE.md, section Context cells (hold-out discipline), and docs/ROADMAP.md OTA-304',
    } as LedgerBody,
  },
  {
    evidence_id: 'doc:ROADMAP.md:exit-sweep-nifty-2025-10-2026-09',
    body: {
      ...base,
      strategy_id: 'configured-set',
      underlying: 'NIFTY',
      date_range: { from: '2025-10-01', to: '2026-09-30', label: 'NIFTY 2025-10..2026-09' },
      overlap_group: 'DOC-NIFTY-2025-10-2026-09',
      experiment_type: 'discovery',
      holdout_status: 'Spent',
      cells: 0,
      variants_evaluated: 1,
      result: {
        note: 'stop %, R target and time-stop variants. Each moved mean R by under 0.02 (ROADMAP fact 1). Floor: the number of variants was never recorded.',
      },
      source: 'docs/ROADMAP.md fact 1 and docs/TIME_MACHINE.md; seeded floor previously in docs/research/variants-seed.json',
    } as LedgerBody,
  },
  {
    evidence_id: 'doc:TIME_MACHINE.md:iv-crush-exit',
    body: {
      ...base,
      strategy_id: 'configured-set',
      underlying: 'NIFTY',
      date_range: { from: '2025-10-01', to: '2026-09-30', label: 'NIFTY 2025-10..2026-09' },
      overlap_group: 'DOC-NIFTY-2025-10-2026-09',
      experiment_type: 'discovery',
      holdout_status: 'Spent',
      cells: 0,
      variants_evaluated: 1,
      result: {
        note: 'IV-crush exit (leave when the held strike IV is 1.5 to 3 vol points below entry), tested on NIFTY 2025-10..2026-09 and on SENSEX and BANKNIFTY 2026-04..09. Changed mean net R by under 0.02 either way, and was removed. Floor: variants and their count were never recorded.',
      },
      source: 'docs/TIME_MACHINE.md, section Implied volatility and open interest; seeded floor previously in docs/research/variants-seed.json',
    } as LedgerBody,
  },
];
