# frozen_string_literal: true

# Consolidates the duplicated derivative master into `instruments`.
#
# Before this migration the Dhan scrip master was split across two tables with
# overlapping columns:
#
#   instruments  <- SEGMENT in (I, E, ...) rows  (index / equity masters)
#   derivatives  <- SEGMENT = 'D' rows      (FNO contracts, full master copy)
#
# After the migration `instruments` is the single canonical tradable-security
# master (Q&A decision 2026-09: "Instrument = broker/exchange-specific tradable
# contract"). The legacy `derivatives` table is kept as a read-only archive for
# historical reference; nothing writes to it anymore.
#
# Steps (idempotent, PostgreSQL):
#   1. Deduplicate instruments on the canonical broker identity
#      (exchange, segment, security_id), remapping every child FK first.
#   2. Replace the old unique index (security_id, symbol_name, exchange,
#      segment) with a unique index on the canonical identity, so the database
#      and the model validation agree on ONE invariant.
#   3. Insert every derivatives row into instruments (ON CONFLICT DO NOTHING
#      on the canonical key).
#   4. Resolve underlying_instrument_id for derivative contracts.
#   5. Remap polymorphic watchables (position_trackers, watchlist_items) from
#      'Derivative' to 'Instrument'.
#   6. Mark expired contracts as not tradable (kept forever for history).
class ConsolidateDerivativesIntoInstruments < ActiveRecord::Migration[8.1]
  CHILD_FK_TABLES = {
    'position_trackers' => 'instrument_id',
    'derivatives' => 'instrument_id',
    'leg_groups' => 'instrument_id',
    'order_intents' => 'instrument_id',
    'paper_orders' => 'instrument_id',
    'paper_positions' => 'instrument_id',
    'risk_events' => 'instrument_id',
    'best_indicator_params' => 'instrument_id'
  }.freeze

  def up
    dedupe_instruments_on_canonical_identity!
    swap_unique_index_to_canonical_identity!
    insert_derivatives_into_instruments!
    link_underlying_instruments!
    remap_watchables_to_instrument!
    mark_expired_contracts_untradable!
  end

  def down
    # Data migration is irreversible (derivatives rows are merged into
    # instruments). Restore the legacy index shape so future schema loads
    # match the pre-consolidation state.
    if index_exists?(:instruments, name: 'index_instruments_on_exchange_segment_security_id_unique')
      remove_index :instruments, name: 'index_instruments_on_exchange_segment_security_id_unique'
      add_index :instruments, %i[security_id symbol_name exchange segment],
                unique: true, name: 'index_instruments_unique'
    end
  end

  private

  # Keeps MIN(id) per (exchange, segment, security_id) and remaps every
  # child FK that pointed at a dropped duplicate.
  def dedupe_instruments_on_canonical_identity!
    say 'ConsolidateDerivatives: deduping instruments on (exchange, segment, security_id)'

    execute <<~SQL.squish
      CREATE TEMP TABLE IF NOT EXISTS _inst_dups AS
      SELECT id AS dropped_id,
             FIRST_VALUE(id) OVER (
               PARTITION BY exchange, segment, security_id
               ORDER BY id ASC
             ) AS keep_id
      FROM instruments;

      CREATE INDEX IF NOT EXISTS _inst_dups_dropped_id_idx ON _inst_dups (dropped_id);
    SQL

    # best_indicator_params has a unique index on (instrument_id, interval,
    # indicator) — drop rows that would collide once remapped onto the keeper.
    execute <<~SQL.squish
      DELETE FROM best_indicator_params b1
      USING _inst_dups d1, best_indicator_params b2
      WHERE d1.dropped_id != d1.keep_id
        AND b1.instrument_id = d1.dropped_id
        AND b2.instrument_id = d1.keep_id
        AND b1.interval = b2.interval
        AND b1.indicator = b2.indicator
    SQL

    CHILD_FK_TABLES.each do |table, column|
      execute <<~SQL.squish
        UPDATE #{table} child
        SET #{column} = dups.keep_id
        FROM _inst_dups dups
        WHERE child.#{column} = dups.dropped_id
          AND dups.dropped_id != dups.keep_id
      SQL
    end

    # Polymorphic Instrument watchables.
    %w[position_trackers watchlist_items].each do |table|
      execute <<~SQL.squish
        UPDATE #{table} w
        SET watchable_id = dups.keep_id
        FROM _inst_dups dups
        WHERE w.watchable_type = 'Instrument'
          AND w.watchable_id = dups.dropped_id
          AND dups.dropped_id != dups.keep_id
      SQL
    end

    execute <<~SQL.squish
      DELETE FROM instruments
      WHERE id IN (
        SELECT dropped_id FROM _inst_dups WHERE dropped_id != keep_id
      );

      DROP TABLE IF EXISTS _inst_dups;
    SQL
  end

  def swap_unique_index_to_canonical_identity!
    say 'ConsolidateDerivatives: swapping unique index to (exchange, segment, security_id)'
    return if index_exists?(:instruments, name: 'index_instruments_on_exchange_segment_security_id_unique')

    remove_index :instruments, name: 'index_instruments_unique' if index_exists?(:instruments, name: 'index_instruments_unique')
    add_index :instruments, %i[exchange segment security_id],
              unique: true, name: 'index_instruments_on_exchange_segment_security_id_unique'
  end

  def insert_derivatives_into_instruments!
    say 'ConsolidateDerivatives: inserting derivatives rows into instruments'
    execute <<~SQL.squish
      INSERT INTO instruments (
        exchange, segment, security_id, isin, instrument_code,
        underlying_security_id, underlying_symbol, symbol_name, display_name,
        instrument_type, series, lot_size, expiry_date, strike_price, option_type,
        tick_size, expiry_flag, bracket_flag, cover_flag, asm_gsm_flag, asm_gsm_category,
        buy_sell_indicator, buy_co_min_margin_per, sell_co_min_margin_per,
        buy_co_sl_range_max_perc, sell_co_sl_range_max_perc,
        buy_co_sl_range_min_perc, sell_co_sl_range_min_perc,
        buy_bo_min_margin_per, sell_bo_min_margin_per,
        buy_bo_sl_range_max_perc, sell_bo_sl_range_max_perc,
        buy_bo_sl_range_min_perc, sell_bo_sl_min_range,
        buy_bo_profit_range_max_perc, sell_bo_profit_range_max_perc,
        buy_bo_profit_range_min_perc, sell_bo_profit_range_min_perc,
        mtf_leverage, created_at, updated_at
      )
      SELECT
        d.exchange, d.segment, d.security_id, d.isin, d.instrument_code,
        d.underlying_security_id, d.underlying_symbol, d.symbol_name, d.display_name,
        d.instrument_type, d.series, d.lot_size, d.expiry_date, d.strike_price, d.option_type,
        d.tick_size, d.expiry_flag, d.bracket_flag, d.cover_flag, d.asm_gsm_flag, d.asm_gsm_category,
        d.buy_sell_indicator, d.buy_co_min_margin_per, d.sell_co_min_margin_per,
        d.buy_co_sl_range_max_perc, d.sell_co_sl_range_max_perc,
        d.buy_co_sl_range_min_perc, d.sell_co_sl_range_min_perc,
        d.buy_bo_min_margin_per, d.sell_bo_min_margin_per,
        d.buy_bo_sl_range_max_perc, d.sell_bo_sl_range_max_perc,
        d.buy_bo_sl_range_min_perc, d.sell_bo_sl_min_range,
        d.buy_bo_profit_range_max_perc, d.sell_bo_profit_range_max_perc,
        d.buy_bo_profit_range_min_perc, d.sell_bo_profit_range_min_perc,
        d.mtf_leverage, d.created_at, d.updated_at
      FROM derivatives d
      ON CONFLICT (exchange, segment, security_id) DO NOTHING
    SQL
  end

  # NIFTY 25000 CE (segment 'D') -> NIFTY index row (segment 'I'), preferring
  # underlying_security_id and falling back to underlying_symbol.
  def link_underlying_instruments!
    say 'ConsolidateDerivatives: linking derivative contracts to underlying instruments'
    execute <<~SQL.squish
      UPDATE instruments deriv
      SET underlying_instrument_id = underlying.id
      FROM instruments underlying
      WHERE deriv.underlying_instrument_id IS NULL
        AND deriv.underlying_security_id IS NOT NULL
        AND deriv.underlying_security_id <> ''
        AND underlying.security_id = deriv.underlying_security_id
        AND underlying.exchange IS NOT DISTINCT FROM deriv.exchange
        AND underlying.segment IN ('I', 'E')
    SQL

    execute <<~SQL.squish
      UPDATE instruments deriv
      SET underlying_instrument_id = underlying.id
      FROM instruments underlying
      WHERE deriv.underlying_instrument_id IS NULL
        AND deriv.option_type IS NOT NULL
        AND deriv.underlying_symbol IS NOT NULL
        AND deriv.underlying_symbol <> ''
        AND underlying.symbol_name = deriv.underlying_symbol
        AND underlying.exchange IS NOT DISTINCT FROM deriv.exchange
        AND underlying.segment = 'I'
    SQL
  end

  def remap_watchables_to_instrument!
    say 'ConsolidateDerivatives: remapping watchables from Derivative to Instrument'
    %w[position_trackers watchlist_items].each do |table|
      execute <<~SQL.squish
        UPDATE #{table} w
        SET watchable_type = 'Instrument', watchable_id = i.id
        FROM derivatives d
        JOIN instruments i
          ON i.exchange IS NOT DISTINCT FROM d.exchange
         AND i.segment  IS NOT DISTINCT FROM d.segment
         AND i.security_id IS NOT DISTINCT FROM d.security_id
        WHERE w.watchable_type = 'Derivative'
          AND w.watchable_id = d.id
      SQL
    end
  end

  # Expired contracts stay forever (historical trades, backtesting, audit) but
  # must never be selected for new orders.
  def mark_expired_contracts_untradable!
    say 'ConsolidateDerivatives: marking expired contracts untradable'
    execute <<~SQL.squish
      UPDATE instruments
      SET tradable = FALSE, updated_at = CURRENT_TIMESTAMP
      WHERE expiry_date IS NOT NULL
        AND expiry_date < CURRENT_DATE
        AND (tradable IS NULL OR tradable = TRUE)
    SQL
  end
end
