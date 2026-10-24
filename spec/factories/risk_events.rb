# frozen_string_literal: true

FactoryBot.define do
  factory :risk_event do
    event_type { 'daily_loss_hit' }
    severity { 'critical' }
    source { 'risk_engine' }
    description { 'Hit daily loss limit' }
    action_taken { 'halted_trading' }
    context { {} }
  end
end
