# frozen_string_literal: true

class CreateMarketHolidays < ActiveRecord::Migration[8.0]
  def change
    create_table :market_holidays do |t|
      t.string :exchange, null: false, limit: 8
      t.date :observed_on, null: false
      t.string :name, null: false, default: ''

      t.timestamps
    end

    add_index :market_holidays, %i[exchange observed_on],
              unique: true,
              name: 'index_market_holidays_on_exchange_and_observed_on_unique'
    add_index :market_holidays, :observed_on,
              name: 'index_market_holidays_on_observed_on'
  end
end
