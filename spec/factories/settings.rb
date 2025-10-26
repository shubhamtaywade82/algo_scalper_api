# == Schema Information
#
# Table name: settings
#
#  id         :integer          not null, primary key
#  key        :string           not null
#  value      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_settings_on_key  (key) UNIQUE
#

# frozen_string_literal: true

FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_key_#{n}" }
    value { 'default_value' }

    trait :trading_enabled do
      key { 'trading_enabled' }
      value { 'true' }
    end

    trait :trading_disabled do
      key { 'trading_enabled' }
      value { 'false' }
    end

    trait :max_positions do
      key { 'max_positions' }
      value { '5' }
    end

    trait :risk_per_trade do
      key { 'risk_per_trade_percentage' }
      value { '2.0' }
    end

    trait :stop_loss_percentage do
      key { 'stop_loss_percentage' }
      value { '30.0' }
    end

    trait :take_profit_percentage do
      key { 'take_profit_percentage' }
      value { '50.0' }
    end

    trait :trailing_stop_percentage do
      key { 'trailing_stop_percentage' }
      value { '20.0' }
    end

    trait :breakeven_threshold do
      key { 'breakeven_threshold_percentage' }
      value { '10.0' }
    end

    trait :signal_confidence_threshold do
      key { 'signal_confidence_threshold' }
      value { '0.7' }
    end

    trait :websocket_enabled do
      key { 'websocket_enabled' }
      value { 'true' }
    end

    trait :websocket_disabled do
      key { 'websocket_enabled' }
      value { 'false' }
    end

    trait :mock_data_enabled do
      key { 'mock_data_enabled' }
      value { 'true' }
    end

    trait :mock_data_disabled do
      key { 'mock_data_enabled' }
      value { 'false' }
    end
  end
end
