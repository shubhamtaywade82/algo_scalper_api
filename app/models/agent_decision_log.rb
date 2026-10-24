# == Schema Information
#
# Table name: agent_decision_logs
#
#  id               :bigint           not null, primary key
#  agent_name       :string           not null
#  authority_level  :string           default("advisor"), not null
#  decision_type    :string           not null
#  input_context    :jsonb
#  output           :jsonb
#  confidence       :decimal(5, 4)
#  published_event  :string
#  error            :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#

# frozen_string_literal: true

# Full-context audit trail for every agentic-AI decision (Ai::Agents::*).
# Every agent in this phase runs at authority_level "advisor" — it can only
# read state, log a recommendation here, and optionally publish an
# observational event; none of them place orders or mutate trading config.
class AgentDecisionLog < ApplicationRecord
  validates :agent_name, presence: true
  validates :decision_type, presence: true
  validates :authority_level, presence: true

  scope :for_agent, ->(name) { where(agent_name: name.to_s) }
  scope :recent, -> { order(created_at: :desc) }
  scope :failed, -> { where.not(error: nil) }

  def failed?
    error.present?
  end
end
