# frozen_string_literal: true

# Enforces derivative contract identity at the database level.
#
# The business identity of an option contract is:
#   (exchange, segment, underlying_security_id, expiry_date, strike_price, option_type)
# and of a future contract:
#   (exchange, segment, underlying_security_id, expiry_date)
#
# Previously this identity existed only as an application-level lookup
# (Derivative.find_by_params + in-Ruby BigDecimal comparison). Now Postgres
# owns the invariant via partial unique indexes, so a bad scrip-master import
# cannot silently create two rows for the same tradable contract.
class AddContractIdentityUniqueIndexes < ActiveRecord::Migration[8.1]
  CHILD_FK_TABLES = {
    'position_trackers' => 'instrument_id',
    'leg_groups' => 'instrument_id',
    'order_intents' => 'instrument_id',
    'paper_orders' => 'instrument_id',
    'paper_positions' => 'instrument_id',
    'risk_events' => 'instrument_id',
    'best_indicator_params' => 'instrument_id'
  }.freeze

  def up
    dedupe_option_identity!
    dedupe_future_identity!

    unless index_exists?(:instruments, name: 'index_instruments_on_option_contract_identity')
      add_index :instruments,
                %i[exchange segment underlying_security_id expiry_date strike_price option_type],
                unique: true,
                name: 'index_instruments_on_option_contract_identity',
                where: "option_type IS NOT NULL AND underlying_security_id IS NOT NULL AND expiry_date IS NOT NULL"
    end

    unless index_exists?(:instruments, name: 'index_instruments_on_future_contract_identity')
      add_index :instruments,
                %i[exchange segment underlying_security_id expiry_date],
                unique: true,
                name: 'index_instruments_on_future_contract_identity',
                where: "option_type IS NULL AND expiry_date IS NOT NULL AND underlying_security_id IS NOT NULL AND instrument_type LIKE 'FUT%'"
    end
  end

  def down
    if index_exists?(:instruments, name: 'index_instruments_on_option_contract_identity')
      remove_index :instruments, name: 'index_instruments_on_option_contract_identity'
    end
    if index_exists?(:instruments, name: 'index_instruments_on_future_contract_identity')
      remove_index :instruments, name: 'index_instruments_on_future_contract_identity'
    end
  end

  private

  # Collapses duplicate option contracts (same exchange/segment/underlying/
  # expiry/strike/type) onto the lowest id, remapping references first.
  def dedupe_option_identity!
    say 'ContractIdentity: deduping option contracts'
    dedupe_identity!(
      <<~SQL.squish,
        deriv.option_type IS NOT NULL
          AND deriv.underlying_security_id IS NOT NULL
          AND deriv.expiry_date IS NOT NULL
      SQL
      'exchange, segment, underlying_security_id, expiry_date, strike_price, option_type'
    )
  end

  def dedupe_future_identity!
    say 'ContractIdentity: deduping future contracts'
    dedupe_identity!(
      <<~SQL.squish,
        deriv.option_type IS NULL
          AND deriv.underlying_security_id IS NOT NULL
          AND deriv.expiry_date IS NOT NULL
          AND deriv.instrument_type LIKE 'FUT%'
      SQL
      'exchange, segment, underlying_security_id, expiry_date'
    )
  end

  def dedupe_identity!(derivative_filter, partition_cols)
    execute <<~SQL.squish
      DROP TABLE IF EXISTS _contract_dups;
      CREATE TEMP TABLE _contract_dups AS
      SELECT id AS dropped_id,
             FIRST_VALUE(id) OVER (
               PARTITION BY #{partition_cols}
               ORDER BY id ASC
             ) AS keep_id
      FROM instruments
      WHERE #{derivative_filter.gsub('deriv.', '')};

      CREATE INDEX ON _contract_dups (dropped_id);
    SQL

    execute <<~SQL.squish
      DELETE FROM best_indicator_params b1
      USING _contract_dups d1, best_indicator_params b2
      WHERE d1.dropped_id != d1.keep_id
        AND b1.instrument_id = d1.dropped_id
        AND b2.instrument_id = d1.keep_id
        AND b1.interval = b2.interval
        AND b1.indicator = b2.indicator;
    SQL

    CHILD_FK_TABLES.each do |table, column|
      execute <<~SQL.squish
        UPDATE #{table} child
        SET #{column} = dups.keep_id
        FROM _contract_dups dups
        WHERE child.#{column} = dups.dropped_id
          AND dups.dropped_id != dups.keep_id;
      SQL
    end

    # Underlying self-reference remap.
    execute <<~SQL.squish
      UPDATE instruments child
      SET underlying_instrument_id = dups.keep_id
      FROM _contract_dups dups
      WHERE child.underlying_instrument_id = dups.dropped_id
        AND dups.dropped_id != dups.keep_id;
    SQL

    %w[position_trackers watchlist_items].each do |table|
      execute <<~SQL.squish
        UPDATE #{table} w
        SET watchable_id = dups.keep_id
        FROM _contract_dups dups
        WHERE w.watchable_type = 'Instrument'
          AND w.watchable_id = dups.dropped_id
          AND dups.dropped_id != dups.keep_id;
      SQL
    end

    # Drop the duplicates (any non-min row of each identity group).
    execute <<~SQL.squish
      DELETE FROM instruments
      WHERE id IN (
        SELECT dropped_id FROM _contract_dups WHERE dropped_id != keep_id
      );

      DROP TABLE IF EXISTS _contract_dups;
    SQL
  end
end
