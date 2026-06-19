# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomous::OptimizationJob do
  describe '#perform' do
    let(:index_keys) { %w[NIFTY BANKNIFTY SENSEX] }

    before do
      allow(IndiaIndexRegistry).to receive(:all_by_key).and_return(double(keys: index_keys))
      allow(Ai::Autonomous::Orchestrator).to receive(:call)
    end

    it 'calls Orchestrator for each symbol returned by IndiaIndexRegistry' do
      described_class.new.perform(days: 30, dry_run: false)

      index_keys.each do |symbol|
        expect(Ai::Autonomous::Orchestrator).to have_received(:call).with(
          symbol: symbol,
          days: 30,
          dry_run: false
        )
      end
    end

    it 'rescues errors per symbol and continues with other symbols' do
      allow(Ai::Autonomous::Orchestrator).to receive(:call)
        .with(symbol: 'NIFTY', days: 30, dry_run: false)
        .and_raise(StandardError.new("Test Error"))

      expect do
        described_class.new.perform(days: 30, dry_run: false)
      end.not_to raise_error

      expect(Ai::Autonomous::Orchestrator).to have_received(:call).with(
        symbol: 'BANKNIFTY',
        days: 30,
        dry_run: false
      )
      expect(Ai::Autonomous::Orchestrator).to have_received(:call).with(
        symbol: 'SENSEX',
        days: 30,
        dry_run: false
      )
    end
  end
end
