# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::PremiumBandGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: index_key }, pick: { ltp: premium } } }
    let(:index_key) { 'NIFTY' }
    let(:premium) { 150.0 }

    context 'when premium band config is not enabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(indices: {})
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when premium band config is enabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          indices: { 'NIFTY' => { premium_band: { min: 100, max: 200 } } }
        )
      end

      context 'and index_key is blank' do
        let(:index_key) { nil }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and premium is zero' do
        let(:premium) { 0.0 }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and premium band is not configured for the index' do
        let(:index_key) { 'BANKNIFTY' }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and premium band min/max are both zero' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return(
            indices: { 'NIFTY' => { premium_band: { min: 0, max: 0 } } }
          )
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and premium is within the band' do
        let(:premium) { 150.0 }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and premium is below the minimum' do
        let(:premium) { 80.0 }

        it 'blocks entry with details' do
          result = described_class.call(context)
          expect(result).to include(blocked: /premium_band/)
          expect(result[:blocked]).to include('NIFTY')
          expect(result[:blocked]).to include('below min')
          expect(result[:blocked]).to include('₹80.0')
        end
      end

      context 'and premium is above the maximum' do
        let(:premium) { 250.0 }

        it 'blocks entry with details' do
          result = described_class.call(context)
          expect(result).to include(blocked: /premium_band/)
          expect(result[:blocked]).to include('NIFTY')
          expect(result[:blocked]).to include('above max')
          expect(result[:blocked]).to include('₹250.0')
        end
      end
    end

    context 'when AlgoConfig.fetch raises an error' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError.new('config error'))
      end

      it 'allows entry (fails open)' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
