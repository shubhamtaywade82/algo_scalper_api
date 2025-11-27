# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commands::PlaceMarketOrderCommand do
  let(:side) { 'BUY' }
  let(:segment) { 'NSE_FNO' }
  let(:security_id) { '12345' }
  let(:qty) { 50 }
  let(:client_order_id) { 'TEST-123' }
  let(:metadata) { { index_key: 'NIFTY' } }

  let(:command) do
    described_class.new(
      side: side,
      segment: segment,
      security_id: security_id,
      qty: qty,
      client_order_id: client_order_id,
      metadata: metadata
    )
  end

  before do
    allow(Orders::Placer).to receive(:buy_market!).and_return(
      double(order_id: 'ORD123456', status: 'success')
    )
    allow(Orders::Placer).to receive(:sell_market!).and_return(
      double(order_id: 'ORD123456', status: 'success')
    )
  end

  describe '#initialize' do
    it 'sets command attributes' do
      expect(command.side).to eq('BUY')
      expect(command.segment).to eq(segment)
      expect(command.security_id).to eq(security_id)
      expect(command.qty).to eq(qty)
      expect(command.client_order_id).to eq(client_order_id)
    end

    it 'generates client_order_id if not provided' do
      command_without_id = described_class.new(
        side: side,
        segment: segment,
        security_id: security_id,
        qty: qty
      )

      expect(command_without_id.client_order_id).to be_present
      expect(command_without_id.client_order_id).to start_with('CMD-')
    end
  end

  describe '#execute' do
    context 'when placing buy order' do
      it 'calls Orders::Placer.buy_market! with correct parameters' do
        expect(Orders::Placer).to receive(:buy_market!).with(
          seg: segment,
          sid: security_id,
          qty: qty,
          client_order_id: client_order_id,
          product_type: 'INTRADAY'
        ).and_return(double(order_id: 'ORD123456'))

        command.execute
      end

      it 'returns success result with order data' do
        result = command.execute

        expect(result[:success]).to be true
        expect(result[:data][:order_id]).to eq('ORD123456')
      end

      it 'stores order response' do
        command.execute

        expect(command.order_response).to be_present
        expect(command.order_id).to eq('ORD123456')
      end
    end

    context 'when placing sell order' do
      let(:sell_command) do
        described_class.new(
          side: 'SELL',
          segment: segment,
          security_id: security_id,
          qty: qty
        )
      end

      it 'calls Orders::Placer.sell_market! with correct parameters' do
        expect(Orders::Placer).to receive(:sell_market!).with(
          seg: segment,
          sid: security_id,
          qty: qty,
          client_order_id: anything
        ).and_return(double(order_id: 'ORD789012'))

        sell_command.execute
      end
    end

    context 'when order placement fails' do
      before do
        allow(Orders::Placer).to receive(:buy_market!).and_return(nil)
      end

      it 'returns failure result' do
        result = command.execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Order placement returned nil')
      end
    end

    context 'when invalid side provided' do
      let(:invalid_command) do
        described_class.new(
          side: 'INVALID',
          segment: segment,
          security_id: security_id,
          qty: qty
        )
      end

      it 'returns failure result' do
        result = invalid_command.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid side')
      end
    end

    context 'when validation fails' do
      let(:invalid_command) do
        described_class.new(
          side: side,
          segment: 'INVALID_SEGMENT',
          security_id: security_id,
          qty: qty
        )
      end

      it 'raises ArgumentError' do
        expect { invalid_command.execute }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#undo' do
    before do
      command.execute
    end

    it 'returns failure for non-implemented undo' do
      result = command.undo

      expect(result[:success]).to be false
      expect(result[:error]).to include('not implemented')
    end

    it 'is marked as undoable' do
      expect(command.undoable?).to be true
    end
  end

  describe '#order_id' do
    it 'extracts order_id after execution' do
      command.execute

      expect(command.instance_variable_get(:@order_id)).to eq('ORD123456')
    end

    it 'returns nil before execution' do
      expect(command.instance_variable_get(:@order_id)).to be_nil
    end
  end
end
