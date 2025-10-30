# frozen_string_literal: true

class CreatePaperWallet < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_wallets do |t|
      t.decimal :initial_capital, precision: 15, scale: 2, default: 0, null: false
      t.decimal :available_capital, precision: 15, scale: 2, default: 0, null: false
      t.decimal :invested_capital, precision: 15, scale: 2, default: 0, null: false
      t.decimal :total_pnl, precision: 15, scale: 2, default: 0, null: false
      t.string :mode, default: 'paper', null: false

      t.timestamps
    end
  end
end
