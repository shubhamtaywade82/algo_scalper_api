# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::MiddayQualityGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY' },
        pick: { adx_value: 24.0 },
        entry_metadata: { regime_confidence: 0.85 }
      }
    end

    let(:config) do
      {
        midday_guard: {
          enabled: true,
          min_confidence: 0.7,
          min_adx: 20,
          block_after_time: '15:00'
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(config)
    end

    context 'when config is disabled' do
      it 'passes entry' do
        allow(AlgoConfig).to receive(:fetch).and_return(midday_guard: { enabled: false })

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current time is within opening window' do
      it 'passes entry' do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 09:45:00 IST'))

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current time is after configured cutoff' do
      it 'blocks entry' do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 15:01:00 IST'))

        result = described_class.call(context)

        expect(result).to include(blocked: 'no new trades after 15:00')
      end
    end

    context 'when current time is midday and quality thresholds pass' do
      it 'passes entry' do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 11:30:00 IST'))

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current time is midday and confidence is below threshold' do
      it 'blocks entry' do
        allow(Time).to receive(:current).and_return(Time.zone.parse('2026-03-24 11:30:00 IST'))
        context[:entry_metadata][:regime_confidence] = 0.45

        result = described_class.call(context)

        expect(result).to include(blocked: /midday quality gate blocked/)
      end
    end
  end
end
