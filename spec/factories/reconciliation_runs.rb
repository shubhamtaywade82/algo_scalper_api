# frozen_string_literal: true

FactoryBot.define do
  factory :reconciliation_run do
    status { 'running' }
    mode { 'paper' }
    started_at { Time.current }
  end

  factory :reconciliation_discrepancy do
    reconciliation_run
    entity_type { 'order' }
    entity_id { 'ORD-001' }
    field_name { 'status' }
    local_value { 'active' }
    broker_value { 'cancelled' }
    severity { 'critical' }
  end
end
