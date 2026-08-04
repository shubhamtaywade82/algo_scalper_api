# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Calibration::DatasetBuilder do
  let(:symbol) { 'NIFTY' }
  let(:days) { 30 }

  describe '.call' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { sl_pct: 0.10, tp_pct: 0.25 }
      })
    end

    let!(:tracker) do
      create(:position_tracker, :exited, :paper,
             symbol: 'NIFTY 20MAR24 22000 CE',
             created_at: 1.day.ago,
             exited_at: 1.day.ago + 10.minutes,
             entry_price: 100,
             exit_price: 120,
             last_pnl_rupees: 1000,
             last_pnl_pct: 0.2,
             segment: 'NSE_FNO',
             meta: { 'index_key' => 'NIFTY', 'entry_strategy' => 'supertrend', 'exit_reason' => 'target' })
    end

    let!(:telemetry) do
      create(:trade_telemetry, tracker: tracker,
             bos_age_at_entry: 5,
             retrace_pct: 0.5,
             max_r_reached: 2.5)
    end

    let!(:signal) do
      create(:trading_signal,
             index_key: 'NIFTY',
             signal_timestamp: tracker.created_at - 30.seconds,
             adx_value: 25.0,
             supertrend_value: 21900.0,
             direction: 'bullish',
             confidence_score: 0.8)
    end

    it 'builds a structured dataset' do
      result = described_class.call(symbol: symbol, days: days)

      expect(result[:symbol]).to eq('NIFTY')
      expect(result[:trades].size).to eq(1)

      trade = result[:trades].first
      expect(trade[:symbol]).to eq('NIFTY')
      expect(trade[:option_type]).to eq('CE')
      expect(trade[:last_pnl_rupees]).to eq(1000.0)
      expect(trade[:adx_value]).to eq(25.0)
      expect(trade[:bos_age_at_entry]).to eq(5)
    end

    it 'calculates meta statistics' do
      result = described_class.call(symbol: symbol, days: days)
      meta = result[:meta]

      expect(meta[:total_trades]).to eq(1)
      expect(meta[:win_rate]).to eq(100.0)
      expect(meta[:total_pnl]).to eq(1000.0)
      expect(meta[:exit_breakdown]['target']).to eq(1)
    end

    context 'when no trades found' do
      it 'returns empty trades array' do
        result = described_class.call(symbol: 'BANKNIFTY', days: days)
        expect(result[:trades]).to be_empty
        expect(result[:meta][:total_trades]).to eq(0)
      end
    end
  end
end
