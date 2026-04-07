# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmcScannerJob do
  let(:job) { described_class.new }
  let(:indices) do
    [
      { key: :NIFTY, segment: 'IDX_I', sid: '13' },
      { key: :BANKNIFTY, segment: 'IDX_I', sid: '25' }
    ]
  end

  let(:nifty_instrument) do
    instance_double(Instrument, symbol_name: 'NIFTY', expiry_list: [Time.zone.today + 2.days])
  end
  let(:banknifty_instrument) do
    instance_double(Instrument, symbol_name: 'BANKNIFTY', expiry_list: [Time.zone.today + 10.days])
  end

  let(:bias_engine) { instance_double(Smc::BiasEngine, ai_enabled?: false, decision: :buy) }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return(indices)
    allow(Instrument).to receive(:find_by_sid_and_segment).with(security_id: '13', segment_code: 'IDX_I').and_return(nifty_instrument)
    allow(Instrument).to receive(:find_by_sid_and_segment).with(security_id: '25', segment_code: 'IDX_I').and_return(banknifty_instrument)

    allow(Smc::BiasEngine).to receive(:new).and_return(bias_engine)

    allow(AlgoConfig).to receive(:fetch).and_return({ signals: { max_expiry_days: 7 } })
    allow(job).to receive(:sleep) # skip actual sleeps
  end

  describe '#perform' do
    context 'when tick_ai_analysis_enabled and market is open' do
      it 'skips the scheduled scan and defers intraday work to tick events' do
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { tick_ai_analysis_enabled: true, max_expiry_days: 7 } })
        allow(Rails.logger).to receive(:info)

        job.perform

        expect(Smc::BiasEngine).not_to have_received(:new)
        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/SmcScannerJob.*Skipped intraday scheduled scan.*event-driven AI/i)
        )
      end
    end

    it 'loads indices, filters by expiry, and scans the remaining instruments' do
      # NIFTY has 2 days expiry (<= 7), BANKNIFTY has 10 days (> 7). Only NIFTY should be processed.
      job.perform

      expect(Smc::BiasEngine).to have_received(:new).with(nifty_instrument, delay_seconds: 1.0).once
      expect(Smc::BiasEngine).not_to have_received(:new).with(banknifty_instrument, anything)
    end

    it 'processes all indices if expiry filtering fails (fallback)' do
      allow(job).to receive(:max_expiry_days).and_raise(StandardError, 'Config Error')
      allow(job).to receive(:indices_without_expiry_filter).and_call_original

      # Given an error in calculating max_days, it should fallback to all instruments
      job.perform

      expect(job).to have_received(:indices_without_expiry_filter)
      expect(Smc::BiasEngine).to have_received(:new).twice
    end

    it 'sleeps between instruments to avoid rate limits' do
      # Both within expiry
      allow(banknifty_instrument).to receive(:expiry_list).and_return([Time.zone.today + 3.days])

      # Should sleep for 2.0s before processing the second instrument
      job.perform

      expect(job).to have_received(:sleep).with(2.0).once
    end

    it 'handles DhanHQ rate limits with additional sleep' do
      allow(Smc::BiasEngine).to receive(:new).and_raise(DhanHQ::RateLimitError, 'Too many requests')

      expect { job.perform }.not_to raise_error

      expect(job).to have_received(:sleep).with(5).once
    end

    context 'when SCHEDULED_SMC_SCANNER forces scheduled run' do
      it 'runs even with tick_ai on and market open' do
        previous = ENV.fetch('SCHEDULED_SMC_SCANNER', nil)
        ENV['SCHEDULED_SMC_SCANNER'] = 'true'
        allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
        allow(AlgoConfig).to receive(:fetch).and_return({ signals: { tick_ai_analysis_enabled: true, max_expiry_days: 7 } })

        job.perform

        expect(Smc::BiasEngine).to have_received(:new).with(nifty_instrument, delay_seconds: 1.0).once
      ensure
        if previous.nil?
          ENV.delete('SCHEDULED_SMC_SCANNER')
        else
          ENV['SCHEDULED_SMC_SCANNER'] = previous
        end
      end
    end
  end

  describe '#process_ai_analysis' do
    let(:idx_cfg) { { key: :NIFTY } }

    before do
      allow(bias_engine).to receive_messages(
        ai_enabled?: true,
        analyze_with_ai: "AI says: <script>alert('hack')</script> up"
      )
      allow(job).to receive(:telegram_enabled?).and_return(true)
      allow(TelegramNotifier).to receive(:send_message)
    end

    it 'HTML escapes AI analysis output before sending to Telegram' do
      job.send(:process_index, idx_cfg, nifty_instrument)

      expect(TelegramNotifier).to have_received(:send_message) do |message, kwargs|
        expect(kwargs[:parse_mode]).to eq('HTML')
        expect(message).not_to include('<script>')
        expect(message).to include('&lt;script&gt;alert(&#39;hack&#39;)&lt;/script&gt; up')
      end
    end

    it 'does not send Telegram message if analysis is empty' do
      allow(bias_engine).to receive(:analyze_with_ai).and_return(nil)

      job.send(:process_index, idx_cfg, nifty_instrument)

      expect(TelegramNotifier).not_to have_received(:send_message)
    end
  end
end
