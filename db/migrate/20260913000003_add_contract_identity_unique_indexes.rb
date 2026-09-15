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
    'position_trackers'     => 'instrument_id',
    'leg_groups'            => 'instrument_id',
    'order_intents'         => 'instrument_id',
    'paper_orders'          => 'instrument_id',
    'paper_positions'       => 'instrument_id',
    'risk_events'           => 'instrument_id',
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
    dedupe_identity! <<~SQL
      deriv.option_type IS NOT NULL
        AND deriv.underlying_security_id IS NOT NULL
        AND deriv.expiry_date IS NOT NULL
    SQL
  end

  def dedupe_future_identity!
    say 'ContractIdentity: deduping future contracts'
    dedupe_identity! <<~SQL
      deriv.option_type IS NULL
        AND deriv.underlying_security_id IS NOT NULL
        AND deriv.expiry_date IS NOT NULL
        AND deriv.instrument_type LIKE 'FUT%'
    SQL
  end

  def dedupe_identity!(derivative_filter)
    # Child FK remap (collisions on best_indicator_params are dropped first).
    execute <<~SQL
      DELETE FROM best_indicator_params b1
      USING instruments dropped, instruments kept, best_indicator_params b2
      WHERE b1.instrument_id = dropped.id
        AND #{derivative_filter.gsub('deriv.', 'dropped.')}
        AND b2.instrument_id = kept.id
        AND #{derivative_filter.gsub('deriv.', 'kept.')}
        AND dropped.exchange IS NOT DISTINCT FROM kept.exchange
        AND dropped.segment  IS NOT DISTINCT FROM kept.segment
        AND dropped.underlying_security_id IS NOT DISTINCT FROM kept.underlying_security_id
        AND dropped.expiry_date IS NOT DISTINCT FROM kept.expiry_date
        AND dropped.strike_price IS NOT DISTINCT FROM kept.strike_price
        AND dropped.option_type IS NOT DISTINCT FROM kept.option_type
        AND dropped.id > kept.id
        AND b1.interval = b2.interval
        AND b1.indicator = b2.indicator
    SQL

    CHILD_FK_TABLES.each do |table, column|
      execute <<~SQL
        UPDATE #{table} child
        SET #{column} = keeper.id
        FROM instruments dropped
        JOIN LATERAL (
          SELECT k.id
          FROM instruments k
          WHERE k.id < dropped.id
            AND k.exchange IS NOT DISTINCT FROM dropped.exchange
            AND k.segment  IS NOT DISTINCT FROM dropped.segment
            AND k.underlying_security_id IS NOT DISTINCT FROM dropped.underlying_security_id
            AND k.expiry_date IS NOT DISTINCT FROM dropped.expiry_date
            AND k.strike_price IS NOT DISTINCT FROM dropped.strike_price
            AND k.option_type IS NOT DISTINCT FROM dropped.option_type
            AND #{derivative_filter.gsub('deriv.', 'k.')}
          ORDER BY k.id
          LIMIT 1
        ) keeper ON TRUE
        WHERE child.#{column} = dropped.id
          AND #{derivative_filter.gsub('deriv.', 'dropped.')}
      SQL
    end

    # Underlying self-reference remap.
    execute <<~SQL
      UPDATE instruments child
      SET underlying_instrument_id = keeper.id
      FROM instruments dropped
      JOIN LATERAL (
        SELECT k.id
        FROM instruments k
        WHERE k.id < dropped.id
          AND k.exchange IS NOT DISTINCT FROM dropped.exchange
          AND k.segment  IS NOT DISTINCT FROM dropped.segment
          AND k.underlying_security_id IS NOT DISTINCT FROM dropped.underlying_security_id
          AND k.expiry_date IS NOT DISTINCT FROM dropped.expiry_date
          AND k.strike_price IS NOT DISTINCT FROM dropped.strike_price
          AND k.option_type IS NOT DISTINCT FROM dropped.option_type
          AND #{derivative_filter.gsub('deriv.', 'k.')}
        ORDER BY k.id
        LIMIT 1
      ) keeper ON TRUE
      WHERE child.underlying_instrument_id = dropped.id
        AND #{derivative_filter.gsub('deriv.', 'dropped.')}
    SQL

    %w[position_trackers watchlist_items].each do |table|
      execute <<~SQL
        UPDATE #{table} w
        SET watchable_id = keeper.id
        FROM instruments dropped
        JOIN LATERAL (
          SELECT k.id
          FROM instruments k
          WHERE k.id < dropped.id
            AND k.exchange IS NOT DISTINCT FROM dropped.exchange
            AND k.segment  IS NOT DISTINCT FROM dropped.segment
            AND k.underlying_security_id IS NOT DISTINCT FROM dropped.underlying_security_id
            AND k.expiry_date IS NOT DISTINCT FROM dropped.expiry_date
            AND k.strike_price IS NOT DISTINCT FROM dropped.strike_price
            AND k.option_type IS NOT DISTINCT FROM dropped.option_type
            AND #{derivative_filter.gsub('deriv.', 'k.')}
          ORDER BY k.id
          LIMIT 1
        ) keeper ON TRUE
        WHERE w.watchable_type = 'Instrument'
          AND w.watchable_id = dropped.id
          AND #{derivative_filter.gsub('deriv.', 'dropped.')}
      SQL
    end

    # Drop the duplicates (any non-min row of each identity group).
    execute <<~SQL
      DELETE FROM instruments a
      USING instruments b
      WHERE a.id > b.id
        AND a.exchange IS NOT DISTINCT FROM b.exchange
        AND a.segment  IS NOT DISTINCT FROM b.segment
        AND a.underlying_security_id IS NOT DISTINCT FROM b.underlying_security_id
        AND a.expiry_date IS NOT DISTINCT FROM b.expiry_date
        AND a.strike_price IS NOT DISTINCT FROM b.strike_price
        AND a.option_type IS NOT DISTINCT FROM b.option_type
        AND #{derivative_filter.gsub('deriv.', 'a.')}
    SQL
  end
end
