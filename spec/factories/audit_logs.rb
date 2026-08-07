FactoryBot.define do
  factory :audit_log do
    event_type { 'bot_start' }
    actor { 'system' }
    metadata { {} }
  end
end
