# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::OrderUpdateHandler do
  let(:handler) { described_class.instance }
  let(:hub) { Live::OrderUpdateHub.instance }
  let(:tracker) do
    create(:position_tracker, :option_position,
           status: 'active',
           segment: 'NSE_FNO',
           security_id: '55111',
           order_no: 'TEST123',
           paper: false) # Live trading tracker
  end
  let(:paper_tracker) do
    create(:position_tracker, :option_position,
           status: 'active',
           segment: 'NSE_FNO',
           security_id: '55112',
           order_no: 'PAPER-123',
           paper: true) # Paper trading tracker
  end

  before do
    # Reset singleton state
    handler.instance_variable_set(:@subscribed, false)

    # Stub OrderUpdateHub
    allow(hub).to receive(:start!)
    allow(hub).to receive(:on_update)
  end

  describe '#initialize' do
    it 'initializes with subscribed false' do
      new_handler = described_class.instance
      expect(new_handler.instance_variable_get(:@subscribed)).to be false
    end

    it 'initializes with mutex' do
      expect(handler.instance_variable_get(:@lock)).to be_a(Mutex)
    end
  end

  describe '#start!' do
    it 'starts OrderUpdateHub' do
      handler.start!

      expect(hub).to have_received(:start!)
    end

    it 'registers callback with OrderUpdateHub' do
      handler.start!

      expect(hub).to have_received(:on_update)
    end

    it 'sets subscribed to true' do
      handler.start!

      expect(handler.instance_variable_get(:@subscribed)).to be true
    end

    it 'does not subscribe again if already subscribed' do
      handler.start!
      handler.start!

      expect(hub).to have_received(:start!).once
      expect(hub).to have_received(:on_update).once
    end

    it 'is thread-safe' do
      threads = []
      3.times do
        threads << Thread.new { handler.start! }
      end
      threads.each(&:join)

      expect(hub).to have_received(:start!).at_most(1).time
    end
  end

  describe '#stop!' do
    before do
      handler.instance_variable_set(:@subscribed, true)
    end

    it 'sets subscribed to false' do
      handler.stop!

      expect(handler.instance_variable_get(:@subscribed)).to be false
    end

    it 'is thread-safe' do
      threads = []
      3.times do
        threads << Thread.new { handler.stop! }
      end
      threads.each(&:join)

      expect(handler.instance_variable_get(:@subscribed)).to be false
    end
  end

  describe '#process_update' do
    it 'calls handle_update' do
      payload = { order_no: tracker.order_no, order_status: 'TRADED' }

      expect(handler).to receive(:handle_update).with(payload)

      handler.process_update(payload)
    end
  end

  describe '#handle_order_update' do
    it 'calls handle_update' do
      payload = { order_no: tracker.order_no, order_status: 'TRADED' }

      expect(handler).to receive(:handle_update).with(payload)

      handler.handle_order_update(payload)
    end
  end

  describe '#find_tracker_by_order_id' do
    it 'finds tracker by order_no' do
      result = handler.find_tracker_by_order_id(tracker.order_no)

      expect(result).to eq(tracker)
    end

    it 'returns nil when tracker not found' do
      result = handler.find_tracker_by_order_id('NONEXISTENT')

      expect(result).to be_nil
    end
  end

  describe '#handle_update' do
    context 'with valid payload' do
      context 'when order is filled (TRADED)' do
        context 'with SELL transaction (exit order)' do
          let(:payload) do
            {
              order_no: tracker.order_no,
              order_status: 'TRADED',
              transaction_type: 'SELL',
              average_traded_price: 105.5,
              filled_quantity: 50
            }
          end

          it 'marks tracker as exited' do
            handler.send(:handle_update, payload)

            tracker.reload
            expect(tracker.status).to eq('exited')
          end

          it 'sets exit_price from average_traded_price' do
            handler.send(:handle_update, payload)

            tracker.reload
            expect(tracker.exit_price).to eq(BigDecimal('105.5'))
          end

          it 'uses tracker lock for atomic update' do
            expect(tracker).to receive(:with_lock).and_call_original

            handler.send(:handle_update, payload)
          end
        end

        context 'with BUY transaction (entry order)' do
          let(:payload) do
            {
              order_no: tracker.order_no,
              order_status: 'TRADED',
              transaction_type: 'BUY',
              average_traded_price: 100.5,
              filled_quantity: 50
            }
          end

          it 'marks tracker as active' do
            tracker.update!(status: 'pending')

            handler.send(:handle_update, payload)

            tracker.reload
            expect(tracker.status).to eq('active')
          end

          it 'sets avg_price and quantity' do
            tracker.update!(status: 'pending', avg_price: nil, quantity: nil)

            handler.send(:handle_update, payload)

            tracker.reload
            expect(tracker.avg_price).to eq(BigDecimal('100.5'))
            expect(tracker.quantity).to eq(50)
          end

          it 'uses tracker lock for atomic update' do
            expect(tracker).to receive(:with_lock).and_call_original

            handler.send(:handle_update, payload)
          end
        end

        context 'with COMPLETE status' do
          let(:payload) do
            {
              order_no: tracker.order_no,
              order_status: 'COMPLETE',
              transaction_type: 'SELL',
              average_traded_price: 105.5
            }
          end

          it 'marks tracker as exited' do
            handler.send(:handle_update, payload)

            tracker.reload
            expect(tracker.status).to eq('exited')
          end
        end
      end

      context 'when order is cancelled' do
        let(:payload) do
          {
            order_no: tracker.order_no,
            order_status: 'CANCELLED'
          }
        end

        it 'marks tracker as cancelled' do
          handler.send(:handle_update, payload)

          tracker.reload
          expect(tracker.status).to eq('cancelled')
        end

        it 'uses tracker lock for atomic update' do
          expect(tracker).to receive(:with_lock).and_call_original

          handler.send(:handle_update, payload)
        end
      end

      context 'when order is rejected' do
        let(:payload) do
          {
            order_no: tracker.order_no,
            order_status: 'REJECTED'
          }
        end

        it 'marks tracker as cancelled' do
          handler.send(:handle_update, payload)

          tracker.reload
          expect(tracker.status).to eq('cancelled')
        end
      end

      context 'with paper trading tracker' do
        let(:payload) do
          {
            order_no: paper_tracker.order_no,
            order_status: 'TRADED',
            transaction_type: 'SELL',
            average_traded_price: 105.5
          }
        end

        it 'skips paper trading trackers' do
          handler.send(:handle_update, payload)

          paper_tracker.reload
          expect(paper_tracker.status).to eq('active') # Unchanged
        end

        it 'does not call mark_exited!' do
          expect(paper_tracker).not_to receive(:mark_exited!)

          handler.send(:handle_update, payload)
        end
      end
    end

    context 'with invalid payload' do
      it 'returns early if order_no is blank' do
        payload = { order_status: 'TRADED' }

        expect(tracker).not_to receive(:mark_exited!)

        handler.send(:handle_update, payload)
      end

      it 'returns early if order_no is nil' do
        payload = { order_no: nil, order_status: 'TRADED' }

        expect(tracker).not_to receive(:mark_exited!)

        handler.send(:handle_update, payload)
      end

      it 'returns early if tracker not found' do
        payload = { order_no: 'NONEXISTENT', order_status: 'TRADED' }

        expect(PositionTracker).not_to receive(:find_by)

        handler.send(:handle_update, payload)
      end
    end

    context 'with alternative payload keys' do
      it 'handles order_id instead of order_no' do
        payload = {
          order_id: tracker.order_no,
          status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }

        handler.send(:handle_update, payload)

        tracker.reload
        expect(tracker.status).to eq('exited')
      end

      it 'handles status instead of order_status' do
        payload = {
          order_no: tracker.order_no,
          status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }

        handler.send(:handle_update, payload)

        tracker.reload
        expect(tracker.status).to eq('exited')
      end

      it 'handles average_price instead of average_traded_price' do
        payload = {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }

        handler.send(:handle_update, payload)

        tracker.reload
        expect(tracker.exit_price).to eq(BigDecimal('105.5'))
      end

      it 'handles side instead of transaction_type' do
        payload = {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          side: 'SELL',
          average_price: 105.5
        }

        handler.send(:handle_update, payload)

        tracker.reload
        expect(tracker.status).to eq('exited')
      end

      it 'handles transaction_side instead of transaction_type' do
        payload = {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          transaction_side: 'SELL',
          average_price: 105.5
        }

        handler.send(:handle_update, payload)

        tracker.reload
        expect(tracker.status).to eq('exited')
      end
    end

    context 'with errors' do
      it 'handles mark_exited! errors gracefully' do
        payload = {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }

        allow(tracker).to receive(:mark_exited!).and_raise(ActiveRecord::RecordInvalid.new(tracker))

        expect { handler.send(:handle_update, payload) }.not_to raise_error
      end

      it 'logs errors' do
        payload = {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }

        allow(tracker).to receive(:mark_exited!).and_raise(StandardError.new('DB error'))

        expect(Rails.logger).to receive(:error).with(/OrderUpdateHandler.*Failed to process order update/)

        handler.send(:handle_update, payload)
      end
    end

    context 'with race conditions' do
      let(:payload) do
        {
          order_no: tracker.order_no,
          order_status: 'TRADED',
          transaction_type: 'SELL',
          average_price: 105.5
        }
      end

      it 'uses tracker lock to prevent race conditions' do
        expect(tracker).to receive(:with_lock).and_call_original

        handler.send(:handle_update, payload)
      end

      it 'handles already exited tracker gracefully' do
        tracker.update!(status: 'exited')

        expect { handler.send(:handle_update, payload) }.not_to raise_error
      end
    end
  end

  describe '#safe_decimal' do
    it 'converts numeric string to BigDecimal' do
      result = handler.send(:safe_decimal, '100.5')

      expect(result).to eq(BigDecimal('100.5'))
    end

    it 'converts number to BigDecimal' do
      result = handler.send(:safe_decimal, 100.5)

      expect(result).to eq(BigDecimal('100.5'))
    end

    it 'returns nil for nil input' do
      result = handler.send(:safe_decimal, nil)

      expect(result).to be_nil
    end

    it 'returns nil for invalid input' do
      result = handler.send(:safe_decimal, 'invalid')

      expect(result).to be_nil
    end

    it 'handles ArgumentError gracefully' do
      result = handler.send(:safe_decimal, 'not a number')

      expect(result).to be_nil
    end
  end
end
