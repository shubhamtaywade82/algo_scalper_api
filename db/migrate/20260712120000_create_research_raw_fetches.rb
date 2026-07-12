# frozen_string_literal: true

class CreateResearchRawFetches < ActiveRecord::Migration[7.1]
  def change
    create_table :research_raw_fetches do |t|
      t.string   :endpoint,    null: false
      t.jsonb    :request,     null: false, default: {}
      t.jsonb    :response,    null: false, default: {}
      t.datetime :fetched_at,  null: false
      t.string   :api_version

      t.timestamps
    end

    add_index :research_raw_fetches, [:endpoint, :fetched_at]
  end
end
