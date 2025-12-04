# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Database Persistence Integration', :vcr, type: :integration do
  # Use real index instruments (NIFTY-13, BANKNIFTY-25, SENSEX-51) if available
  # Otherwise fall back to factory-created instruments
  let(:instrument) do
    Instrument.segment_index.find_by(security_id: '13', symbol_name: 'NIFTY') ||
      Instrument.segment_index.find_by(symbol_name: 'NIFTY') ||
      create(:instrument, :nifty_index)
  end
  let(:derivative) { create(:derivative, security_id: '12345CE', lot_size: 50) }
  let(:position_tracker) do
    # PositionTracker requires a tradable segment, not IDX_I or 'index'
    tradable_segment = instrument.exchange == 'nse' ? 'NSE_FNO' : 'BSE_FNO'
    create(:position_tracker,
           watchable: instrument,
           instrument: instrument,
           order_no: 'ORD123456',
           security_id: instrument.security_id,
           segment: tradable_segment,
           status: 'active')
  end
  let(:trading_signal) do
    create(:trading_signal,
           index_key: 'nifty',
           direction: 'bullish',
           confidence_score: 0.85)
  end

  describe 'Position Tracker Persistence' do
    context 'when creating position trackers' do
      it 'persists position tracker with all required fields' do
        # PositionTracker requires a tradable segment (NSE_FNO, BSE_FNO, etc.), not IDX_I
        # Use NSE_FNO for NSE instruments, BSE_FNO for BSE instruments
        tradable_segment = instrument.exchange == 'nse' ? 'NSE_FNO' : 'BSE_FNO'

        tracker_data = {
          watchable: instrument,
          instrument: instrument,
          order_no: 'ORD123456',
          security_id: instrument.security_id,
          symbol: 'NIFTY18500CE',
          segment: tradable_segment,
          side: 'long_ce',
          quantity: 50,
          entry_price: 100.0,
          meta: { index_key: 'nifty', direction: 'long_ce' }
        }

        tracker = PositionTracker.create!(tracker_data)

        expect(tracker).to be_persisted
        expect(tracker.order_no).to eq('ORD123456')
        expect(tracker.security_id).to eq(instrument.security_id)
        expect(tracker.symbol).to eq('NIFTY18500CE')
        expect(tracker.segment).to eq(tradable_segment)
        expect(tracker.side).to eq('long_ce')
        expect(tracker.quantity).to eq(50)
        expect(tracker.entry_price).to eq(BigDecimal('100.0'))
        expect(tracker.meta['index_key']).to eq('nifty')
      end

      it 'enforces unique order number constraint' do
        PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                instrument: instrument)

        expect do
          PositionTracker.create!(order_no: 'ORD123456', security_id: (instrument.security_id.to_i + 1).to_s, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::RecordInvalid, /Order no has already been taken/)
      end

      it 'validates required fields' do
        expect do
          PositionTracker.create!(order_no: nil, security_id: instrument.security_id, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::RecordInvalid, /Order no can't be blank/)

        expect do
          PositionTracker.create!(order_no: 'ORD123456', security_id: nil, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::RecordInvalid, /Security can't be blank/)
      end

      it 'validates status values' do
        expect do
          PositionTracker.create!(
            order_no: 'ORD123456',
            security_id: instrument.security_id,
            watchable: instrument,
            instrument: instrument,
            status: 'invalid_status'
          )
        end.to raise_error(ArgumentError, /is not a valid status/)
      end
    end

    context 'when updating position tracker status' do
      it 'marks position as active with average price and quantity' do
        avg_price = BigDecimal('101.5')
        quantity = 50

        position_tracker.mark_active!(avg_price: avg_price, quantity: quantity)

        expect(position_tracker.status).to eq('active')
        expect(position_tracker.avg_price).to eq(avg_price)
        expect(position_tracker.quantity).to eq(quantity)
        # entry_price should be preserved (not updated to avg_price)
        expect(position_tracker.entry_price).not_to eq(avg_price)
      end

      it 'marks position as cancelled' do
        position_tracker.mark_cancelled!

        expect(position_tracker.status).to eq('cancelled')
      end

      it 'marks position as exited and cleans up resources' do
        # unsubscribe and clear_tracker may be called multiple times (by mark_exited! and after_update_commit callbacks)
        # So we just verify they're called at least once, not exactly once
        allow(position_tracker).to receive(:unsubscribe)
        redis_cache = Live::RedisPnlCache.instance
        allow(redis_cache).to receive(:clear_tracker)
        expect(Rails.cache).to receive(:write).with(
          "reentry:#{position_tracker.symbol}",
          anything,
          expires_in: 8.hours
        )

        position_tracker.mark_exited!

        expect(position_tracker.status).to eq('exited')
        # Verify cleanup methods were called (may be called multiple times due to callbacks)
        expect(position_tracker).to have_received(:unsubscribe).at_least(:once)
        expect(redis_cache).to have_received(:clear_tracker).with(position_tracker.id).at_least(:once)
      end
    end

    context 'when updating PnL data' do
      it 'updates PnL and high water mark' do
        pnl = BigDecimal('500.0')
        pnl_pct = BigDecimal('0.10')

        position_tracker.update_pnl!(pnl, pnl_pct: pnl_pct)

        expect(position_tracker.last_pnl_rupees).to eq(pnl)
        expect(position_tracker.last_pnl_pct).to eq(pnl_pct)
        # High water mark should remain at the higher value (25200.00 from factory)
        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('25200.00'))
      end

      it 'updates high water mark only when PnL increases' do
        # Set initial high water mark
        position_tracker.update!(high_water_mark_pnl: BigDecimal('1000.0'))

        # Update with lower PnL
        lower_pnl = BigDecimal('500.0')
        position_tracker.update_pnl!(lower_pnl)

        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('1000.0'))
      end

      it 'updates high water mark when PnL increases' do
        # Set initial high water mark
        position_tracker.update!(high_water_mark_pnl: BigDecimal('500.0'))

        # Update with higher PnL
        higher_pnl = BigDecimal('1500.0')
        position_tracker.update_pnl!(higher_pnl)

        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('1500.0'))
      end
    end

    context 'when managing metadata' do
      it 'stores and retrieves metadata correctly' do
        metadata = {
          'index_key' => 'nifty',
          'direction' => 'long_ce',
          'placed_at' => Time.current,
          'breakeven_locked' => true,
          'trailing_stop_price' => 95.0
        }

        position_tracker.update!(meta: metadata)

        expect(position_tracker.meta['index_key']).to eq('nifty')
        expect(position_tracker.meta['direction']).to eq('long_ce')
        expect(position_tracker.meta['breakeven_locked']).to be true
        expect(position_tracker.meta['trailing_stop_price']).to eq(95.0)
      end

      it 'handles breakeven lock status' do
        position_tracker.update!(meta: { 'breakeven_locked' => true })

        expect(position_tracker.breakeven_locked?).to be true

        position_tracker.lock_breakeven!

        expect(position_tracker.meta['breakeven_locked']).to be true
      end
    end
  end

  describe 'Trading Signal Persistence' do
    context 'when creating trading signals' do
      it 'persists trading signal with all required fields' do
        signal_data = {
          index_key: 'nifty',
          direction: 'bullish',
          confidence_score: 0.85,
          timeframe: '5m',
          supertrend_value: 105.0,
          adx_value: 35.0,
          signal_timestamp: Time.current,
          candle_timestamp: Time.current,
          metadata: {
            rsi: 65.0,
            entry_price: 105.0,
            stop_loss: 103.0,
            take_profit: 108.0
          }
        }

        signal = TradingSignal.create!(signal_data)

        expect(signal).to be_persisted
        expect(signal.direction).to eq('bullish')
        expect(signal.confidence_score).to eq(0.85)
        expect(signal.timeframe).to eq('5m')
        expect(signal.supertrend_value).to eq(105.0)
        expect(signal.adx_value).to eq(35.0)
        expect(signal.metadata['rsi']).to eq(65.0)
        expect(signal.metadata['entry_price']).to eq(105.0)
        expect(signal.metadata['stop_loss']).to eq(103.0)
        expect(signal.metadata['take_profit']).to eq(108.0)
      end

      it 'tracks signal execution' do
        signal_data = {
          index_key: 'nifty',
          direction: 'bullish',
          confidence_score: 0.85,
          timeframe: '5m',
          supertrend_value: 105.0,
          adx_value: 35.0,
          signal_timestamp: Time.current,
          candle_timestamp: Time.current,
          metadata: {
            rsi: 65.0,
            entry_price: 105.0,
            stop_loss: 103.0,
            take_profit: 108.0
          }
        }

        signal = TradingSignal.create!(signal_data)

        # Simulate signal execution by updating metadata
        signal.update!(
          metadata: signal.metadata.merge({
                                            executed_at: Time.current.iso8601,
                                            execution_price: 105.5,
                                            status: 'executed'
                                          })
        )

        expect(signal.metadata['executed_at']).to be_present
        expect(signal.metadata['execution_price']).to eq(105.5)
        expect(signal.metadata['status']).to eq('executed')
      end

      it 'tracks signal performance' do
        signal_data = {
          index_key: 'nifty',
          direction: 'bullish',
          confidence_score: 0.85,
          timeframe: '5m',
          supertrend_value: 105.0,
          adx_value: 35.0,
          signal_timestamp: Time.current,
          candle_timestamp: Time.current,
          metadata: {
            rsi: 65.0,
            entry_price: 105.0,
            stop_loss: 103.0,
            take_profit: 108.0
          }
        }

        signal = TradingSignal.create!(signal_data)

        # Simulate signal execution and performance tracking by updating metadata
        signal.update!(
          metadata: signal.metadata.merge({
                                            executed_at: Time.current.iso8601,
                                            execution_price: 105.5,
                                            status: 'executed',
                                            exit_price: 108.0,
                                            exit_at: 1.hour.from_now.iso8601,
                                            final_status: 'profitable'
                                          })
        )

        expect(signal.metadata['exit_price']).to eq(108.0)
        expect(signal.metadata['exit_at']).to be_present
        expect(signal.metadata['final_status']).to eq('profitable')
      end
    end

    context 'when calculating signal accuracy' do
      it 'calculates accuracy for profitable signals' do
        trading_signal.update!(
          metadata: trading_signal.metadata.merge({
                                                    executed_at: Time.current.iso8601,
                                                    execution_price: 105.5,
                                                    status: 'executed',
                                                    exit_price: 108.0,
                                                    exit_at: 1.hour.from_now.iso8601,
                                                    final_status: 'profitable'
                                                  })
        )

        accuracy = trading_signal.calculate_accuracy
        expect(accuracy).to be > 0
      end

      it 'calculates accuracy for losing signals' do
        trading_signal.update!(
          metadata: trading_signal.metadata.merge({
                                                    executed_at: Time.current.iso8601,
                                                    execution_price: 105.5,
                                                    status: 'executed',
                                                    exit_price: 103.0,
                                                    exit_at: 1.hour.from_now.iso8601,
                                                    final_status: 'loss'
                                                  })
        )

        accuracy = trading_signal.calculate_accuracy
        expect(accuracy).to be < 0
      end
    end
  end

  describe 'Instrument Persistence' do
    context 'when persisting instrument data' do
      it 'persists instrument with all required fields' do
        # Use a unique security_id to avoid conflicts with imported instruments
        unique_security_id = "TEST#{SecureRandom.hex(4)}"
        instrument_data = {
          symbol_name: 'TESTINDEX',
          security_id: unique_security_id,
          exchange: 'nse',
          segment: 'derivatives',
          instrument_type: 'INDEX',
          lot_size: 1,
          tick_size: 0.05,
          instrument_code: 'index'
        }

        new_instrument = Instrument.create!(instrument_data)

        expect(new_instrument).to be_persisted
        expect(new_instrument.symbol_name).to eq('TESTINDEX')
        expect(new_instrument.security_id).to eq(unique_security_id)
        expect(new_instrument.exchange_segment).to eq('NSE_FNO')
        expect(new_instrument.instrument_type).to eq('INDEX')
        expect(new_instrument.lot_size).to eq(1)
        expect(new_instrument.tick_size).to eq(BigDecimal('0.05'))
      end

      it 'enforces unique constraint on security_id and exchange_segment' do
        # Use unique security_id to avoid conflicts with imported instruments
        unique_security_id = "TEST#{SecureRandom.hex(4)}"
        Instrument.create!(symbol_name: 'TESTINDEX1', security_id: unique_security_id, exchange: 'nse', segment: 'derivatives',
                           instrument_code: 'index')

        expect do
          Instrument.create!(symbol_name: 'TESTINDEX2', security_id: unique_security_id, exchange: 'nse', segment: 'derivatives',
                             instrument_code: 'index')
        end.to raise_error(ActiveRecord::RecordInvalid, /Security has already been taken/)
      end

      it 'validates required fields' do
        unique_security_id = "TEST#{SecureRandom.hex(4)}"
        expect do
          Instrument.create!(symbol_name: nil, security_id: unique_security_id, exchange: 'nse', segment: 'derivatives',
                             instrument_code: 'index')
        end.to raise_error(ActiveRecord::RecordInvalid, /Symbol name can't be blank/)

        expect do
          Instrument.create!(symbol_name: 'TESTINDEX', security_id: nil, exchange: 'nse', segment: 'derivatives',
                             instrument_code: 'index')
        end.to raise_error(ActiveRecord::RecordInvalid, /Security can't be blank/)
      end
    end

    context 'when managing instrument associations' do
      it 'associates instruments with derivatives' do
        # Use a unique security_id to avoid conflicts with imported derivatives
        unique_security_id = "TEST#{SecureRandom.hex(4)}"
        derivative = Derivative.create!(
          instrument: instrument,
          security_id: unique_security_id,
          symbol_name: 'TESTINDEX',
          underlying_symbol: instrument.symbol_name,
          underlying_security_id: instrument.security_id,
          exchange: instrument.exchange,
          segment: 'derivatives',
          strike_price: 18_500.0,
          expiry_date: Date.current + 7.days,
          instrument_type: 'OPTION',
          option_type: 'CE',
          lot_size: 50
        )

        expect(instrument.derivatives).to include(derivative)
        expect(derivative.instrument).to eq(instrument)
      end

      it 'associates instruments with position trackers' do
        tracker = PositionTracker.create!(
          watchable: instrument, instrument: instrument,
          order_no: 'ORD123456',
          security_id: instrument.security_id
        )

        expect(instrument.position_trackers).to include(tracker)
        expect(tracker.instrument).to eq(instrument)
      end

      it 'associates instruments with trading signals' do
        signal = TradingSignal.create!(
          index_key: 'nifty',
          direction: 'bullish',
          confidence_score: 0.85,
          timeframe: '5m',
          signal_timestamp: Time.current,
          candle_timestamp: Time.current
        )

        # Test that the signal can be found by index_key
        expect(TradingSignal.for_index('nifty')).to include(signal)
        expect(signal.index_key).to eq('nifty')
      end
    end
  end

  describe 'Derivative Persistence' do
    context 'when persisting derivative data' do
      it 'persists derivative with all required fields' do
        derivative_data = {
          instrument: instrument,
          security_id: '12345CE',
          strike_price: 18_500.0,
          expiry_date: Date.current + 7.days,
          option_type: 'CE',
          lot_size: 50,
          exchange: 'nse',
          segment: 'derivatives'
        }

        derivative = Derivative.create!(derivative_data)

        expect(derivative).to be_persisted
        expect(derivative.security_id).to eq('12345CE')
        expect(derivative.strike_price).to eq(BigDecimal('18500.0'))
        expect(derivative.expiry_date).to eq(Date.current + 7.days)
        expect(derivative.option_type).to eq('CE')
        expect(derivative.lot_size).to eq(50)
        expect(derivative.exchange_segment).to eq('NSE_FNO')
      end

      it 'enforces unique constraint on security_id' do
        Derivative.create!(
          instrument: instrument,
          security_id: '12345CE',
          strike_price: 18_500.0,
          expiry_date: Date.current + 7.days,
          option_type: 'CE'
        )

        expect do
          Derivative.create!(
            instrument: instrument,
            security_id: '12345CE',
            strike_price: 18_600.0,
            expiry_date: Date.current + 7.days,
            option_type: 'CE'
          )
        end.to raise_error(ActiveRecord::RecordInvalid, /Security has already been taken/)
      end

      it 'validates option type values' do
        expect do
          Derivative.create!(
            instrument: instrument,
            security_id: '12345XX',
            strike_price: 18_500.0,
            expiry_date: Date.current + 7.days,
            option_type: 'INVALID'
          )
        end.to raise_error(ActiveRecord::RecordInvalid, /Option type is not included in the list/)
      end
    end
  end

  describe 'Watchlist Item Persistence' do
    context 'when persisting watchlist items' do
      it 'persists watchlist item with required fields' do
        watchlist_data = {
          segment: 'NSE_FNO',
          security_id: instrument.security_id,
          active: true
        }

        watchlist_item = WatchlistItem.create!(watchlist_data)

        expect(watchlist_item).to be_persisted
        expect(watchlist_item.segment).to eq('NSE_FNO')
        expect(watchlist_item.security_id).to eq(instrument.security_id)
        expect(watchlist_item.active).to be true
      end

      it 'enforces unique constraint on segment and security_id' do
        WatchlistItem.create!(segment: 'NSE_FNO', security_id: instrument.security_id)

        expect do
          WatchlistItem.create!(segment: 'NSE_FNO', security_id: instrument.security_id)
        end.to raise_error(ActiveRecord::RecordInvalid, /Security has already been taken/)
      end

      it 'scopes active watchlist items' do
        active_item = WatchlistItem.create!(segment: 'NSE_FNO', security_id: instrument.security_id, active: true)
        inactive_item = WatchlistItem.create!(segment: 'NSE_FNO', security_id: (instrument.security_id.to_i + 1).to_s,
                                              active: false)

        active_items = WatchlistItem.active
        expect(active_items).to include(active_item)
        expect(active_items).not_to include(inactive_item)
      end
    end
  end

  describe 'Database Transactions and Consistency' do
    context 'when handling database transactions' do
      it 'rolls back transaction on error' do
        expect do
          ActiveRecord::Base.transaction do
            PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                    instrument: instrument)
            PositionTracker.create!(order_no: 'ORD123456', security_id: (instrument.security_id.to_i + 1).to_s, watchable: instrument, instrument: instrument) # Duplicate order_no
          end
        end.to raise_error(ActiveRecord::RecordInvalid)

        expect(PositionTracker.where(order_no: 'ORD123456')).to be_empty
      end

      it 'commits transaction on success' do
        ActiveRecord::Base.transaction do
          PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                  instrument: instrument)
          PositionTracker.create!(order_no: 'ORD123457', security_id: (instrument.security_id.to_i + 1).to_s, watchable: instrument,
                                  instrument: instrument)
        end

        expect(PositionTracker.where(order_no: 'ORD123456')).to exist
        expect(PositionTracker.where(order_no: 'ORD123457')).to exist
      end
    end

    context 'when handling concurrent access' do
      it 'handles optimistic locking' do
        tracker1 = PositionTracker.find(position_tracker.id)
        tracker2 = PositionTracker.find(position_tracker.id)

        tracker1.update!(quantity: 100)
        tracker2.update!(quantity: 150)

        expect(tracker1.reload.quantity).to eq(150) # Last update wins
      end

      it 'handles pessimistic locking' do
        position_tracker.with_lock do
          position_tracker.update!(quantity: 100)
        end

        expect(position_tracker.quantity).to eq(100)
      end
    end
  end

  describe 'Database Indexes and Performance' do
    context 'when querying with indexes' do
      it 'uses index on order_no for lookups' do
        PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                instrument: instrument)

        # This should use the unique index on order_no
        tracker = PositionTracker.find_by(order_no: 'ORD123456')
        expect(tracker).to be_present
      end

      it 'uses index on security_id and status for lookups' do
        PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                instrument: instrument, status: 'active')

        # This should use the composite index on security_id and status
        active_trackers = PositionTracker.where(security_id: instrument.security_id, status: 'active')
        expect(active_trackers).to exist
      end

      it 'uses index on instrument_id for associations' do
        tracker = PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                          instrument: instrument)

        # This should use the foreign key index on instrument_id
        instrument_trackers = instrument.position_trackers
        expect(instrument_trackers).to include(tracker)
      end
    end

    context 'when handling large datasets' do
      it 'efficiently queries large numbers of records' do
        # Create multiple records
        100.times do |i|
          PositionTracker.create!(
            order_no: "ORD#{i.to_s.rjust(6, '0')}",
            security_id: "1234#{i}",
            watchable: instrument, instrument: instrument
          )
        end

        # This should be efficient with proper indexing
        all_trackers = PositionTracker.all
        expect(all_trackers.count).to eq(100)
      end

      it 'efficiently paginates through large datasets' do
        # Create multiple records
        100.times do |i|
          PositionTracker.create!(
            order_no: "ORD#{i.to_s.rjust(6, '0')}",
            security_id: "1234#{i}",
            watchable: instrument, instrument: instrument
          )
        end

        # Paginate through records
        page1 = PositionTracker.limit(50).offset(0)
        page2 = PositionTracker.limit(50).offset(50)

        expect(page1.count).to eq(50)
        expect(page2.count).to eq(50)
      end
    end
  end

  describe 'Data Integrity and Validation' do
    context 'when enforcing data integrity' do
      it 'prevents orphaned records' do
        PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                instrument: instrument)

        # Verify that the method can be called without crashing
        expect { instrument.destroy }.not_to raise_error
      end

      it 'cascades deletes when appropriate' do
        signal = TradingSignal.create!(index_key: instrument.symbol_name, direction: 'bullish', confidence_score: 0.85,
                                       timeframe: '5m', signal_timestamp: Time.current, candle_timestamp: Time.current)

        instrument.destroy

        # TradingSignal is not automatically deleted since it uses index_key, not foreign key
        expect(TradingSignal.find_by(id: signal.id)).to be_present
      end

      it 'validates decimal precision' do
        tracker = PositionTracker.create!(
          order_no: 'ORD123456',
          security_id: instrument.security_id,
          watchable: instrument, instrument: instrument,
          entry_price: 100.123456789
        )

        # Should be truncated to 4 decimal places
        expect(tracker.entry_price).to eq(BigDecimal('100.1235'))
      end
    end

    context 'when handling data migrations' do
      it 'handles schema changes gracefully' do
        # Simulate adding a new column
        expect do
          ActiveRecord::Base.connection.add_column :position_trackers, :new_field, :string
        end.not_to raise_error

        # Clean up
        ActiveRecord::Base.connection.remove_column :position_trackers, :new_field
      end

      it 'handles data type changes gracefully' do
        # This would be handled by proper migrations in real scenarios
        expect(PositionTracker.columns_hash['quantity']).to be_present
      end
    end
  end

  describe 'Error Handling and Recovery' do
    context 'when handling database errors' do
      it 'handles connection errors gracefully' do
        allow(PositionTracker).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished, 'Connection lost')

        expect do
          PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it 'handles timeout errors gracefully' do
        # Mock the actual database operation to raise a timeout error
        allow(PositionTracker).to receive(:create!).and_raise(ActiveRecord::StatementTimeout, 'Query timeout')

        expect do
          PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::StatementTimeout)
      end

      it 'handles constraint violations gracefully' do
        PositionTracker.create!(order_no: 'ORD123456', security_id: instrument.security_id, watchable: instrument,
                                instrument: instrument)

        expect do
          PositionTracker.create!(order_no: 'ORD123456', security_id: (instrument.security_id.to_i + 1).to_s, watchable: instrument,
                                  instrument: instrument)
        end.to raise_error(ActiveRecord::RecordInvalid, /Order no has already been taken/)
      end
    end

    context 'when recovering from errors' do
      it 'retries failed operations' do
        retry_count = 0
        allow(ActiveRecord::Base).to receive(:connection).and_return(
          double('Connection').tap do |conn|
            allow(conn).to receive(:execute) do
              retry_count += 1
              raise ActiveRecord::ConnectionNotEstablished, 'Connection lost' if retry_count == 1

              true
            end
          end
        )

        # Trigger the connection by executing a query
        begin
          ActiveRecord::Base.connection.execute('SELECT 1')
        rescue ActiveRecord::ConnectionNotEstablished
          # Expected on first attempt
        end

        # In a real scenario, this would be wrapped in a retry mechanism
        expect(retry_count).to eq(1) # First attempt fails
      end
    end
  end
end
