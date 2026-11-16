# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiTechnicalAnalysisJob do
  describe '#perform' do
    before do
      allow(AlgoConfig).to receive(:scheduled_ai_technical_analysis_job_deferred?).and_return(false)
      allow(TradingSession::Service).to receive(:market_closed?).and_return(true)
      allow(Market::Calendar).to receive(:next_trading_day).and_return(Time.zone.parse('2026-11-17 09:15'))
      allow(Rails.logger).to receive_messages(info: nil, debug: nil)
    end

    it 'passes the query via ENV and keeps the command string static' do
      captured = {}
      allow_any_instance_of(described_class).to receive(:system) do |_job, env, cmd|
        captured[:env] = env
        captured[:cmd] = cmd
        true
      end

      described_class.perform_now('NIFTY')

      expect(captured[:cmd]).to eq('bundle exec rake ai:technical_analysis')
      expect(captured[:env]['QUERY']).to eq(
        'OPTIONS buying intraday for next trading day (2026-11-17) in INDEX like NIFTY'
      )
      expect(captured[:env]['STREAM']).to eq('true')
    end

    it 'rejects indices outside the configured set' do
      expect { described_class.perform_now('FAKEINDEX') }.to raise_error(ArgumentError, /Unknown index/)
    end
  end
end
