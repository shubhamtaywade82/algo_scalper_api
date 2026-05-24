# frozen_string_literal: true

FactoryBot.define do
  factory :market_holiday do
    exchange { :nse }
    observed_on { Date.new(2031, 6, 11) }
    name { 'Factory test holiday' }
  end
end
