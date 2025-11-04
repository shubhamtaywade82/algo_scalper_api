# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::OhlcPrefetcherService, :vcr do
  let(:service) { described_class.instance }

  before do
    # Reset singleton state
    service.stop! if service.running?
    service.instance_variable_set(:@running, false)
    service.instance_variable_set(:@thread, nil)

    # Clean up watchlist items
    WatchlistItem.where(segment: %w[IDX_I NSE_FNO], security_id: %w[13 25 51]).delete_all
  end

  after do
    service.stop! if service.running?
    WatchlistItem.where(segment: %w[IDX_I NSE_FNO], security_id: %w[13 25 51]).delete_all
  end

  describe 'EPIC C — C1: Staggered OHLC Fetch' do
    describe '#start!' do
      context 'when starting the service' do
        it 'marks service as running' do
          allow(service).to receive(:fetch_all_watchlist)
          allow(service).to receive(:sleep)
          service.start!
          expect(service).to be_running
        end

        it 'creates a background thread' do
          allow(service).to receive(:fetch_all_watchlist)
          allow(service).to receive(:sleep)
          service.start!
          thread = service.instance_variable_get(:@thread)
          expect(thread).to be_a(Thread)
          expect(thread.name).to eq('ohlc-prefetcher')
        end

        it 'does not start if already running' do
          allow(service).to receive(:fetch_all_watchlist)
          allow(service).to receive(:sleep)
          service.start!
          first_thread = service.instance_variable_get(:@thread)
          service.start!
          second_thread = service.instance_variable_get(:@thread)
          expect(first_thread).to eq(second_thread)
        end

        it 'is thread-safe' do
          allow(service).to receive(:fetch_all_watchlist)
          allow(service).to receive(:sleep)
          threads = []
          5.times do
            threads << Thread.new { service.start! }
          end
          threads.each(&:join)
          expect(service).to be_running
          # Should only have one thread despite concurrent starts
          expect(service.instance_variable_get(:@thread)).not_to be_nil
        end
      end
    end

    describe '#stop!' do
      before do
        allow(service).to receive(:fetch_all_watchlist)
        allow(service).to receive(:sleep)
        service.start!
      end

      it 'marks service as not running' do
        service.stop!
        expect(service).not_to be_running
      end

      it 'clears thread reference' do
        service.stop!
        expect(service.instance_variable_get(:@thread)).to be_nil
      end

      it 'wakes up sleeping thread' do
        thread = service.instance_variable_get(:@thread)
        expect(thread).to receive(:wakeup).and_call_original
        service.stop!
      end

      it 'handles thread wakeup errors gracefully' do
        thread = service.instance_variable_get(:@thread)
        allow(thread).to receive(:wakeup).and_raise(ThreadError, 'Thread not sleeping')
        expect { service.stop! }.not_to raise_error
      end
    end

    describe '#running?' do
      it 'returns false initially' do
        expect(service).not_to be_running
      end

      it 'returns true after start' do
        allow(service).to receive(:fetch_all_watchlist)
        allow(service).to receive(:sleep)
        service.start!
        expect(service).to be_running
      end

      it 'returns false after stop' do
        allow(service).to receive(:fetch_all_watchlist)
        allow(service).to receive(:sleep)
        service.start!
        service.stop!
        expect(service).not_to be_running
      end
    end

    describe 'Background Loop' do
      before do
        allow(service).to receive(:sleep) # Don't actually sleep in tests
      end

      it 'calls fetch_all_watchlist in loop' do
        expect(service).to receive(:fetch_all_watchlist).at_least(:once)
        service.start!
        sleep 0.1 # Give thread time to run
        service.stop!
      end

      it 'sleeps LOOP_INTERVAL_SECONDS between iterations' do
        allow(service).to receive(:fetch_all_watchlist)
        expect(service).to receive(:sleep).with(described_class::LOOP_INTERVAL_SECONDS).at_least(:once)
        service.start!
        sleep 0.1
        service.stop!
      end

      it 'handles errors in loop gracefully' do
        allow(service).to receive(:fetch_all_watchlist).and_raise(StandardError, 'Test error')
        allow(Rails.logger).to receive(:error)
        service.start!
        sleep 0.1
        expect(Rails.logger).to have_received(:error).with(
          match(/OhlcPrefetcherService crashed/)
        )
        expect(service).not_to be_running
        service.stop!
      end
    end

    describe '#fetch_all_watchlist' do
      let!(:nifty_instrument) { create(:instrument, :nifty_index) }
      let!(:banknifty_instrument) { create(:instrument, :banknifty_index) }
      let!(:nifty) { create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true, watchable: nifty_instrument) }
      let!(:banknifty) { create(:watchlist_item, segment: 'IDX_I', security_id: '25', active: true, watchable: banknifty_instrument) }
      let!(:inactive) { create(:watchlist_item, segment: 'IDX_I', security_id: '51', active: false) }

      before do
        allow(service).to receive(:sleep) # Don't actually sleep
      end

      it 'fetches OHLC for all active watchlist items' do
        # Verify instruments are set up correctly
        expect(nifty_instrument).to be_persisted
        expect(banknifty_instrument).to be_persisted
        expect(nifty.watchable).to eq(nifty_instrument)
        expect(banknifty.watchable).to eq(banknifty_instrument)

        # Capture logs to verify API calls via VCR cassettes
        info_calls = []
        debug_calls = []
        warn_calls = []
        allow(Rails.logger).to receive(:info) do |*args, &block|
          info_calls << (block ? block.call : args.first)
        end
        allow(Rails.logger).to receive(:debug) do |*args, &block|
          debug_calls << (block ? block.call : args.first)
        end
        allow(Rails.logger).to receive(:warn) do |*args, &block|
          warn_calls << (block ? block.call : args.first)
        end

        service.send(:fetch_all_watchlist)

        # VCR cassettes exist - verify API calls were made
        # The service should log info for each instrument fetch
        if warn_calls.any?
          # API error occurred - this should not happen with VCR cassettes
          # Still check that we tried to fetch (debug logs would show instrument not found)
          expect(debug_calls.none? { |msg| msg.to_s.match(/Instrument not found/) }).to be_truthy,
                 "Instruments not found. Debug: #{debug_calls.map(&:to_s).join(', ')}"
        end

        # With VCR cassettes, we should get info logs for successful fetches
        # Even if data parsing results in fetched=0, we should still get logs
        expect(info_calls.size).to be >= 2,
               "Expected at least 2 info logs (one per active watchlist item). Got: #{info_calls.size}. Info: #{info_calls.map(&:to_s).join(', ')}. Debug: #{debug_calls.map(&:to_s).join(', ')}. Warnings: #{warn_calls.map(&:to_s).join(', ')}"
        expect(info_calls.any? { |msg| msg.to_s.match(/OHLC prefetch/) }).to be_truthy
      end

      it 'does not fetch for inactive watchlist items' do
        # Inactive items are filtered by WatchlistItem.active scope
        info_calls = []
        allow(Rails.logger).to receive(:info) { |*args, &block| info_calls << (block ? block.call : args.first) }
        allow(Rails.logger).to receive(:warn) # Allow warnings
        allow(Rails.logger).to receive(:debug) # Allow debug logs

        service.send(:fetch_all_watchlist)

        # With VCR cassettes, we should get exactly 2 logs (one per active item: nifty and banknifty)
        # Security ID '51' (inactive SENSEX) should not appear in any logs
        expect(info_calls.size).to eq(2),
               "Expected exactly 2 info logs for active items. Got: #{info_calls.size}. Logs: #{info_calls.map(&:to_s).join(', ')}"
        expect(info_calls.none? { |msg| msg.to_s.include?('51') }).to be_truthy,
               "Inactive item (security_id: 51) should not appear in logs. Logs: #{info_calls.map(&:to_s).join(', ')}"
      end

      it 'sleeps STAGGER_SECONDS between each fetch' do
        expect(service).to receive(:sleep).with(described_class::STAGGER_SECONDS).at_least(2).times
        service.send(:fetch_all_watchlist)
      end

      it 'processes in batches of 100' do
        allow(WatchlistItem).to receive(:active).and_return(WatchlistItem.active)
        expect(WatchlistItem.active).to receive(:find_in_batches).with(batch_size: 100).and_yield([nifty, banknifty])
        service.send(:fetch_all_watchlist)
      end

      it 'returns early if WatchlistItem is not defined' do
        original_watchlist_item = WatchlistItem
        Object.send(:remove_const, :WatchlistItem) if Object.const_defined?(:WatchlistItem)

        expect(service).not_to receive(:fetch_one)
        expect { service.send(:fetch_all_watchlist) }.not_to raise_error
      ensure
        Object.const_set(:WatchlistItem, original_watchlist_item)
      end
    end

    describe '#fetch_one' do
      let(:watchlist_item) { create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true) }
      let(:instrument) { create(:instrument, segment: 'I', security_id: '13') }

      context 'when instrument is found via watchable' do
        before do
          watchlist_item.update(watchable: instrument)
        end

        it 'uses watchable instrument and makes API call via VCR' do
          # VCR will record/playback actual API calls
          expect(Rails.logger).to receive(:info) do |&block|
            message = block.call
            expect(message).to match(/OHLC prefetch.*fetched=/)
          end
          service.send(:fetch_one, watchlist_item)
        end

        it 'does not query database for instrument' do
          expect(Instrument).not_to receive(:find_by_sid_and_segment)
          allow(Rails.logger).to receive(:info)
          service.send(:fetch_one, watchlist_item)
        end
      end

      context 'when instrument is found via database lookup' do
        before do
          watchlist_item.update(watchable: nil)
          # VCR will handle actual API calls
          allow(Rails.logger).to receive(:info)
        end

        it 'looks up instrument from database' do
          expect(Instrument).to receive(:find_by_sid_and_segment)
            .with(security_id: '13', segment_code: 'IDX_I')
            .and_return(instrument)
          service.send(:fetch_one, watchlist_item)
        end

        it 'fetches OHLC for the instrument via VCR' do
          allow(Instrument).to receive(:find_by_sid_and_segment)
            .with(security_id: '13', segment_code: 'IDX_I')
            .and_return(instrument)
          # Actual API call will be made - VCR will record/playback
          expect(Rails.logger).to receive(:info) do |&block|
            message = block.call
            expect(message).to match(/OHLC prefetch/)
          end
          service.send(:fetch_one, watchlist_item)
        end
      end

      context 'when instrument is not found' do
        before do
          watchlist_item.update(watchable: nil)
          allow(Instrument).to receive(:find_by_sid_and_segment)
            .with(security_id: '13', segment_code: 'IDX_I')
            .and_return(nil)
          allow(Rails.logger).to receive(:debug)
        end

        it 'logs debug message' do
          expect(Rails.logger).to receive(:debug) do |&block|
            expect(block.call).to match(/Instrument not found/)
          end
          service.send(:fetch_one, watchlist_item)
        end

        it 'does not attempt to fetch OHLC' do
          expect_any_instance_of(Instrument).not_to receive(:intraday_ohlc)
          service.send(:fetch_one, watchlist_item)
        end
      end

      context 'when parsing OHLC data from VCR cassette' do
        before do
          watchlist_item.update(watchable: instrument)
          allow(Rails.logger).to receive(:info)
        end

        it 'parses real OHLC data from API via VCR' do
          # VCR will provide real OHLC data structure from cassette
          expect(Rails.logger).to receive(:info) do |&block|
            message = block.call
            expect(message).to match(/OHLC prefetch.*fetched=/)
          end
          service.send(:fetch_one, watchlist_item)
        end

        it 'extracts timestamp information from real data' do
          expect(Rails.logger).to receive(:info) do |&block|
            message = block.call
            # Real data will have timestamp info if available
            expect(message).to match(/OHLC prefetch/)
          end
          service.send(:fetch_one, watchlist_item)
        end

        it 'logs fetch summary with instrument details' do
          expect(Rails.logger).to receive(:info) do |&block|
            message = block.call
            expect(message).to match(/OHLC prefetch.*#{instrument.exchange_segment}:#{instrument.security_id}/)
          end
          service.send(:fetch_one, watchlist_item)
        end
      end

      context 'when API call fails' do
        before do
          watchlist_item.update(watchable: instrument)
          allow(instrument).to receive(:intraday_ohlc).and_raise(StandardError, 'API error')
          allow(instrument).to receive(:exchange_segment).and_return('IDX_I')
          allow(instrument).to receive(:security_id).and_return('13')
          allow(Rails.logger).to receive(:warn)
        end

        it 'handles errors gracefully' do
          expect { service.send(:fetch_one, watchlist_item) }.not_to raise_error
        end

        it 'logs warning message' do
          expect(Rails.logger).to receive(:warn) do |message|
            expect(message).to match(/Failed for IDX_I:13/)
            expect(message).to match(/API error/)
          end
          service.send(:fetch_one, watchlist_item)
        end
      end
    end

    describe 'Constants' do
      it 'has correct LOOP_INTERVAL_SECONDS' do
        expect(described_class::LOOP_INTERVAL_SECONDS).to eq(60)
      end

      it 'has correct STAGGER_SECONDS' do
        expect(described_class::STAGGER_SECONDS).to eq(0.5)
      end

      it 'has correct DEFAULT_INTERVAL' do
        expect(described_class::DEFAULT_INTERVAL).to eq('5')
      end

      it 'has correct LOOKBACK_DAYS' do
        expect(described_class::LOOKBACK_DAYS).to eq(2)
      end
    end

    describe 'Integration with WatchlistItem' do
      let!(:nifty_wl) { create(:watchlist_item, segment: 'IDX_I', security_id: '13', active: true) }
      let!(:banknifty_wl) { create(:watchlist_item, segment: 'IDX_I', security_id: '25', active: true) }
      let!(:nifty_instrument) { create(:instrument, segment: 'I', security_id: '13') }
      let!(:banknifty_instrument) { create(:instrument, segment: 'I', security_id: '25') }

      before do
        nifty_wl.update(watchable: nifty_instrument)
        banknifty_wl.update(watchable: banknifty_instrument)

        allow(Rails.logger).to receive(:info)
        allow(service).to receive(:sleep) # Don't actually sleep
        # VCR will handle actual API calls
      end

      it 'processes all active watchlist items via VCR' do
        # VCR will record/playback actual API calls for both instruments
        call_count = 0
        expect(Rails.logger).to receive(:info).at_least(:twice) do |&block|
          call_count += 1
          message = block.call
          expect(message).to match(/OHLC prefetch/) if call_count <= 2
        end

        service.send(:fetch_all_watchlist)
      end

      it 'respects stagger timing between fetches' do
        expect(service).to receive(:sleep).with(0.5).at_least(:twice) # Once after each fetch
        allow(Rails.logger).to receive(:info)

        service.send(:fetch_all_watchlist)
      end
    end
  end
end
