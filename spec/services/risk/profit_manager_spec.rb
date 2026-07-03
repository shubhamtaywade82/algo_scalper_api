# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::ProfitManager do
  subject(:profit_manager) { described_class.instance }

  describe '#classify_exit' do
    it "returns 'profit' for positive pnl" do
      expect(profit_manager.classify_exit(0.12)).to eq('profit')
    end

    it "returns 'profit' for a very small positive pnl" do
      expect(profit_manager.classify_exit(0.001)).to eq('profit')
    end

    it "returns 'loss' for negative pnl" do
      expect(profit_manager.classify_exit(-0.05)).to eq('loss')
    end

    it "returns 'breakeven' for zero pnl" do
      expect(profit_manager.classify_exit(0)).to eq('breakeven')
    end

    it "returns 'breakeven' for nil" do
      expect(profit_manager.classify_exit(nil)).to eq('breakeven')
    end

    it "returns 'loss' for a very small negative pnl" do
      expect(profit_manager.classify_exit(-0.0001)).to eq('loss')
    end
  end

  describe '#peak_profit_pct_for' do
    let(:tracker) { instance_double(PositionTracker, entry_price: 150.0, quantity: 75) }

    context 'when snapshot has positive hwm_pnl' do
      let(:snapshot) { { hwm_pnl: 5000.0 } }

      it 'calculates peak profit pct as decimal fraction' do
        result = profit_manager.peak_profit_pct_for(tracker, snapshot)
        expect(result).to be_within(0.001).of(5000.0 / (150.0 * 75.0))
      end
    end

    context 'when hwm_pnl is negative' do
      let(:snapshot) { { hwm_pnl: -100.0 } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when hwm_pnl is nil' do
      let(:snapshot) { { hwm_pnl: nil } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when hwm_pnl is zero' do
      let(:snapshot) { { hwm_pnl: 0 } }

      it 'returns nil (not positive)' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when entry_price is nil' do
      let(:tracker) { instance_double(PositionTracker, entry_price: nil, quantity: 75) }
      let(:snapshot) { { hwm_pnl: 5000.0 } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when quantity is nil' do
      let(:tracker) { instance_double(PositionTracker, entry_price: 150.0, quantity: nil) }
      let(:snapshot) { { hwm_pnl: 5000.0 } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when quantity is zero' do
      let(:tracker) { instance_double(PositionTracker, entry_price: 150.0, quantity: 0) }
      let(:snapshot) { { hwm_pnl: 5000.0 } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'when buy_value is zero (entry_price is zero)' do
      let(:tracker) { instance_double(PositionTracker, entry_price: 0, quantity: 75) }
      let(:snapshot) { { hwm_pnl: 5000.0 } }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end

    context 'with missing snapshot key' do
      let(:snapshot) { {} }

      it 'returns nil' do
        expect(profit_manager.peak_profit_pct_for(tracker, snapshot)).to be_nil
      end
    end
  end

  describe '#allowed_drawdown_for_peak' do
    let(:adaptive_tiers) { { 0.10 => 0.5, 0.20 => 0.3, 0.30 => 0.2 } }

    it 'delegates to Positions::TrailingConfig.adaptive_drawdown_for_peak' do
      allow(Positions::TrailingConfig).to receive(:adaptive_drawdown_for_peak).and_return(0.3)

      result = profit_manager.allowed_drawdown_for_peak(0.25, adaptive_tiers)

      expect(Positions::TrailingConfig).to have_received(:adaptive_drawdown_for_peak).with(0.25, adaptive_tiers)
      expect(result).to eq(0.3)
    end

    context 'when peak_profit_pct is nil' do
      it 'returns nil' do
        expect(profit_manager.allowed_drawdown_for_peak(nil, adaptive_tiers)).to be_nil
      end
    end

    context 'when adaptive_tiers is nil' do
      it 'returns nil' do
        expect(profit_manager.allowed_drawdown_for_peak(0.25, nil)).to be_nil
      end
    end
  end
end
