# frozen_string_literal: true

class BackfillPositionTrackerMetaColumns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  SCALAR_MAP = {
    'dte_at_entry' => 'dte_at_entry',
    'vix_at_entry' => 'vix_at_entry',
    'iv_at_entry' => 'iv_at_entry',
    'iv_percentile' => 'iv_percentile',
    'spread_guard_pct' => 'spread_guard_pct',
    'atm_strike' => 'atm_strike',
    'expiry_date' => 'expiry_date',
    'bos_age_at_entry' => 'bos_age_at_entry',
    'retrace_pct' => 'retrace_pct',
    'pullback_candles' => 'pullback_candles',
    'entry_distance_r' => 'entry_distance_r',
    'continuation_body_position' => 'continuation_body_position',
    'time_from_bos_to_entry' => 'time_from_bos_to_entry',
    'premium_stop_price' => 'premium_stop_price',
    'entry_risk_rupees' => 'entry_risk_rupees',
    'entry_tf' => 'entry_tf',
    'htf_tf' => 'htf_tf',
    'strategy_profile' => 'strategy_profile',
    'entry_underlying_price' => 'entry_underlying_price',
    'hwm_pnl_pct' => 'hwm_pnl_pct'
  }.freeze

  BLOB_MAP = {
    'decision' => 'decision',
    'execution' => 'execution',
    'entry_context' => 'entry_context'
  }.freeze

  def up
    say_with_time('Promoting scalar meta fields to columns...') do
      count = 0

      PositionTracker.find_in_batches(batch_size: 200) do |batch|
        batch.each do |tracker|
          meta = tracker.meta || {}
          next if meta.empty?

          col_values = {}

          meta.each do |meta_key, meta_val|
            str_key = meta_key.to_s
            next if BLOB_MAP.key?(str_key)
            next if str_key == 'config_snapshot'
            next if str_key == 'config_version'

            if SCALAR_MAP.key?(str_key)
              col_values[str_key] = coerce(meta_val, str_key)
            end
          end

          next if col_values.empty?

          # rubocop:disable Rails/SkipsModelValidations
          tracker.update_columns(col_values.merge('updated_at' => Time.current))
          # rubocop:enable Rails/SkipsModelValidations
          count += 1
        end
      end

      say("Total trackers promoted: #{count}")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def coerce(value, key)
    case key
    when 'dte_at_entry', 'pullback_candles', 'bos_age_at_entry'
      value.to_i
    when /_pct$/, 'spread_guard_pct', 'retrace_pct', 'iv_at_entry', 'iv_percentile',
          'vix_at_entry', 'hwm_pnl_pct', 'entry_distance_r', 'atm_strike',
          'entry_risk_rupees', 'premium_stop_price', 'entry_underlying_price'
      BigDecimal(value.to_s)
    when 'expiry_date'
      parse_date(value)
    else
      value.to_s
    end
  rescue StandardError
    nil
  end

  def parse_date(value)
    value.is_a?(String) ? Date.parse(value) : value
  rescue StandardError
    nil
  end
end
