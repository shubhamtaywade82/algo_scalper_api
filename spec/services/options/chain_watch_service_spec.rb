require 'rails_helper'

RSpec.describe Options::ChainWatchService do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:expiry) { Date.current + 7.days }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(Live::MarketFeedHub.instance).to receive(:subscribe_many).and_return([])
    allow(Live::MarketFeedHub.instance).to receive(:unsubscribe_many).and_return([])
  end

  describe '#resolve_atm_legs' do
    it 'returns the 11 nearest strikes both sides of ATM for NIFTY' do
      # Seed 21 CE/PE derivative pairs around strike 24800 in 50pt steps
      instrument = Instrument.create!(
        exchange: 'nse', segment: 'index', security_id: '13',
        symbol_name: 'NIFTY', display_name: 'NIFTY', instrument_code: 'index'
      )
      (-10..10).each do |offset|
        strike = 24800.0 + (offset * 50)
        %w[CE PE].each do |type|
          Derivative.create!(
            instrument: instrument, exchange: 'nse', segment: 'derivatives',
            underlying_symbol: 'NIFTY', expiry_date: expiry, strike_price: strike,
            option_type: type, lot_size: 50, security_id: "#{strike.to_i}#{type}",
            symbol_name: "NIFTY-#{strike.to_i}-#{type}"
          )
        end
      end

      service = described_class.new(index_key: 'NIFTY')
      legs = service.resolve_atm_legs(spot: 24800.0, expiry: expiry)

      expect(legs.size).to eq(22) # 11 strikes × CE/PE
      strikes = legs.map { |l| l[:strike] }.uniq.sort
      expect(strikes).to eq((24550.0..25050.0).step(50).to_a)
    end
  end
end
