# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::AdminActions do
  let(:instrument) { create(:instrument, :nifty_index, security_id: '13') }
  let(:derivative) { create(:derivative, :nifty_call_option, instrument: instrument, security_id: '60001') }
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', capital_alloc_pct: 0.30 } }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ indices: [index_cfg] })
  end

  describe '.buy_derivative!' do
    before do
      allow(derivative).to receive(:buy_option!).and_return(double('Order', order_id: 'ORD123'))
    end

    it 'finds derivative and calls buy_option! with resolved index config' do
      allow(Derivative).to receive(:find).with(42).and_return(derivative)

      expect(derivative).to receive(:buy_option!).with(
        qty: 50,
        product_type: 'INTRADAY',
        index_cfg: index_cfg,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 42, qty: 50)
    end

    it 'prefers override index_key when provided' do
      banknifty_cfg = { key: 'BANKNIFTY', segment: 'IDX_I', capital_alloc_pct: 0.30 }
      allow(AlgoConfig).to receive(:fetch).and_return({ indices: [index_cfg, banknifty_cfg] })
      allow(Derivative).to receive(:find).with(99).and_return(derivative)

      expect(derivative).to receive(:buy_option!).with(
        qty: nil,
        product_type: 'INTRADAY',
        index_cfg: banknifty_cfg,
        meta: { foo: 'bar' }
      )

      described_class.buy_derivative!(
        derivative_id: 99,
        index_key: 'BANKNIFTY',
        meta: { foo: 'bar' }
      )
    end

    it 'uses underlying_symbol to find index config when no override' do
      allow(Derivative).to receive(:find).with(123).and_return(derivative)
      allow(derivative).to receive(:underlying_symbol).and_return('NIFTY')

      expect(derivative).to receive(:buy_option!).with(
        qty: nil,
        product_type: 'INTRADAY',
        index_cfg: index_cfg,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 123)
    end

    it 'falls back to symbol_name when underlying_symbol is missing' do
      alt_derivative = create(:derivative, :banknifty_call_option, instrument: instrument, security_id: '60002')
      banknifty_cfg = { key: 'BANKNIFTY', segment: 'IDX_I' }
      allow(AlgoConfig).to receive(:fetch).and_return({ indices: [banknifty_cfg] })
      allow(Derivative).to receive(:find).with(456).and_return(alt_derivative)
      allow(alt_derivative).to receive(:underlying_symbol).and_return(nil)
      allow(alt_derivative).to receive(:symbol_name).and_return('BANKNIFTY')

      expect(alt_derivative).to receive(:buy_option!).with(
        qty: nil,
        product_type: 'INTRADAY',
        index_cfg: banknifty_cfg,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 456)
    end

    it 'passes nil index_cfg when lookup fails' do
      allow(AlgoConfig).to receive(:fetch).and_return({ indices: [] })
      allow(Derivative).to receive(:find).with(789).and_return(derivative)

      expect(derivative).to receive(:buy_option!).with(
        qty: nil,
        product_type: 'INTRADAY',
        index_cfg: nil,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 789)
    end

    it 'handles errors gracefully when config lookup fails' do
      allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, 'Config error')
      allow(Rails.logger).to receive(:error)
      allow(Derivative).to receive(:find).with(999).and_return(derivative)

      expect(derivative).to receive(:buy_option!).with(
        qty: 10,
        product_type: 'INTRADAY',
        index_cfg: nil,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 999, qty: 10)
      expect(Rails.logger).to have_received(:error)
    end

    it 'passes custom product_type' do
      allow(Derivative).to receive(:find).with(111).and_return(derivative)

      expect(derivative).to receive(:buy_option!).with(
        qty: 25,
        product_type: 'CNC',
        index_cfg: index_cfg,
        meta: {}
      )

      described_class.buy_derivative!(derivative_id: 111, qty: 25, product_type: 'CNC')
    end
  end

  describe '.sell_derivative!' do
    it 'finds derivative and calls sell_option!' do
      allow(Derivative).to receive(:find).with(42).and_return(derivative)

      expect(derivative).to receive(:sell_option!).with(qty: 50, meta: {})

      described_class.sell_derivative!(derivative_id: 42, qty: 50)
    end

    it 'passes meta hash when provided' do
      allow(Derivative).to receive(:find).with(99).and_return(derivative)

      expect(derivative).to receive(:sell_option!).with(qty: nil, meta: { note: 'exit' })

      described_class.sell_derivative!(derivative_id: 99, meta: { note: 'exit' })
    end

    it 'handles missing derivative gracefully' do
      allow(Derivative).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)

      expect do
        described_class.sell_derivative!(derivative_id: 999)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end

