# frozen_string_literal: true

require 'rails_helper'

# Tests for exit_testing mode entry blockers:
# 1. expiry_trade_allowed? must return true in exit_testing mode
# 2. momentum_score must be nil (not 0) so StrikeSelector doesn't weak_momentum_skip
RSpec.describe Signal::Engine, 'exit_testing entry gates' do
  describe '#expiry_trade_allowed? in exit_testing mode' do
    context 'when run_mode is exit_testing' do
      before { allow(AlgoConfig).to receive(:run_mode).and_return('exit_testing') }

      it 'returns true regardless of expiry day status' do
        # Even if today is an expiry day, exit_testing mode must bypass the block
        allow(Market::ExpiryChecker).to receive(:expiry_today?).and_return(true)
        allow(Strategies::ExpiryModel).to receive(:session).and_return(:midday)

        result = described_class.send(:expiry_trade_allowed?, 'NIFTY')

        expect(result).to be true
      end
    end

    context 'when run_mode is production and it is expiry midday' do
      before { allow(AlgoConfig).to receive(:run_mode).and_return('production') }

      it 'returns false on expiry day midday session' do
        allow(Market::ExpiryChecker).to receive(:expiry_today?).and_return(true)
        allow(Strategies::ExpiryModel).to receive(:session).and_return(:midday)

        result = described_class.send(:expiry_trade_allowed?, 'NIFTY')

        expect(result).to be false
      end
    end
  end

  describe '#execute_execution_gates in exit_testing mode' do
    let(:index_cfg) { { key: 'SENSEX' } }
    let(:instrument) { instance_double(Instrument) }
    let(:series)     { build(:candle_series, :five_minute, :with_candles) }

    before { allow(AlgoConfig).to receive(:run_mode).and_return('exit_testing') }

    it 'returns momentum_score: nil so StrikeSelector does not apply weak_momentum_skip' do
      result = described_class.send(
        :execute_execution_gates,
        index_cfg, instrument, series, :bearish, {}, true
      )

      expect(result[:momentum_score]).to be_nil
    end

    it 'returns immediately without calling EntryFilterEngine' do
      expect(Entries::EntryFilterEngine).not_to receive(:new)

      described_class.send(
        :execute_execution_gates,
        index_cfg, instrument, series, :bearish, {}, true
      )
    end
  end
end
