# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::SegmentExpectancyGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: index_key } } }
    let(:index_key) { 'NIFTY' }
    let(:algo_config) { instance_double(AlgoConfig::Configuration) }
    let(:time_regime_service) { instance_double(Live::TimeRegimeService) }
    let(:segment_expectancy_analyzer) { instance_double(Trading::SegmentExpectancyAnalyzer) }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(algo_config)
      allow(algo_config).to receive(:[]).with(:segment_expectancy_guard).and_return(guard_config)
      allow(Live::TimeRegimeService).to receive(:instance).and_return(time_regime_service)
      allow(time_regime_service).to receive(:current_regime).and_return(regime)
      allow(Trading::SegmentExpectancyAnalyzer).to receive(:instance).and_return(segment_expectancy_analyzer)
    end

    context 'when segment expectancy guard is disabled' do
      let(:guard_config) { { enabled: false } }
      let(:regime) { 'MORNING' }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when segment expectancy guard is enabled' do
      let(:guard_config) { { enabled: true } }
      let(:regime) { 'MORNING' }

      context 'and index_key is blank' do
        let(:index_key) { nil }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and segment has positive or break-even expectancy' do
        before do
          allow(segment_expectancy_analyzer).to receive(:negative_edge?).with(index_key: 'NIFTY', regime: 'MORNING').and_return(false)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and segment has negative expectancy' do
        before do
          allow(segment_expectancy_analyzer).to receive(:negative_edge?).with(index_key: 'NIFTY', regime: 'MORNING').and_return(true)
        end

        it 'blocks entry with details' do
          result = described_class.call(context)
          expect(result).to include(blocked: /segment expectancy guard/)
          expect(result[:blocked]).to include('NIFTY/MORNING')
          expect(result[:blocked]).to include('negative realized edge')
        end
      end

      context 'and an error occurs during check' do
        before do
          allow(segment_expectancy_analyzer).to receive(:negative_edge?).and_raise(StandardError.new('analyzer error'))
        end

        it 'allows entry (fails open)' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end

    context 'when AlgoConfig.fetch raises an error' do
      let(:guard_config) { {} }
      let(:regime) { 'MORNING' }

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
