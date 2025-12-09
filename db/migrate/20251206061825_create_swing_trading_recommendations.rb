# frozen_string_literal: true

class CreateSwingTradingRecommendations < ActiveRecord::Migration[8.0]
  def change
    create_table :swing_trading_recommendations do |t|
      t.references :watchlist_item, null: false, foreign_key: true
      t.string :symbol_name, null: false
      t.string :segment, null: false
      t.string :security_id, null: false
      t.string :recommendation_type, null: false # 'swing' or 'long_term'
      t.string :direction, null: false # 'buy' or 'sell'
      t.decimal :entry_price, precision: 12, scale: 4, null: false
      t.decimal :stop_loss, precision: 12, scale: 4, null: false
      t.decimal :take_profit, precision: 12, scale: 4, null: false
      t.integer :quantity, null: false
      t.decimal :allocation_pct, precision: 5, scale: 2, null: false # Percentage of capital to allocate
      t.integer :hold_duration_days, null: false # Expected hold duration
      t.decimal :confidence_score, precision: 5, scale: 4 # 0.0 to 1.0
      t.string :status, default: 'active' # 'active', 'executed', 'expired', 'cancelled'
      t.jsonb :technical_analysis, default: {} # Stores all indicator values
      t.jsonb :volume_analysis, default: {} # Volume-based analysis
      t.text :reasoning # Human-readable reasoning for the recommendation
      t.datetime :analysis_timestamp, null: false
      t.datetime :expires_at # When this recommendation expires

      t.timestamps
    end

    add_index :swing_trading_recommendations, [:watchlist_item_id, :status, :analysis_timestamp]
    add_index :swing_trading_recommendations, [:symbol_name, :status]
    add_index :swing_trading_recommendations, [:recommendation_type, :status]
    add_index :swing_trading_recommendations, :expires_at
    add_index :swing_trading_recommendations, :technical_analysis, using: :gin
    add_index :swing_trading_recommendations, :volume_analysis, using: :gin
  end
end
