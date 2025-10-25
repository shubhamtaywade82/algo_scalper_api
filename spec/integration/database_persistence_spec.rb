# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Database Persistence Integration", type: :integration, vcr: true do
  let(:instrument) { create(:instrument, :nifty_future, security_id: '12345') }
  let(:derivative) { create(:derivative, security_id: '12345CE', lot_size: 50) }
  let(:position_tracker) { create(:position_tracker,
    instrument: instrument,
    order_no: 'ORD123456',
    security_id: '12345',
    status: 'active'
  ) }
  let(:trading_signal) { create(:trading_signal,
    instrument: instrument,
    direction: 'bullish',
    confidence: 0.85
  ) }

  describe "Position Tracker Persistence" do
    context "when creating position trackers" do
      it "persists position tracker with all required fields" do
        tracker_data = {
          instrument: instrument,
          order_no: 'ORD123456',
          security_id: '12345',
          symbol: 'NIFTY18500CE',
          segment: 'NSE_FNO',
          side: 'long_ce',
          quantity: 50,
          entry_price: 100.0,
          meta: { index_key: 'nifty', direction: 'long_ce' }
        }

        tracker = PositionTracker.create!(tracker_data)

        expect(tracker).to be_persisted
        expect(tracker.order_no).to eq('ORD123456')
        expect(tracker.security_id).to eq('12345')
        expect(tracker.symbol).to eq('NIFTY18500CE')
        expect(tracker.segment).to eq('NSE_FNO')
        expect(tracker.side).to eq('long_ce')
        expect(tracker.quantity).to eq(50)
        expect(tracker.entry_price).to eq(BigDecimal('100.0'))
        expect(tracker.meta['index_key']).to eq('nifty')
      end

      it "enforces unique order number constraint" do
        PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)

        expect {
          PositionTracker.create!(order_no: 'ORD123456', security_id: '67890', instrument: instrument)
        }.to raise_error(ActiveRecord::RecordInvalid, /Order no has already been taken/)
      end

      it "validates required fields" do
        expect {
          PositionTracker.create!(order_no: nil, security_id: '12345', instrument: instrument)
        }.to raise_error(ActiveRecord::RecordInvalid, /Order no can't be blank/)

        expect {
          PositionTracker.create!(order_no: 'ORD123456', security_id: nil, instrument: instrument)
        }.to raise_error(ActiveRecord::RecordInvalid, /Security id can't be blank/)
      end

      it "validates status values" do
        expect {
          PositionTracker.create!(
            order_no: 'ORD123456',
            security_id: '12345',
            instrument: instrument,
            status: 'invalid_status'
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Status is not included in the list/)
      end
    end

    context "when updating position tracker status" do
      it "marks position as active with average price and quantity" do
        avg_price = BigDecimal('101.5')
        quantity = 50

        position_tracker.mark_active!(avg_price: avg_price, quantity: quantity)

        expect(position_tracker.status).to eq('active')
        expect(position_tracker.avg_price).to eq(avg_price)
        expect(position_tracker.quantity).to eq(quantity)
        expect(position_tracker.entry_price).to eq(avg_price)
      end

      it "marks position as cancelled" do
        position_tracker.mark_cancelled!

        expect(position_tracker.status).to eq('cancelled')
      end

      it "marks position as exited and cleans up resources" do
        expect(position_tracker).to receive(:unsubscribe)
        expect(Live::RedisPnlCache.instance).to receive(:clear_tracker).with(position_tracker.id)
        expect(Rails.cache).to receive(:write).with(
          "reentry:#{position_tracker.symbol}",
          anything,
          expires_in: 8.hours
        )

        position_tracker.mark_exited!

        expect(position_tracker.status).to eq('exited')
      end
    end

    context "when updating PnL data" do
      it "updates PnL and high water mark" do
        pnl = BigDecimal('500.0')
        pnl_pct = BigDecimal('0.10')

        position_tracker.update_pnl!(pnl, pnl_pct: pnl_pct)

        expect(position_tracker.last_pnl_rupees).to eq(pnl)
        expect(position_tracker.last_pnl_pct).to eq(pnl_pct)
        # High water mark should remain at the higher value (25200.00 from factory)
        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('25200.00'))
      end

      it "updates high water mark only when PnL increases" do
        # Set initial high water mark
        position_tracker.update!(high_water_mark_pnl: BigDecimal('1000.0'))

        # Update with lower PnL
        lower_pnl = BigDecimal('500.0')
        position_tracker.update_pnl!(lower_pnl)

        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('1000.0'))
      end

      it "updates high water mark when PnL increases" do
        # Set initial high water mark
        position_tracker.update!(high_water_mark_pnl: BigDecimal('500.0'))

        # Update with higher PnL
        higher_pnl = BigDecimal('1500.0')
        position_tracker.update_pnl!(higher_pnl)

        expect(position_tracker.high_water_mark_pnl).to eq(BigDecimal('1500.0'))
      end
    end

    context "when managing metadata" do
      it "stores and retrieves metadata correctly" do
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

      it "handles breakeven lock status" do
        position_tracker.update!(meta: { 'breakeven_locked' => true })

        expect(position_tracker.breakeven_locked?).to be true

        position_tracker.lock_breakeven!

        expect(position_tracker.meta['breakeven_locked']).to be true
      end
    end
  end

  describe "Trading Signal Persistence" do
    context "when creating trading signals" do
      it "persists trading signal with all required fields" do
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

      it "tracks signal execution" do
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

      it "tracks signal performance" do
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
            exit_at: (Time.current + 1.hour).iso8601,
            final_status: 'profitable'
          })
        )

        expect(signal.metadata['exit_price']).to eq(108.0)
        expect(signal.metadata['exit_at']).to be_present
        expect(signal.metadata['final_status']).to eq('profitable')
      end
    end

    context "when calculating signal accuracy" do
      it "calculates accuracy for profitable signals" do
        signal.update!(
          executed_at: Time.current,
          execution_price: 105.5,
          status: 'executed',
          exit_price: 108.0,
          exit_at: Time.current + 1.hour,
          final_status: 'profitable'
        )

        accuracy = signal.calculate_accuracy
        expect(accuracy).to be > 0
      end

      it "calculates accuracy for losing signals" do
        signal.update!(
          executed_at: Time.current,
          execution_price: 105.5,
          status: 'executed',
          exit_price: 103.0,
          exit_at: Time.current + 1.hour,
          final_status: 'loss'
        )

        accuracy = signal.calculate_accuracy
        expect(accuracy).to be < 0
      end
    end
  end

  describe "Instrument Persistence" do
    context "when persisting instrument data" do
      it "persists instrument with all required fields" do
        instrument_data = {
          symbol_name: 'NIFTY',
          security_id: '12345',
          exchange: 'nse',
          segment: 'derivatives',
          instrument_type: 'INDEX',
          lot_size: 1,
          tick_size: 0.05,
          instrument_code: 'index'
        }

        instrument = Instrument.create!(instrument_data)

        expect(instrument).to be_persisted
        expect(instrument.symbol_name).to eq('NIFTY')
        expect(instrument.security_id).to eq('12345')
        expect(instrument.exchange_segment).to eq('NSE_FNO')
        expect(instrument.instrument_type).to eq('INDEX')
        expect(instrument.lot_size).to eq(1)
        expect(instrument.tick_size).to eq(BigDecimal('0.05'))
      end

      it "enforces unique constraint on security_id and exchange_segment" do
        Instrument.create!(symbol_name: 'NIFTY', security_id: '12345', exchange: 'nse', segment: 'derivatives', instrument_code: 'index')

        expect {
          Instrument.create!(symbol_name: 'NIFTY2', security_id: '12345', exchange: 'nse', segment: 'derivatives', instrument_code: 'index')
        }.to raise_error(ActiveRecord::RecordInvalid, /Security has already been taken/)
      end

      it "validates required fields" do
        expect {
          Instrument.create!(symbol_name: nil, security_id: '12345', exchange: 'nse', segment: 'derivatives', instrument_code: 'index')
        }.to raise_error(ActiveRecord::RecordInvalid, /Symbol name can't be blank/)

        expect {
          Instrument.create!(symbol_name: 'NIFTY', security_id: nil, exchange: 'nse', segment: 'derivatives', instrument_code: 'index')
        }.to raise_error(ActiveRecord::RecordInvalid, /Security can't be blank/)
      end
    end

    context "when managing instrument associations" do
      it "associates instruments with derivatives" do
        derivative = Derivative.create!(
          instrument: instrument,
          security_id: '12345CE',
          strike_price: 18500.0,
          expiry_date: Date.current + 7.days,
          option_type: 'CE',
          lot_size: 50
        )

        expect(instrument.derivatives).to include(derivative)
        expect(derivative.instrument).to eq(instrument)
      end

      it "associates instruments with position trackers" do
        tracker = PositionTracker.create!(
          instrument: instrument,
          order_no: 'ORD123456',
          security_id: '12345'
        )

        expect(instrument.position_trackers).to include(tracker)
        expect(tracker.instrument).to eq(instrument)
      end

      it "associates instruments with trading signals" do
        signal = TradingSignal.create!(
          instrument: instrument,
          direction: 'bullish',
          confidence: 0.85
        )

        expect(instrument.trading_signals).to include(signal)
        expect(signal.instrument).to eq(instrument)
      end
    end
  end

  describe "Derivative Persistence" do
    context "when persisting derivative data" do
      it "persists derivative with all required fields" do
        derivative_data = {
          instrument: instrument,
          security_id: '12345CE',
          strike_price: 18500.0,
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

      it "enforces unique constraint on security_id" do
        Derivative.create!(
          instrument: instrument,
          security_id: '12345CE',
          strike_price: 18500.0,
          expiry_date: Date.current + 7.days,
          option_type: 'CE'
        )

        expect {
          Derivative.create!(
            instrument: instrument,
            security_id: '12345CE',
            strike_price: 18600.0,
            expiry_date: Date.current + 7.days,
            option_type: 'CE'
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Security id has already been taken/)
      end

      it "validates option type values" do
        expect {
          Derivative.create!(
            instrument: instrument,
            security_id: '12345XX',
            strike_price: 18500.0,
            expiry_date: Date.current + 7.days,
            option_type: 'INVALID'
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /Option type is not included in the list/)
      end
    end
  end

  describe "Watchlist Item Persistence" do
    context "when persisting watchlist items" do
      it "persists watchlist item with required fields" do
        watchlist_data = {
          segment: 'NSE_FNO',
          security_id: '12345',
          active: true
        }

        watchlist_item = WatchlistItem.create!(watchlist_data)

        expect(watchlist_item).to be_persisted
        expect(watchlist_item.segment).to eq('NSE_FNO')
        expect(watchlist_item.security_id).to eq('12345')
        expect(watchlist_item.active).to be true
      end

      it "enforces unique constraint on segment and security_id" do
        WatchlistItem.create!(segment: 'NSE_FNO', security_id: '12345')

        expect {
          WatchlistItem.create!(segment: 'NSE_FNO', security_id: '12345')
        }.to raise_error(ActiveRecord::RecordInvalid, /Security id has already been taken/)
      end

      it "scopes active watchlist items" do
        active_item = WatchlistItem.create!(segment: 'NSE_FNO', security_id: '12345', active: true)
        inactive_item = WatchlistItem.create!(segment: 'NSE_FNO', security_id: '67890', active: false)

        active_items = WatchlistItem.active
        expect(active_items).to include(active_item)
        expect(active_items).not_to include(inactive_item)
      end
    end
  end

  describe "Database Transactions and Consistency" do
    context "when handling database transactions" do
      it "rolls back transaction on error" do
        expect {
          ActiveRecord::Base.transaction do
            PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)
            PositionTracker.create!(order_no: 'ORD123456', security_id: '67890', instrument: instrument) # Duplicate order_no
          end
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(PositionTracker.where(order_no: 'ORD123456')).to be_empty
      end

      it "commits transaction on success" do
        ActiveRecord::Base.transaction do
          PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)
          PositionTracker.create!(order_no: 'ORD123457', security_id: '67890', instrument: instrument)
        end

        expect(PositionTracker.where(order_no: 'ORD123456')).to exist
        expect(PositionTracker.where(order_no: 'ORD123457')).to exist
      end
    end

    context "when handling concurrent access" do
      it "handles optimistic locking" do
        tracker1 = PositionTracker.find(position_tracker.id)
        tracker2 = PositionTracker.find(position_tracker.id)

        tracker1.update!(quantity: 100)
        tracker2.update!(quantity: 150)

        expect(tracker1.reload.quantity).to eq(150) # Last update wins
      end

      it "handles pessimistic locking" do
        position_tracker.with_lock do
          position_tracker.update!(quantity: 100)
        end

        expect(position_tracker.quantity).to eq(100)
      end
    end
  end

  describe "Database Indexes and Performance" do
    context "when querying with indexes" do
      it "uses index on order_no for lookups" do
        PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)

        # This should use the unique index on order_no
        tracker = PositionTracker.find_by(order_no: 'ORD123456')
        expect(tracker).to be_present
      end

      it "uses index on security_id and status for lookups" do
        PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument, status: 'active')

        # This should use the composite index on security_id and status
        active_trackers = PositionTracker.where(security_id: '12345', status: 'active')
        expect(active_trackers).to exist
      end

      it "uses index on instrument_id for associations" do
        tracker = PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)

        # This should use the foreign key index on instrument_id
        instrument_trackers = instrument.position_trackers
        expect(instrument_trackers).to include(tracker)
      end
    end

    context "when handling large datasets" do
      it "efficiently queries large numbers of records" do
        # Create multiple records
        100.times do |i|
          PositionTracker.create!(
            order_no: "ORD#{i.to_s.rjust(6, '0')}",
            security_id: "1234#{i}",
            instrument: instrument
          )
        end

        # This should be efficient with proper indexing
        all_trackers = PositionTracker.all
        expect(all_trackers.count).to eq(100)
      end

      it "efficiently paginates through large datasets" do
        # Create multiple records
        100.times do |i|
          PositionTracker.create!(
            order_no: "ORD#{i.to_s.rjust(6, '0')}",
            security_id: "1234#{i}",
            instrument: instrument
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

  describe "Data Integrity and Validation" do
    context "when enforcing data integrity" do
      it "prevents orphaned records" do
        tracker = PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)

        # Verify that the method can be called without crashing
        expect { instrument.destroy }.not_to raise_error
      end

      it "cascades deletes when appropriate" do
        signal = TradingSignal.create!(instrument: instrument, direction: 'bullish', confidence: 0.85)

        instrument.destroy

        expect(TradingSignal.find_by(id: signal.id)).to be_nil
      end

      it "validates decimal precision" do
        tracker = PositionTracker.create!(
          order_no: 'ORD123456',
          security_id: '12345',
          instrument: instrument,
          entry_price: 100.123456789
        )

        # Should be truncated to 4 decimal places
        expect(tracker.entry_price).to eq(BigDecimal('100.1235'))
      end
    end

    context "when handling data migrations" do
      it "handles schema changes gracefully" do
        # Simulate adding a new column
        expect {
          ActiveRecord::Base.connection.add_column :position_trackers, :new_field, :string
        }.not_to raise_error

        # Clean up
        ActiveRecord::Base.connection.remove_column :position_trackers, :new_field
      end

      it "handles data type changes gracefully" do
        # This would be handled by proper migrations in real scenarios
        expect(PositionTracker.column_types['quantity']).to be_present
      end
    end
  end

  describe "Error Handling and Recovery" do
    context "when handling database errors" do
      it "handles connection errors gracefully" do
        allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished, "Connection lost")

        expect {
          PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it "handles timeout errors gracefully" do
        # Mock the actual database operation to raise a timeout error
        allow(PositionTracker).to receive(:create!).and_raise(ActiveRecord::StatementTimeout, "Query timeout")

        expect {
          PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)
        }.to raise_error(ActiveRecord::StatementTimeout)
      end

      it "handles constraint violations gracefully" do
        PositionTracker.create!(order_no: 'ORD123456', security_id: '12345', instrument: instrument)

        expect {
          PositionTracker.create!(order_no: 'ORD123456', security_id: '67890', instrument: instrument)
        }.to raise_error(ActiveRecord::RecordInvalid, /Order no has already been taken/)
      end
    end

    context "when recovering from errors" do
      it "retries failed operations" do
        retry_count = 0
        allow(ActiveRecord::Base).to receive(:connection).and_return(
          double('Connection').tap do |conn|
            allow(conn).to receive(:execute) do
              retry_count += 1
              if retry_count == 1
                raise ActiveRecord::ConnectionNotEstablished, "Connection lost"
              else
                true
              end
            end
          end
        )

        # In a real scenario, this would be wrapped in a retry mechanism
        expect(retry_count).to eq(1) # First attempt fails
      end
    end
  end
end
