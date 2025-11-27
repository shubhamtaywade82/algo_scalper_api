# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commands::ExitPositionCommand do
  let(:tracker) { create(:position_tracker, :active, entry_price: BigDecimal('150.00')) }
  let(:exit_reason) { 'stop_loss_hit' }
  let(:exit_price) { BigDecimal('145.00') }
  let(:metadata) { { triggered_by: 'risk_manager' } }

  let(:command) do
    described_class.new(
      tracker: tracker,
      exit_reason: exit_reason,
      exit_price: exit_price,
      metadata: metadata
    )
  end

  let(:gateway) { instance_double(Orders::Gateway) }

  before do
    allow(Orders).to receive(:config).and_return(gateway)
    allow(gateway).to receive(:exit_market).and_return({ success: true })
    allow(Live::TickCache).to receive(:ltp).and_return(exit_price)
    allow(Core::EventBus.instance).to receive(:publish)
  end

  describe '#initialize' do
    it 'sets command attributes' do
      expect(command.tracker).to eq(tracker)
      expect(command.exit_reason).to eq(exit_reason)
      expect(command.exit_price).to eq(exit_price)
    end
  end

  describe '#execute' do
    it 'calls gateway.exit_market with tracker' do
      expect(gateway).to receive(:exit_market).with(tracker).and_return({ success: true })

      command.execute
    end

    it 'marks tracker as exited' do
      expect(tracker).to receive(:mark_exited!).with(
        exit_price: exit_price,
        exit_reason: exit_reason
      )

      command.execute
    end

    it 'publishes exit_triggered event' do
      expect(Core::EventBus.instance).to receive(:publish).with(
        :exit_triggered,
        hash_including(
          tracker_id: tracker.id,
          order_no: tracker.order_no,
          exit_reason: exit_reason,
          exit_price: exit_price
        )
      )

      command.execute
    end

    it 'returns success result' do
      result = command.execute

      expect(result[:success]).to be true
      expect(result[:data][:tracker_id]).to eq(tracker.id)
      expect(result[:data][:exit_price]).to eq(exit_price)
    end

    context 'when exit fails' do
      before do
        allow(gateway).to receive(:exit_market).and_return({ success: false })
      end

      it 'returns failure result' do
        result = command.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Exit failed')
      end
    end

    context 'when tracker already exited' do
      let(:exited_tracker) { create(:position_tracker, :exited) }
      let(:exited_command) do
        described_class.new(
          tracker: exited_tracker,
          exit_reason: exit_reason
        )
      end

      it 'raises ArgumentError' do
        expect { exited_command.execute }.to raise_error(ArgumentError, /already exited/)
      end
    end

    context 'when tracker is not active' do
      let(:cancelled_tracker) { create(:position_tracker, :cancelled) }
      let(:cancelled_command) do
        described_class.new(
          tracker: cancelled_tracker,
          exit_reason: exit_reason
        )
      end

      it 'raises ArgumentError' do
        expect { cancelled_command.execute }.to raise_error(ArgumentError, /must be active/)
      end
    end

    context 'when exit_price is not provided' do
      let(:command_without_price) do
        described_class.new(
          tracker: tracker,
          exit_reason: exit_reason
        )
      end

      it 'resolves exit price from cache' do
        expect(Live::TickCache).to receive(:ltp).with(
          tracker.segment,
          tracker.security_id
        ).and_return(BigDecimal('140.00'))

        command_without_price.execute

        expect(command_without_price.exit_price).to eq(BigDecimal('140.00'))
      end

      it 'falls back to entry price if cache unavailable' do
        allow(Live::TickCache).to receive(:ltp).and_return(nil)

        command_without_price.execute

        expect(command_without_price.exit_price).to eq(tracker.entry_price)
      end
    end
  end
end
