# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Builders::BracketOrderBuilder do
  let(:tracker) { create(:position_tracker, :active, entry_price: BigDecimal('150.00')) }
  let(:builder) { described_class.new(tracker) }

  before do
    allow(Orders::BracketPlacer).to receive(:place_bracket).and_return(
      { success: true, sl_price: 100.0, tp_price: 200.0 }
    )
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { sl_pct: 0.30, tp_pct: 0.60 }
    })
  end

  describe '#initialize' do
    it 'sets tracker' do
      expect(builder.instance_variable_get(:@tracker)).to eq(tracker)
    end

    it 'initializes with nil prices' do
      expect(builder.instance_variable_get(:@sl_price)).to be_nil
      expect(builder.instance_variable_get(:@tp_price)).to be_nil
    end
  end

  describe '#with_stop_loss' do
    it 'sets stop loss price' do
      result = builder.with_stop_loss(100.0)

      expect(result).to eq(builder) # Fluent interface
      expect(builder.instance_variable_get(:@sl_price)).to eq(BigDecimal('100.0'))
    end

    it 'converts to BigDecimal' do
      builder.with_stop_loss(100.5)

      expect(builder.instance_variable_get(:@sl_price)).to be_a(BigDecimal)
    end
  end

  describe '#with_take_profit' do
    it 'sets take profit price' do
      result = builder.with_take_profit(200.0)

      expect(result).to eq(builder)
      expect(builder.instance_variable_get(:@tp_price)).to eq(BigDecimal('200.0'))
    end
  end

  describe '#with_stop_loss_percentage' do
    it 'calculates SL as percentage below entry' do
      builder.with_stop_loss_percentage(0.30)

      expected_sl = tracker.entry_price.to_f * 0.70
      expect(builder.instance_variable_get(:@sl_price).to_f).to be_within(0.01).of(expected_sl)
    end

    it 'raises error if tracker has no entry price' do
      tracker_without_price = create(:position_tracker, entry_price: nil)

      expect do
        described_class.new(tracker_without_price).with_stop_loss_percentage(0.30)
      end.to raise_error(ArgumentError, /entry price/)
    end
  end

  describe '#with_take_profit_percentage' do
    it 'calculates TP as percentage above entry' do
      builder.with_take_profit_percentage(0.60)

      expected_tp = tracker.entry_price.to_f * 1.60
      expect(builder.instance_variable_get(:@tp_price).to_f).to be_within(0.01).of(expected_tp)
    end
  end

  describe '#with_trailing' do
    it 'sets trailing configuration' do
      config = { enabled: true, activation_pct: 0.20, trail_pct: 0.10 }
      result = builder.with_trailing(config)

      expect(result).to eq(builder)
      expect(builder.instance_variable_get(:@trailing_config)).to include(
        enabled: true,
        activation_pct: 0.20,
        trail_pct: 0.10
      )
    end

    it 'uses defaults for missing values' do
      builder.with_trailing({})

      config = builder.instance_variable_get(:@trailing_config)
      expect(config[:enabled]).to be false
      expect(config[:activation_pct]).to eq(0.20)
      expect(config[:trail_pct]).to eq(0.10)
    end
  end

  describe '#with_reason' do
    it 'sets reason' do
      result = builder.with_reason('initial_bracket')

      expect(result).to eq(builder)
      expect(builder.instance_variable_get(:@reason)).to eq('initial_bracket')
    end
  end

  describe '#without_validation' do
    it 'disables validation' do
      result = builder.without_validation

      expect(result).to eq(builder)
      expect(builder.instance_variable_get(:@validate)).to be false
    end
  end

  describe '#build' do
    context 'when prices are set' do
      before do
        builder.with_stop_loss(100.0).with_take_profit(200.0).with_reason('test')
      end

      it 'calls BracketPlacer.place_bracket with correct parameters' do
        expect(Orders::BracketPlacer).to receive(:place_bracket).with(
          tracker: tracker,
          sl_price: 100.0,
          tp_price: 200.0,
          reason: 'test'
        )

        builder.build
      end

      it 'returns result from BracketPlacer' do
        result = builder.build

        expect(result[:success]).to be true
        expect(result[:sl_price]).to eq(100.0)
        expect(result[:tp_price]).to eq(200.0)
      end
    end

    context 'when prices are not set' do
      it 'calculates default prices from config' do
        builder.with_reason('default_bracket')

        expected_sl = (tracker.entry_price.to_f * 0.70).round(2)
        expected_tp = (tracker.entry_price.to_f * 1.60).round(2)

        expect(Orders::BracketPlacer).to receive(:place_bracket).with(
          tracker: tracker,
          sl_price: expected_sl,
          tp_price: expected_tp,
          reason: 'default_bracket'
        )

        builder.build
      end
    end

    context 'when validation fails' do
      it 'raises error for invalid SL (above entry)' do
        builder.with_stop_loss(200.0).with_take_profit(300.0)

        expect { builder.build }.to raise_error(ArgumentError, /below entry/)
      end

      it 'raises error for invalid TP (below entry)' do
        builder.with_stop_loss(100.0).with_take_profit(100.0)

        expect { builder.build }.to raise_error(ArgumentError, /above entry/)
      end

      it 'raises error if tracker not active' do
        cancelled_tracker = create(:position_tracker, :cancelled)
        invalid_builder = described_class.new(cancelled_tracker)

        expect { invalid_builder.build }.to raise_error(ArgumentError, /must be active/)
      end

      it 'skips validation when disabled' do
        cancelled_tracker = create(:position_tracker, :cancelled)
        invalid_builder = described_class.new(cancelled_tracker).without_validation

        expect { invalid_builder.build }.not_to raise_error
      end
    end

    context 'when BracketPlacer fails' do
      before do
        allow(Orders::BracketPlacer).to receive(:place_bracket).and_raise(StandardError, 'Placement failed')
      end

      it 'handles exception gracefully' do
        builder.with_stop_loss(100.0).with_take_profit(200.0)

        result = builder.build

        expect(result[:success]).to be false
        expect(result[:error]).to include('Placement failed')
      end
    end
  end

  describe '#build_config' do
    before do
      builder.with_stop_loss(100.0)
        .with_take_profit(200.0)
        .with_trailing(enabled: true, activation_pct: 0.20)
        .with_reason('test_reason')
    end

    it 'returns configuration hash without placing order' do
      config = builder.build_config

      expect(config).to include(
        tracker: tracker,
        sl_price: 100.0,
        tp_price: 200.0,
        reason: 'test_reason'
      )
      expect(config[:trailing_config]).to include(enabled: true)
    end

    it 'does not call BracketPlacer' do
      expect(Orders::BracketPlacer).not_to receive(:place_bracket)

      builder.build_config
    end

    it 'calculates defaults if prices not set' do
      new_builder = described_class.new(tracker)
      config = new_builder.build_config

      expected_sl = (tracker.entry_price.to_f * 0.70).round(2)
      expected_tp = (tracker.entry_price.to_f * 1.60).round(2)

      expect(config[:sl_price]).to eq(expected_sl)
      expect(config[:tp_price]).to eq(expected_tp)
    end
  end

  describe 'fluent interface' do
    it 'allows method chaining' do
      result = builder
        .with_stop_loss_percentage(0.30)
        .with_take_profit_percentage(0.60)
        .with_trailing(enabled: true)
        .with_reason('chained_bracket')
        .build

      expect(result[:success]).to be true
    end
  end
end
