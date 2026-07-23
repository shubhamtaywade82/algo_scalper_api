# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Indicators::Cpr do
  describe '#call' do
    context 'with standard daily OHLC data' do
      subject(:result) do
        described_class.call(high: 22_150.00, low: 22_000.00, close: 22_100.00)
      end

      it 'calculates pivot correctly' do
        expected_pivot = (22_150 + 22_000 + 22_100) / 3.0
        expect(result[:pivot]).to eq(expected_pivot.round(2))
      end

      it 'calculates TC and BC' do
        expect(result[:top_central]).to be > result[:bottom_central]
      end

      it 'calculates positive width' do
        expect(result[:width]).to be_positive
      end

      it 'calculates width percentage' do
        expect(result[:width_pct]).to be_a(Float).and(be_positive)
      end

      it 'returns a valid width_type' do
        expect(result[:width_type]).to be_in(%i[narrow normal wide])
      end
    end

    context 'with narrow range (trend day setup)' do
      subject(:result) do
        described_class.call(high: 22_050.00, low: 22_000.00, close: 22_030.00)
      end

      it 'detects narrow CPR' do
        expect(result[:width_type]).to eq(:narrow)
      end
    end

    context 'with wide range (choppy day setup)' do
      subject(:result) do
        described_class.call(high: 22_500.00, low: 21_500.00, close: 22_400.00)
      end

      it 'detects wide CPR' do
        expect(result[:width_type]).to eq(:wide)
      end

      it 'returns positive width' do
        expect(result[:width]).to be_positive
      end
    end

    context 'when high equals low' do
      subject(:result) do
        described_class.call(high: 22_000, low: 22_000, close: 22_000)
      end

      it 'returns zero width' do
        expect(result[:width]).to eq(0.0)
      end

      it 'returns narrow type' do
        expect(result[:width_type]).to eq(:narrow)
      end
    end

    context 'when TC is below BC (edge case)' do
      subject(:result) do
        described_class.call(high: 22_100, low: 22_000, close: 22_000)
      end

      it 'ensures TC >= BC' do
        expect(result[:top_central]).to be >= result[:bottom_central]
      end

      it 'returns positive width' do
        expect(result[:width]).to be_positive
      end
    end
  end
end
