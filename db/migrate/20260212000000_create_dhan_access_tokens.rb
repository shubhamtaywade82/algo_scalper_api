# frozen_string_literal: true

class CreateDhanAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :dhan_access_tokens do |t|
      t.string :token, null: false
      t.datetime :expiry_time, null: false
      t.timestamps
    end

    add_index :dhan_access_tokens, :expiry_time
  end
end

