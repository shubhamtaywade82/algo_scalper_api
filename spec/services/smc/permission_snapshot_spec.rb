# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::PermissionSnapshot do
  describe '.from_contexts' do
    it 'returns a hash with SMC keys for three contexts' do
      s5 = build(:candle_series, :five_minute, :with_candles)
      s15 = build(:candle_series, :fifteen_minute, :with_candles)
      s60 = build(:candle_series, :one_hour, :with_candles)

      htf = Smc::Context.new(s60)
      mtf = Smc::Context.new(s15)
      ltf = Smc::Context.new(s5)

      h = described_class.from_contexts(htf: htf, mtf: mtf, ltf: ltf)

      expect(h).to have_key(:structure_state)
      expect(h).to have_key(:trend)
      expect(h).to have_key(:bos_recent)
      expect(h).to have_key(:displacement)
    end
  end
end
