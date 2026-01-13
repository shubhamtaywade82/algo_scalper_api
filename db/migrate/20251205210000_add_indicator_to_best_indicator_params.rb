# frozen_string_literal: true

class AddIndicatorToBestIndicatorParams < ActiveRecord::Migration[8.0]
  def change
    # Add indicator column if it doesn't exist
    unless column_exists?(:best_indicator_params, :indicator)
      add_column :best_indicator_params, :indicator, :string, default: 'combined'
    end

    # Remove old unique index if it exists
    if index_exists?(:best_indicator_params, [:instrument_id, :interval],
                     name: 'idx_unique_best_params_per_instrument_interval')
      remove_index :best_indicator_params,
                   name: 'idx_unique_best_params_per_instrument_interval'
    end

    # Add new unique index including indicator (if it doesn't exist)
    unless index_exists?(:best_indicator_params, [:instrument_id, :interval, :indicator],
                        name: 'idx_unique_best_params_per_instrument_interval_indicator')
      add_index :best_indicator_params,
                [:instrument_id, :interval, :indicator],
                unique: true,
                name: 'idx_unique_best_params_per_instrument_interval_indicator'
    end

    # Update existing records to have indicator = 'combined' (for backward compatibility)
    execute <<-SQL
      UPDATE best_indicator_params
      SET indicator = 'combined'
      WHERE indicator IS NULL OR indicator = ''
    SQL

    # Make indicator NOT NULL after setting defaults
    change_column_null :best_indicator_params, :indicator, false
  end
end

