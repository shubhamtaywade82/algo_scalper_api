# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTechnicalAnalysisJob do
  describe '.perform' do
    it 'invokes rake via argv (no shell) with STREAM and QUERY set' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      allow(Open3).to receive(:capture2e).and_return(['', instance_double(Process::Status, success?: true, exitstatus: 0)])

      described_class.new.perform('NIFTY')

      expect(Open3).to have_received(:capture2e).with(
        {
          'STREAM' => 'true',
          'QUERY' => 'OPTIONS buying intraday in INDEX like NIFTY'
        },
        'bundle', 'exec', 'rake', 'ai:technical_analysis',
        chdir: Rails.root.to_s
      )
    end

    it 'logs failure when subprocess exits non-zero' do
      allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture2e).and_return(['rake failed', status])
      allow(Rails.logger).to receive(:error)

      described_class.new.perform('NIFTY')

      expect(Rails.logger).to have_received(:error).at_least(:once)
    end

    it 'raises when IndexConfigLoader returns no indices' do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])

      expect { described_class.new.send(:validate_index_key!, 'NIFTY') }.to raise_error(
        ArgumentError,
        /No indices loaded from IndexConfigLoader/
      )
    end
  end
end
