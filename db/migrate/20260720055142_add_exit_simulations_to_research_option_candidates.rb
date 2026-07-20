# frozen_string_literal: true

class AddExitSimulationsToResearchOptionCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :research_option_candidates, :exit_simulations, :jsonb, null: false, default: {}
  end
end
