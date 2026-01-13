# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engines::BaseEngine do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30
    }
  end
  let(:config) { { multiplier: 1 } }
  let(:option_candidate) do
    {
      security_id: 12_345,
      segment: 'NSE_FNO',
      symbol: 'NIFTY24FEB20000CE',
      lot_size: 50
    }
  end
  let(:tick_cache) { instance_double(Live::RedisTickCache) }
  let(:engine) do
    described_class.new(
      index: index_cfg,
      config: config,
      option_candidate: option_candidate,
      tick_cache: tick_cache
    )
  end

  describe '#create_signal' do
    it 'returns signal hash with required fields' do
      signal = engine.send(:create_signal, reason: 'test reason')

      expect(signal).to be_a(Hash)
      expect(signal[:segment]).to eq('NSE_FNO')
      expect(signal[:security_id]).to eq(12_345)
      expect(signal[:reason]).to eq('test reason')
      expect(signal[:meta]).to include(
        index: 'NIFTY',
        candidate_symbol: 'NIFTY24FEB20000CE',
        strategy: 'Signal::Engines::BaseEngine',
        lot_size: 50,
        multiplier: 1
      )
    end

    it 'includes multiplier from config' do
      config[:multiplier] = 2
      signal = engine.send(:create_signal, reason: 'test')

      expect(signal[:meta][:multiplier]).to eq(2)
    end

    it 'returns nil if security_id is missing' do
      allow(engine).to receive(:option_security_id).and_return(nil)

      signal = engine.send(:create_signal, reason: 'test')

      expect(signal).to be_nil
    end
  end

  describe '#option_lot_size' do
    it 'returns lot_size from candidate' do
      expect(engine.send(:option_lot_size)).to eq(50)
    end

    it 'falls back to index lot_size' do
      candidate_without_lot = option_candidate.except(:lot_size)
      engine = described_class.new(
        index: index_cfg.merge(lot_size: 25),
        config: config,
        option_candidate: candidate_without_lot,
        tick_cache: tick_cache
      )

      expect(engine.send(:option_lot_size)).to eq(25)
    end

    it 'defaults to 1 if no lot_size available' do
      candidate_without_lot = option_candidate.except(:lot_size)
      engine = described_class.new(
        index: index_cfg,
        config: config,
        option_candidate: candidate_without_lot,
        tick_cache: tick_cache
      )

      expect(engine.send(:option_lot_size)).to eq(1)
    end
  end
end
