# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Analyzer do
  let(:tracker) { instance_double(PositionTracker, entry_price: BigDecimal('150.0'), quantity: 75, high_water_mark_pnl: 5000.0) }
  let(:ltp) { 180.0 }
  let(:prices) { [175.0, 180.0, 178.0] }

  describe '#initialize' do
    it 'stores ltp as float' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp)
      expect(analyzer.instance_variable_get(:@ltp)).to eq(180.0)
    end

    it 'stores entry_price as float' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp)
      expect(analyzer.instance_variable_get(:@entry_price)).to eq(150.0)
    end

    it 'calculates highest_price from entry_price and peak_profit_pct' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp)
      peak_pct = 5000.0 / (150.0 * 75.0)
      expect(analyzer.instance_variable_get(:@highest_price)).to eq(150.0 * (1.0 + peak_pct))
    end

    it 'uses provided peak_profit_pct instead of calculating' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp, peak_profit_pct: 0.10)
      expect(analyzer.instance_variable_get(:@peak_profit_pct)).to eq(0.10)
      expect(analyzer.instance_variable_get(:@highest_price)).to eq(150.0 * 1.10)
    end

    it 'wraps price in an array when passed as scalar' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp, prices: 180.0)
      expect(analyzer.instance_variable_get(:@prices)).to eq([180.0])
    end
  end

  describe '#recommended_sl' do
    let(:exit_engine) { instance_double(Orders::ExitEngine) }
    let(:gamma_engine) { instance_double(Orders::GammaTrailingEngine) }

    before do
      allow(Orders::ExitEngine).to receive(:new).and_return(exit_engine)
      allow(Orders::GammaTrailingEngine).to receive(:new).and_return(gamma_engine)
      allow(exit_engine).to receive_messages(force_exit?: false, recommended_sl: 165.0)
      allow(gamma_engine).to receive(:call).and_return(170.0)
    end

    it 'returns the most conservative (highest) SL between exit_engine and gamma_engine' do
      analyzer = described_class.new(tracker: tracker, ltp: ltp, prices: prices)
      expect(analyzer.recommended_sl).to eq(170.0)
    end

    it 'uses base_sl when gamma_sl is nil' do
      allow(gamma_engine).to receive(:call).and_return(nil)

      analyzer = described_class.new(tracker: tracker, ltp: ltp, prices: prices)
      expect(analyzer.recommended_sl).to eq(165.0)
    end

    it 'uses gamma_sl when base_sl is nil' do
      allow(exit_engine).to receive(:recommended_sl).and_return(nil)

      analyzer = described_class.new(tracker: tracker, ltp: ltp, prices: prices)
      expect(analyzer.recommended_sl).to eq(170.0)
    end

    context 'when force_exit is triggered' do
      before do
        allow(exit_engine).to receive(:force_exit?).and_return(true)
      end

      it 'returns SL at 10% above current LTP' do
        analyzer = described_class.new(tracker: tracker, ltp: ltp, prices: prices)
        expect(analyzer.recommended_sl).to eq((180.0 * 1.1).round(2))
      end
    end

    context 'when no prices are provided' do
      it 'uses ltp as the only price' do
        analyzer = described_class.new(tracker: tracker, ltp: ltp)
        analyzer.recommended_sl

        expect(Orders::ExitEngine).to have_received(:new).with(position: tracker, prices: [ltp])
      end
    end

    context 'with zero ltp' do
      let(:ltp) { 0.0 }

      before do
        allow(exit_engine).to receive(:force_exit?).and_return(true)
      end

      it 'returns SL at 10% above 0 (edge case handled gracefully)' do
        analyzer = described_class.new(tracker: tracker, ltp: ltp)
        expect(analyzer.recommended_sl).to eq(0.0)
      end
    end

    context 'with nil peak_profit_pct' do
      let(:tracker) { instance_double(PositionTracker, entry_price: BigDecimal('150.0'), quantity: 75, high_water_mark_pnl: nil) }

      it 'calculates peak_profit_pct from hwm_pnl' do
        analyzer = described_class.new(tracker: tracker, ltp: ltp)
        expect(analyzer.instance_variable_get(:@peak_profit_pct)).to eq(0.0)
        expect(analyzer.instance_variable_get(:@highest_price)).to eq(150.0)
      end
    end
  end
end
