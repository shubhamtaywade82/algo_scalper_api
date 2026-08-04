# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Slicer do
  let(:nifty_key) { 'NIFTY' }
  let(:banknifty_key) { 'BANKNIFTY' }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      options_buying: {
        execution: {
          order_slicing: {
            enabled: true,
            delay_ms: 500,
            freeze_limits: {
              'NIFTY' => 1800,
              'BANKNIFTY' => 900,
              'default' => 1800
            }
          }
        }
      }
    })
  end

  describe '.slice_quantity' do
    context 'when quantity is below the freeze limit' do
      it 'returns a single slice with the full quantity' do
        expect(described_class.slice_quantity(index_key: nifty_key, total_quantity: 1500)).to eq([1500])
        expect(described_class.slice_quantity(index_key: banknifty_key, total_quantity: 800)).to eq([800])
      end
    end

    context 'when quantity exceeds the freeze limit' do
      it 'splits the quantity into slices equal to the limit plus the remainder' do
        # NIFTY limit = 1800. 3000 -> 1800, 1200
        expect(described_class.slice_quantity(index_key: nifty_key, total_quantity: 3000)).to eq([1800, 1200])

        # BANKNIFTY limit = 900. 2000 -> 900, 900, 200
        expect(described_class.slice_quantity(index_key: banknifty_key, total_quantity: 2000)).to eq([900, 900, 200])
      end
    end

    context 'when slicing is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          options_buying: {
            execution: {
              order_slicing: {
                enabled: false
              }
            }
          }
        })
      end

      it 'returns a single slice even if it exceeds the limit' do
        expect(described_class.slice_quantity(index_key: banknifty_key, total_quantity: 2000)).to eq([2000])
      end
    end
  end

  describe '.delay_seconds' do
    it 'returns the delay in fractional seconds' do
      expect(described_class.delay_seconds).to eq(0.5)
    end
  end
end
