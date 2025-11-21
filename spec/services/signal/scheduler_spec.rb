# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      strategies: {
        open_interest: { enabled: true, priority: 1, multiplier: 1 },
        momentum_buying: { enabled: true, priority: 2, multiplier: 1 }
      }
    }
  end
  let(:scheduler) { described_class.new(period: 1) }
  let(:mock_provider) { instance_double(Providers::DhanhqProvider) }
  let(:mock_analyzer) { instance_double(Options::ChainAnalyzer) }

  before do
    allow(scheduler).to receive(:default_provider).and_return(mock_provider)
    allow(Options::ChainAnalyzer).to receive(:new).and_return(mock_analyzer)
  end

  describe '#load_enabled_strategies' do
    it 'loads and sorts strategies by priority' do
      strategies = scheduler.send(:load_enabled_strategies, index_cfg)

      expect(strategies.size).to eq(2)
      expect(strategies.first[:key]).to eq(:open_interest)
      expect(strategies.first[:priority]).to eq(1)
      expect(strategies.last[:key]).to eq(:momentum_buying)
      expect(strategies.last[:priority]).to eq(2)
    end

    it 'excludes disabled strategies' do
      index_cfg[:strategies][:open_interest][:enabled] = false

      strategies = scheduler.send(:load_enabled_strategies, index_cfg)

      expect(strategies.size).to eq(1)
      expect(strategies.first[:key]).to eq(:momentum_buying)
    end

    it 'returns empty array when no strategies enabled' do
      index_cfg[:strategies] = {
        open_interest: { enabled: false },
        momentum_buying: { enabled: false }
      }

      strategies = scheduler.send(:load_enabled_strategies, index_cfg)

      expect(strategies).to be_empty
    end
  end

  describe '#evaluate_strategies_priority' do
    let(:enabled_strategies) { scheduler.send(:load_enabled_strategies, index_cfg) }
    let(:candidate) { { security_id: 12345, segment: 'NSE_FNO', symbol: 'NIFTY24FEB20000CE', lot_size: 50 } }
    let(:mock_engine) { instance_double(Signal::Engines::OpenInterestBuyingEngine) }

    before do
      allow(mock_analyzer).to receive(:select_candidates).and_return([candidate])
      allow(Signal::Engines::OpenInterestBuyingEngine).to receive(:new).and_return(mock_engine)
    end

    it 'stops at first valid signal' do
      signal = { segment: 'NSE_FNO', security_id: 12345, reason: 'OI buildup', meta: {} }
      allow(mock_engine).to receive(:evaluate).and_return(signal)

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, enabled_strategies)

      expect(result).to eq(signal)
      expect(mock_engine).to have_received(:evaluate).once
    end

    it 'tries next strategy if first returns nil' do
      momentum_engine = instance_double(Signal::Engines::MomentumBuyingEngine)
      allow(mock_engine).to receive(:evaluate).and_return(nil)
      allow(Signal::Engines::MomentumBuyingEngine).to receive(:new).and_return(momentum_engine)

      signal = { segment: 'NSE_FNO', security_id: 12345, reason: 'Momentum breakout', meta: {} }
      allow(momentum_engine).to receive(:evaluate).and_return(signal)

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, enabled_strategies)

      expect(result).to eq(signal)
      expect(mock_engine).to have_received(:evaluate).once
      expect(momentum_engine).to have_received(:evaluate).once
    end

    it 'returns nil if no strategies emit signal' do
      allow(mock_engine).to receive(:evaluate).and_return(nil)
      momentum_engine = instance_double(Signal::Engines::MomentumBuyingEngine)
      allow(Signal::Engines::MomentumBuyingEngine).to receive(:new).and_return(momentum_engine)
      allow(momentum_engine).to receive(:evaluate).and_return(nil)

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, enabled_strategies)

      expect(result).to be_nil
    end

    it 'returns nil if no candidates available' do
      allow(mock_analyzer).to receive(:select_candidates).and_return([])

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, enabled_strategies)

      expect(result).to be_nil
    end
  end

  describe '#process_signal' do
    let(:signal) do
      {
        segment: 'NSE_FNO',
        security_id: 12345,
        reason: 'OI buildup',
        meta: { candidate_symbol: 'NIFTY24FEB20000CE', lot_size: 50, multiplier: 1 }
      }
    end

    before do
      allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
    end

    it 'calls EntryGuard with correct parameters' do
      scheduler.send(:process_signal, index_cfg, signal)

      expect(Entries::EntryGuard).to have_received(:try_enter).with(
        index_cfg: index_cfg,
        pick: hash_including(
          segment: 'NSE_FNO',
          security_id: 12345,
          symbol: 'NIFTY24FEB20000CE',
          lot_size: 50
        ),
        direction: :bullish,
        scale_multiplier: 1
      )
    end
  end
end
