# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::StateStore do
  let(:fake_redis) { instance_spy(Redis) }

  before { allow(described_class).to receive(:redis).and_return(fake_redis) }

  describe 'support level' do
    it 'writes the support key' do
      described_class.set_support('NIFTY', 24_000.0)
      expect(fake_redis).to have_received(:set).with('options_buying:support:NIFTY', 24_000.0, ex: kind_of(Integer))
    end

    it 'reads the support key as a float' do
      allow(fake_redis).to receive(:get).with('options_buying:support:NIFTY').and_return('24000.0')
      expect(described_class.support('NIFTY')).to eq(24_000.0)
    end
  end

  describe 'direction-scoped breakout arming' do
    it 'arms bullish and bearish under separate keys' do
      described_class.set_breakout_ready!('NIFTY', direction: :bullish)
      described_class.set_breakout_ready!('NIFTY', direction: :bearish)

      expect(fake_redis).to have_received(:set)
        .with('options_buying:breakout_ready:bullish:NIFTY', kind_of(Integer), ex: kind_of(Integer))
      expect(fake_redis).to have_received(:set)
        .with('options_buying:breakout_ready:bearish:NIFTY', kind_of(Integer), ex: kind_of(Integer))
    end

    it 'checks readiness per direction independently' do
      allow(fake_redis).to receive(:exists?).with('options_buying:breakout_ready:bullish:NIFTY').and_return(true)
      allow(fake_redis).to receive(:exists?).with('options_buying:breakout_ready:bearish:NIFTY').and_return(false)

      expect(described_class.breakout_ready?('NIFTY', direction: :bullish)).to be(true)
      expect(described_class.breakout_ready?('NIFTY', direction: :bearish)).to be(false)
    end

    it 'defaults to the bullish key' do
      described_class.breakout_ready?('NIFTY')
      expect(fake_redis).to have_received(:exists?).with('options_buying:breakout_ready:bullish:NIFTY')
    end
  end

  describe '.primary_radar_strike' do
    let(:strikes) do
      [
        { security_id: '1', type: 'CE', volume: 50_000 },
        { security_id: '2', type: 'CE', volume: 90_000 },
        { security_id: '3', type: 'PE', volume: 70_000 },
        { security_id: '4', type: 'PE', volume: 30_000 }
      ]
    end

    before { allow(described_class).to receive(:radar_strikes).with('NIFTY').and_return(strikes) }

    it 'returns the most liquid CE strike when type: CE' do
      expect(described_class.primary_radar_strike('NIFTY', type: 'CE')[:security_id]).to eq('2')
    end

    it 'returns the most liquid PE strike when type: PE' do
      expect(described_class.primary_radar_strike('NIFTY', type: 'PE')[:security_id]).to eq('3')
    end

    it 'returns the overall most liquid strike when no type given' do
      expect(described_class.primary_radar_strike('NIFTY')[:security_id]).to eq('2')
    end
  end
end
