# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketHoliday do
  describe 'validations' do
    it 'requires exchange and observed_on' do
      expect(build(:market_holiday, exchange: nil)).not_to be_valid
      expect(build(:market_holiday, observed_on: nil)).not_to be_valid
    end
  end

  describe 'uniqueness' do
    it 'does not allow duplicate exchange + date' do
      create(:market_holiday, exchange: :nse, observed_on: Date.new(2032, 4, 7))
      dup = build(:market_holiday, exchange: :nse, observed_on: Date.new(2032, 4, 7))
      expect(dup).not_to be_valid
    end
  end
end
