# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Calibration::Runner do
  let(:symbol) { 'NIFTY' }
  let(:days) { 30 }

  before do
    # Mock DatasetBuilder to return enough trades
    allow(Ai::Calibration::DatasetBuilder).to receive(:call).and_return({
      symbol: 'NIFTY',
      trades: Array.new(20) { { entry_price: 100, exit_price: 110, pnl: 1000 } },
      meta: { win_rate: 60.0 }
    })

    # Mock PromptBuilder
    allow(Ai::Calibration::PromptBuilder).to receive(:call).and_return('prompt')

    # Mock OpenaiClient generate
    client = double('client', enabled?: true)
    allow(Services::Ai::OpenaiClient).to receive(:instance).and_return(client)
    allow(client).to receive(:preferred_text_model).and_return('model')
    allow(client).to receive(:generate).and_return({ 'system_diagnosis' => {}, 'parameter_changes' => [] })

    # Mock ResultParser
    allow(Ai::Calibration::ResultParser).to receive(:call).and_return({
      proposed_patch: { 'risk' => { 'sl_pct' => 0.12 } },
      diagnosis: {},
      parameter_changes: [],
      entry_filters: [],
      exit_improvements: [],
      regime_rules: []
    })

    # Mock BacktestValidator
    allow(Ai::Calibration::BacktestValidator).to receive(:call).and_return({
      approved: true,
      baseline_pnl: 1000,
      projected_pnl: 1100,
      baseline_metrics: {},
      projected_metrics: {}
    })
  end

  describe '.call' do
    it 'orchestrates the pipeline and returns a CalibrationRun' do
      expect(Ai::Calibration::ConfigApplier).to receive(:call).and_call_original
      run = described_class.call(symbol: symbol, days: days)
      expect(run).to be_a(CalibrationRun)
    end

    it 'raises InsufficientDataError if trades < 20' do
      allow(Ai::Calibration::DatasetBuilder).to receive(:call).and_return({ trades: Array.new(10) })
      
      expect(Rails.logger).to receive(:warn).with(/10 trades < MIN_TRADES/)
      run = described_class.call(symbol: symbol, days: days)
      expect(run).to be_nil
    end

    it 'returns nil if BacktestValidator rejects' do
      allow(Ai::Calibration::BacktestValidator).to receive(:call).and_return({ approved: false, rejection_reason: 'low pnl' })
      run = described_class.call(symbol: symbol, days: days)
      expect(run).to be_nil
    end
  end
end
