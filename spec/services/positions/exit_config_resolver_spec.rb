# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitConfigResolver do
  describe '.for' do
    context 'when the tracker carries a pinned snapshot' do
      let(:tracker) do
        instance_double(PositionTracker, meta: { 'config_snapshot' => { 'risk' => { 'sl_pct' => 0.07 } } })
      end

      it 'returns the pinned snapshot with symbolized keys' do
        expect(described_class.for(tracker).dig(:risk, :sl_pct)).to eq(0.07)
      end

      it 'does not change when live config changes afterwards' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.99 })
        expect(described_class.for(tracker).dig(:risk, :sl_pct)).to eq(0.07)
      end
    end

    context 'when the tracker has no pinned snapshot' do
      let(:tracker) { instance_double(PositionTracker, meta: {}) }

      it 'falls back to the live effective config' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.02 })
        expect(described_class.for(tracker).dig(:risk, :sl_pct)).to eq(0.02)
      end
    end

    context 'when the tracker is nil' do
      it 'falls back to the live effective config' do
        allow(AlgoConfig).to receive(:fetch).and_return(risk: { sl_pct: 0.02 })
        expect(described_class.for(nil).dig(:risk, :sl_pct)).to eq(0.02)
      end
    end
  end
end
