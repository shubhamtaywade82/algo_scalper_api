# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::EarliestEntryGuard do
  include ActiveSupport::Testing::TimeHelpers

  context 'when per-index earliest entry is configured' do
    let(:context) do
      {
        index_cfg: {
          key: 'SENSEX',
          execution: { earliest_entry_time: '09:30' }
        }
      }
    end

    it 'blocks before the index earliest time' do
      travel_to Time.zone.parse('2026-03-17 09:20:00 +05:30') do
        result = described_class.call(context)

        expect(result[:blocked]).to include('earliest entry time not reached for SENSEX')
        expect(result[:blocked]).to include('09:30 IST')
      end
    end

    it 'passes at or after the index earliest time' do
      travel_to Time.zone.parse('2026-03-17 09:35:00 +05:30') do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end

  context 'when only global earliest entry is configured' do
    let(:context) { { index_cfg: { key: 'NIFTY' } } }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { time_overrides: { earliest_entry_time: '09:30' } }
      )
    end

    it 'blocks before global earliest time' do
      travel_to Time.zone.parse('2026-03-17 09:25:00 +05:30') do
        result = described_class.call(context)

        expect(result[:blocked]).to include('earliest entry time not reached for NIFTY')
      end
    end
  end
end
