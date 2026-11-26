import type { Migration } from './postgres.js';

/**
 * Schema for the trading ledger. Migrations are append-only: an applied migration is never edited,
 * because its checksum is stored and checked on every start. Add a new version to change the schema.
 */
export const MIGRATIONS: readonly Migration[] = [
  {
    version: '001_ledger',
    sql: `
      CREATE TABLE runs (
        run_id uuid PRIMARY KEY,
        instance_id text NOT NULL,
        mode text NOT NULL CHECK (mode IN ('paper', 'live')),
        client_id text NOT NULL,
        config_fingerprint text NOT NULL,
        started_at timestamptz NOT NULL,
        ended_at timestamptz,
        ended_reason text
      );

      -- Append-only. Each row is the exact JSONL record, so restore replays it through the same code path as the file.
      -- source_key is 'run:seq' for events written by this build, and 'legacy:<day>:<line>' for lines written before run ids existed.
      CREATE TABLE trade_events (
        id bigserial PRIMARY KEY,
        source_key text NOT NULL UNIQUE,
        run_id uuid REFERENCES runs (run_id),
        seq integer,
        trading_day date NOT NULL,
        ts timestamptz NOT NULL,
        event_type text NOT NULL,
        underlying text,
        correlation_id text,
        record jsonb NOT NULL,
        CHECK ((run_id IS NULL) = (seq IS NULL))
      );

      CREATE INDEX trade_events_day_order_idx ON trade_events (trading_day, ts, seq, id);
      CREATE INDEX trade_events_correlation_idx ON trade_events (correlation_id) WHERE correlation_id IS NOT NULL;

      CREATE VIEW v_closed_trades AS
        SELECT
          trading_day,
          underlying,
          record->>'positionId' AS position_id,
          record->>'contract' AS contract,
          (record->>'quantity')::integer AS quantity,
          (record->>'entryPrice')::numeric AS entry_price,
          (record->>'exitPrice')::numeric AS exit_price,
          (record->>'pnlInr')::numeric AS pnl_inr,
          record->>'reason' AS exit_reason,
          ts AS closed_at
        FROM trade_events
        WHERE event_type = 'trade_closed';
    `,
  },
  {
    version: '002_lease_and_tags',
    sql: `
      -- The single trading authority per client id. Holder and epoch change together on every acquisition, so a
      -- stale holder can be recognised by its old epoch. Acquisition and renewal use the database clock.
      CREATE TABLE leases (
        client_id text PRIMARY KEY,
        holder_run uuid NOT NULL,
        epoch bigint NOT NULL,
        expires_at timestamptz NOT NULL
      );

      -- Restore filters each day by the mode and client that wrote it, so paper and live never share state.
      CREATE INDEX trade_events_tags_idx ON trade_events (trading_day, (record->>'client'), (record->>'mode'));
    `,
  },
  {
    version: '003_append_only_and_run_safety',
    sql: `
      -- Rows are written once. Correction happens by a new event, never by editing history. This holds for every
      -- role, including the owner, because the trigger runs for all of them. Retention is a partition drop, done by a migration.
      CREATE FUNCTION trade_events_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'trade_events is append-only; rows cannot be changed, removed or truncated';
      END
      $$;

      CREATE TRIGGER trade_events_immutable
        BEFORE UPDATE OR DELETE ON trade_events
        FOR EACH ROW EXECUTE FUNCTION trade_events_append_only();

      CREATE TRIGGER trade_events_no_truncate
        BEFORE TRUNCATE ON trade_events
        FOR EACH STATEMENT EXECUTE FUNCTION trade_events_append_only();

      -- A run that ended with events still unconfirmed, or that never ended, must be reviewed before a live run starts.
      ALTER TABLE runs ADD COLUMN unconfirmed_at_end integer NOT NULL DEFAULT 0;
      ALTER TABLE runs ADD COLUMN acknowledged boolean NOT NULL DEFAULT false;
    `,
  },
  {
    version: '004_paper_venue',
    sql: `
      -- Paper mode's simulated venue. Market data is real; the wallet, orders and positions live here.
      -- Money is numeric(18,2) rupees. Prices are numeric(14,4), because option tick sizes are fractions of a rupee.
      CREATE TABLE paper_wallets (
        client_id text PRIMARY KEY,
        initial_inr numeric(18,2) NOT NULL CHECK (initial_inr > 0),
        balance_inr numeric(18,2) NOT NULL CHECK (balance_inr >= 0),
        updated_at timestamptz NOT NULL DEFAULT now()
      );

      CREATE TABLE paper_positions (
        position_id text PRIMARY KEY CHECK (char_length(position_id) BETWEEN 1 AND 128),
        client_id text NOT NULL REFERENCES paper_wallets (client_id),
        underlying text NOT NULL,
        security_id text NOT NULL,
        exchange_segment text NOT NULL,
        tick_size numeric(10,4) NOT NULL CHECK (tick_size > 0),
        quantity integer NOT NULL CHECK (quantity > 0),
        average_price numeric(14,4) NOT NULL CHECK (average_price > 0),
        stop_loss_price numeric(14,4) NOT NULL,
        target_price numeric(14,4) NOT NULL,
        status text NOT NULL CHECK (status IN ('OPEN', 'CLOSED')),
        opened_at timestamptz NOT NULL,
        closed_at timestamptz,
        exit_price numeric(14,4),
        exit_reason text,
        realized_pnl_inr numeric(18,2),
        CHECK ((status = 'OPEN') = (closed_at IS NULL))
      );
      CREATE INDEX paper_positions_open_idx ON paper_positions (client_id) WHERE status = 'OPEN';

      CREATE TABLE paper_orders (
        correlation_id text PRIMARY KEY CHECK (char_length(correlation_id) BETWEEN 1 AND 128),
        position_id text NOT NULL REFERENCES paper_positions (position_id),
        client_id text NOT NULL,
        kind text NOT NULL CHECK (kind IN ('ENTRY', 'EXIT', 'PROTECTIVE_EXIT')),
        side text NOT NULL CHECK (side IN ('BUY', 'SELL')),
        quantity integer NOT NULL CHECK (quantity > 0),
        price numeric(14,4) NOT NULL CHECK (price > 0),
        reason text,
        at timestamptz NOT NULL
      );

      -- Every cash movement. The wallet balance is the sum of these, and balance_after is checked on every write.
      CREATE TABLE paper_wallet_entries (
        id bigserial PRIMARY KEY,
        client_id text NOT NULL REFERENCES paper_wallets (client_id),
        correlation_id text NOT NULL UNIQUE REFERENCES paper_orders (correlation_id),
        delta_inr numeric(18,2) NOT NULL,
        balance_after_inr numeric(18,2) NOT NULL CHECK (balance_after_inr >= 0),
        at timestamptz NOT NULL
      );

      -- Orders and cash entries are history: written once, never changed.
      CREATE FUNCTION paper_history_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'paper orders and wallet entries are append-only';
      END
      $$;
      CREATE TRIGGER paper_orders_immutable BEFORE UPDATE OR DELETE ON paper_orders
        FOR EACH ROW EXECUTE FUNCTION paper_history_append_only();
      CREATE TRIGGER paper_wallet_entries_immutable BEFORE UPDATE OR DELETE ON paper_wallet_entries
        FOR EACH ROW EXECUTE FUNCTION paper_history_append_only();

      -- A position opens once and closes once. A closed position is never reopened or edited.
      CREATE FUNCTION paper_position_closed_is_final() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.status = 'CLOSED' THEN
          RAISE EXCEPTION 'paper position % is already closed', OLD.position_id;
        END IF;
        RETURN NEW;
      END
      $$;
      CREATE TRIGGER paper_positions_close_once BEFORE UPDATE ON paper_positions
        FOR EACH ROW EXECUTE FUNCTION paper_position_closed_is_final();
    `,
  },
  {
    version: '005_paper_withdrawals',
    sql: `
      -- Profit taken out of the paper wallet, one row per week or month. The wallet entry for it carries the
      -- correlation id WITHDRAWAL:<period>, so cash entries no longer all point at an order.
      ALTER TABLE paper_wallet_entries DROP CONSTRAINT paper_wallet_entries_correlation_id_fkey;

      CREATE TABLE paper_withdrawals (
        client_id text NOT NULL REFERENCES paper_wallets (client_id),
        period text NOT NULL CHECK (period ~ '^(W:[0-9]{4}-W[0-9]{2}|M:[0-9]{4}-[0-9]{2})$'),
        period_pnl_inr numeric(18,2) NOT NULL,
        amount_inr numeric(18,2) NOT NULL CHECK (amount_inr > 0),
        at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (client_id, period)
      );
      CREATE TRIGGER paper_withdrawals_immutable BEFORE UPDATE OR DELETE ON paper_withdrawals
        FOR EACH ROW EXECUTE FUNCTION paper_history_append_only();
    `,
  },
  {
    version: '006_paper_expiry',
    sql: `
      -- A position carried past its expiry is cash-settled at intrinsic value, which needs the contract's terms.
      -- Rows written before this migration have none.
      ALTER TABLE paper_positions ADD COLUMN expiry date;
      ALTER TABLE paper_positions ADD COLUMN strike numeric(14,4) CHECK (strike > 0);
      ALTER TABLE paper_positions ADD COLUMN option_type text CHECK (option_type IN ('CE', 'PE'));

      -- An out-of-the-money option expires at zero, so a settlement order can carry price 0.
      ALTER TABLE paper_orders DROP CONSTRAINT paper_orders_kind_check;
      ALTER TABLE paper_orders ADD CONSTRAINT paper_orders_kind_check CHECK (kind IN ('ENTRY', 'EXIT', 'PROTECTIVE_EXIT', 'EXPIRY'));
      ALTER TABLE paper_orders DROP CONSTRAINT paper_orders_price_check;
      ALTER TABLE paper_orders ADD CONSTRAINT paper_orders_price_check CHECK (price > 0 OR (kind = 'EXPIRY' AND price = 0));
    `,
  },
];
