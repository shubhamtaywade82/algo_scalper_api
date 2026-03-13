# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::TrailingEngine do
  let(:tracker) do
    instance_double('PositionTracker',
                    symbol: symbol,
                    entry_price: 100.0,
                    highest_price: highest_price,
                    meta: { 'highest_price' => highest_price })
  end
  let(:highest_price) { nil }
  let(:engine) { described_class.new(position: tracker, ltp: ltp, highest_price: highest_price) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: {
        institutional_trailing: {
          nifty: {
            early_trigger: 0.05,
            early_sl_offset: -0.12,
            breakeven_trigger: 0.10,
            activate_trigger: 0.20,
            trailing_distance: 0.22
          },
          sensex: {
            early_trigger: 0.06,
            early_sl_offset: -0.10,
            breakeven_trigger: 0.12,
            activate_trigger: 0.18,
            trailing_distance: 0.30
          }
        }
      }
    })

    # Mock update_column/update! for call tests
    allow(tracker).to receive(:update!)
    allow(tracker).to receive(:update_column)
  end

  context 'with NIFTY' do
    let(:symbol) { 'NIFTY24MAR22000CE' }

    describe '#calculate_sl' do
      context 'Phase 1: Slack (+5% profit)' do
        let(:ltp) { 105.0 }
        it 'returns early_sl_offset (-12% from entry)' do
          expect(engine.calculate_sl).to eq(88.0) # 100 * (1 - 0.12)
        end
      end

      context 'Phase 2: Breakeven (+10% profit)' do
        let(:ltp) { 110.0 }
        it 'returns entry price' do
          expect(engine.calculate_sl).to eq(100.0)
        end
      end

      context 'Phase 3: High-Watermark (+20% profit)' do
        let(:ltp) { 120.0 }
        it 'returns price with 22% trailing gap from peak' do
          # 120 * (1 - 0.22) = 120 * 0.78 = 93.6
          expect(engine.calculate_sl).to eq(93.6)
        end

        context 'with existing high water mark' do
          let(:highest_price) { 130.0 }
          let(:ltp) { 125.0 }
          it 'uses the highest price for calculation' do
            # 130 * 0.78 = 101.4
            expect(engine.calculate_sl).to eq(101.4)
          end
        end
      end

      context 'No trigger (< 5% profit)' do
        let(:ltp) { 102.0 }
        it 'returns nil' do
          expect(engine.calculate_sl).to be_nil
        end
      end
    end
  end

  context 'with SENSEX' do
    let(:symbol) { 'SENSEX24MAR72000CE' }

    describe '#calculate_sl' do
      context 'Phase 1: Slack (+6% profit)' do
        let(:ltp) { 106.0 }
        it 'returns early_sl_offset (-10% from entry)' do
          expect(engine.calculate_sl).to eq(90.0) # 100 * (1 - 0.10)
        end
      end

      context 'Phase 2: Breakeven (+12% profit)' do
        let(:ltp) { 112.0 }
        it 'returns entry price' do
          expect(engine.calculate_sl).to eq(100.0)
        end
      end

      context 'Phase 3: High-Watermark (+18% profit)' do
        let(:ltp) { 118.0 }
        it 'returns price with 30% trailing gap from peak' do
          # 118 * (1 - 0.30) = 118 * 0.7 = 82.6
          expect(engine.calculate_sl).to eq(82.6)
        end
      end
    end
  end
end
