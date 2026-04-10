# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTechnicalAnalysisJob do
  describe '.perform' do
    it 'invokes rake via argv (no shell) with STREAM and QUERY set' do
      allow(AlgoConfig).to receive(:scheduled_ai_technical_analysis_job_deferred?).and_return(false)
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
      allow(AlgoConfig).to receive(:scheduled_ai_technical_analysis_job_deferred?).and_return(false)
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

    context 'when scheduled intraday AI is deferred' do
      it 'skips rake and logs deferral' do
        allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY' }])
        allow(AlgoConfig).to receive(:scheduled_ai_technical_analysis_job_deferred?).and_return(true)
        allow(Open3).to receive(:capture2e)
        allow(Rails.logger).to receive(:info)

        described_class.new.perform('NIFTY')

        expect(Open3).not_to have_received(:capture2e)
        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/AiTechnicalAnalysisJob.*Skipped NIFTY.*event-driven intraday AI/)
        )
      end
    end

    context 'when tick_ai_analysis_enabled but market is closed' do
      it 'still invokes rake for overnight path' do
        allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY' }])
        allow(AlgoConfig).to receive(:scheduled_ai_technical_analysis_job_deferred?).and_return(false)
        allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { tick_ai_analysis_enabled: true } })
        allow(Open3).to receive(:capture2e).and_return(['', instance_double(Process::Status, success?: true, exitstatus: 0)])
        allow(Rails.cache).to receive(:read).and_return(true)
        allow(Market::Calendar).to receive(:next_trading_day).and_return(Date.tomorrow)
        allow(Live::TimeRegimeService).to receive(:closed_session_label).and_return('after_hours')

        described_class.new.perform('NIFTY')

        expect(Open3).to have_received(:capture2e)
      end
    end

    context 'when SCHEDULED_AI_TECHNICAL_ANALYSIS forces scheduled run' do
      it 'invokes rake even with tick_ai on and market open' do
        previous = ENV.fetch('SCHEDULED_AI_TECHNICAL_ANALYSIS', nil)
        ENV['SCHEDULED_AI_TECHNICAL_ANALYSIS'] = 'true'
        allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY' }])
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { tick_ai_analysis_enabled: true } })
        allow(Open3).to receive(:capture2e).and_return(['', instance_double(Process::Status, success?: true, exitstatus: 0)])

        described_class.new.perform('NIFTY')

        expect(Open3).to have_received(:capture2e)
      ensure
        if previous.nil?
          ENV.delete('SCHEDULED_AI_TECHNICAL_ANALYSIS')
        else
          ENV['SCHEDULED_AI_TECHNICAL_ANALYSIS'] = previous
        end
      end
    end
  end
end
