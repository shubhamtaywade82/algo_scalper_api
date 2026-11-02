# frozen_string_literal: true

# Woods (AI codebase indexer) was removed; its tables were never populated — the
# index lived in tmp/woods with an in-memory store.
class DropWoodsTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :woods_embeddings, if_exists: true
    drop_table :woods_edges, if_exists: true
    drop_table :woods_units, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
