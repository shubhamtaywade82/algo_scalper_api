# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engines::OpenInterestBuyingEngine do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:config) { { multiplier: 1 } }
  let(:option_candidate) { { security_id: 12345, segment: 'NSE_FNO', symbol: 'NIFTY24FEB20000CE', lot_size: 50 } }
  let(:tick_cache) { instance_double(Live::RedisTickCache) }
  let(:engine) do
    described_class.new(
      index: index_cfg,
      config: config,
      option_candidate: option_candidate,
      tick_cache: tick_cache
    )
  end

  describe '#evaluate' do
    context 'when conditions are met' do
      let(:tick) do
        {
          oi: 100_000,
          prev_close: 110.0,
          ltp: 120.0
        }
      end

      before do
        allow(engine).to receive(:option_tick).and_return(tick)
        allow(engine).to receive(:state_get).with(:last_oi, 100_000).and_return(90_000)
        allow(engine).to receive(:state_set)
      end

      it 'returns signal when OI increases and price increases' do
        signal = engine.evaluate

        expect(signal).to be_a(Hash)
        expect(signal[:reason]).to eq('OI buildup')
        expect(signal[:meta][:oi_change]).to eq(10_000)
      end
    end

    context 'when OI does not increase' do
      let(:tick) { { oi: 100_000, prev_close: 110.0, ltp: 120.0 } }

      before do
        allow(engine).to receive(:option_tick).and_return(tick)
        allow(engine).to receive(:state_get).with(:last_oi, 100_000).and_return(100_000)
      end

      it 'returns nil' do
        expect(engine.evaluate).to be_nil
      end
    end

    context 'when price does not increase' do
      let(:tick) { { oi: 100_000, prev_close: 110.0, ltp: 105.0 } }

      before do
        allow(engine).to receive(:option_tick).and_return(tick)
        allow(engine).to receive(:state_get).with(:last_oi, 100_000).and_return(90_000)
      end

      it 'returns nil' do
        expect(engine.evaluate).to be_nil
      end
    end

    context 'when tick is missing' do
      before { allow(engine).to receive(:option_tick).and_return(nil) }

      it 'returns nil' do
        expect(engine.evaluate).to be_nil
      end
    end
  end
end

