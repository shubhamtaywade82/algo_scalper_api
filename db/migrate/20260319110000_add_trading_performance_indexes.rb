# frozen_string_literal: true

class AddTradingPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :position_trackers, :created_at, if_not_exists: true

    add_index :derivatives, %i[expiry_date strike_price option_type],
              name: 'index_derivatives_on_expiry_strike_option_type',
              if_not_exists: true
  end
end
