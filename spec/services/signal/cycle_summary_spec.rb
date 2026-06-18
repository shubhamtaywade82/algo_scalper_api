# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::CycleSummary do
  describe '#log_line' do
    it 'includes block reason when cycle was blocked' do
      summary = described_class.new(index_key: 'NIFTY')
      summary.block!('direction_gate:ranging', regime: 'RANGING', direction: 'bearish')

      expect(summary.log_line).to eq(
        '[SignalScheduler] NIFTY cycle: outcome=blocked regime=RANGING direction=bearish block=direction_gate:ranging'
      )
    end

    it 'omits block when entry succeeded' do
      summary = described_class.new(index_key: 'NIFTY')
      summary.entered!(direction: 'bullish', regime: 'TRENDING_UP')

      expect(summary.log_line).to eq(
        '[SignalScheduler] NIFTY cycle: outcome=entered regime=TRENDING_UP direction=bullish'
      )
    end
  end
end
