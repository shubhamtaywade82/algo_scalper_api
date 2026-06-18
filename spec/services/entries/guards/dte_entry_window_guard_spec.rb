# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::DteEntryWindowGuard do
  include ActiveSupport::Testing::TimeHelpers

  let(:context) do
    {
      index_cfg: { key: 'NIFTY' },
      pick: { security_id: '123', segment: 'NSE_FNO', expiry_date: Date.current }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        dte_parameters: {
          enabled: true,
          by_dte: {
            '0' => { max_entry_time: '12:30' }
          }
        }
      }
    )
  end

  context 'when DTE parameters are disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(risk: { dte_parameters: { enabled: false } })
    end

    it 'passes' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when before DTE max entry time' do
    it 'passes for 0-DTE' do
      travel_to Time.zone.parse('2026-03-17 12:00:00 +05:30') do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end

  context 'when after DTE max entry time' do
    it 'blocks 0-DTE entries' do
      travel_to Time.zone.parse('2026-03-17 12:45:00 +05:30') do
        result = described_class.call(context)

        expect(result[:blocked]).to include('DTE entry window closed')
        expect(result[:blocked]).to include('DTE=0')
        expect(result[:blocked]).to include('12:30')
      end
    end
  end
end
