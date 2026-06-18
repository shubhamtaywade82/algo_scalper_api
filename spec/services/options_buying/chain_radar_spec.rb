# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::ChainRadar do
  let(:ce_candidates) do
    [
      { security_id: 'c1', segment: 'NSE_FNO', strike: 24_600, type: 'CE', delta: 0.50, volume: 20_000, oi: 100_000 },
      { security_id: 'c2', segment: 'NSE_FNO', strike: 24_700, type: 'CE', delta: 0.48, volume: 15_000, oi: 250_000 }
    ]
  end
  let(:pe_candidates) do
    [
      { security_id: 'p1', segment: 'NSE_FNO', strike: 24_400, type: 'PE', delta: -0.50, volume: 18_000, oi: 300_000 },
      { security_id: 'p2', segment: 'NSE_FNO', strike: 24_300, type: 'PE', delta: -0.47, volume: 12_000, oi: 120_000 }
    ]
  end

  before do
    allow(OptionsBuying::Mode).to receive_messages(chain_radar_enabled?: true, rsi_bias_enabled?: false, config: {})
    analyzer = instance_double(Options::DerivativeChainAnalyzer, spot_ltp: 24_500.0)
    allow(analyzer).to receive(:select_candidates).with(limit: 50, direction: :bullish).and_return(ce_candidates)
    allow(analyzer).to receive(:select_candidates).with(limit: 50, direction: :bearish).and_return(pe_candidates)
    allow(Options::DerivativeChainAnalyzer).to receive(:new).and_return(analyzer)

    allow(OptionsBuying::StateStore).to receive(:set_radar_strikes)
    allow(OptionsBuying::StateStore).to receive(:set_resistance)
    allow(OptionsBuying::StateStore).to receive(:set_support)
    allow(OptionsBuying::StateStore).to receive(:set_volume_rate_baseline)
    allow(OptionsBuying::RsiDivergenceScanner).to receive(:scan!)
  end

  it 'sets resistance from the peak-OI CE strike' do
    described_class.scan!('NIFTY')
    expect(OptionsBuying::StateStore).to have_received(:set_resistance).with('NIFTY', 24_700.0)
  end

  it 'sets support from the peak-OI PE strike' do
    described_class.scan!('NIFTY')
    expect(OptionsBuying::StateStore).to have_received(:set_support).with('NIFTY', 24_400.0)
  end

  it 'stores both CE and PE liquid strikes tagged with their type' do
    described_class.scan!('NIFTY')

    expect(OptionsBuying::StateStore).to have_received(:set_radar_strikes) do |index_key, strikes|
      expect(index_key).to eq('NIFTY')
      expect(strikes.map { |s| s[:type] }.uniq).to contain_exactly('CE', 'PE')
      expect(strikes.map { |s| s[:security_id] }).to contain_exactly('c1', 'c2', 'p1', 'p2')
    end
  end

  it 'returns a summary including both levels' do
    result = described_class.scan!('NIFTY')
    expect(result).to include(index_key: 'NIFTY', resistance: 24_700.0, support: 24_400.0)
  end

  context 'when chain has LTP and greeks but no OI/volume' do
    let(:ce_candidates) do
      [
        { security_id: 'c1', segment: 'NSE_FNO', strike: 24_600, type: 'CE', delta: 0.50, volume: 0, oi: 0,
          ltp: 150.0 },
        { security_id: 'c2', segment: 'NSE_FNO', strike: 24_700, type: 'CE', delta: 0.48, volume: 0, oi: 0,
          ltp: 120.0 }
      ]
    end
    let(:pe_candidates) do
      [
        { security_id: 'p1', segment: 'NSE_FNO', strike: 24_400, type: 'PE', delta: -0.50, volume: 0, oi: 0,
          ltp: 140.0 }
      ]
    end

    it 'seeds radar strikes from delta-qualified LTP-only candidates' do
      described_class.scan!('NIFTY')

      expect(OptionsBuying::StateStore).to have_received(:set_radar_strikes) do |_index_key, strikes|
        expect(strikes.map { |s| s[:security_id] }).to contain_exactly('c1', 'c2', 'p1')
      end
    end

    it 'falls back to spot-nearest strikes for resistance and support' do
      described_class.scan!('NIFTY')

      expect(OptionsBuying::StateStore).to have_received(:set_resistance).with('NIFTY', 24_600.0)
      expect(OptionsBuying::StateStore).to have_received(:set_support).with('NIFTY', 24_400.0)
    end

    it 'keeps resistance and support on opposite sides of spot' do
      result = described_class.scan!('NIFTY')

      expect(result[:resistance]).to be >= 24_500.0
      expect(result[:support]).to be <= 24_500.0
      expect(result[:resistance]).not_to eq(result[:support])
    end
  end
end
