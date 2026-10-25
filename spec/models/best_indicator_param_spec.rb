# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BestIndicatorParam do
  let(:instrument) { create(:instrument) }

  def build_param(**overrides)
    described_class.new(
      {
        instrument: instrument,
        interval: '5m',
        indicator: 'combined',
        params: { period: 10 },
        metrics: { win_rate: 0.6 },
        score: 0.72
      }.merge(overrides)
    )
  end

  describe 'validations' do
    it 'is valid with all required attributes' do
      expect(build_param).to be_valid
    end

    it 'requires an instrument' do
      param = build_param(instrument: nil)
      expect(param).not_to be_valid
      expect(param.errors[:instrument]).to be_present
    end

    it 'requires interval, params, metrics, and score' do
      param = described_class.new(instrument: instrument, interval: nil, params: nil, metrics: nil, score: nil)
      expect(param).not_to be_valid
      expect(param.errors[:interval]).to be_present
      expect(param.errors[:params]).to be_present
      expect(param.errors[:metrics]).to be_present
      expect(param.errors[:score]).to be_present
    end

    it 'accepts a zero score as present' do
      expect(build_param(score: 0)).to be_valid
    end
  end

  describe 'scopes' do
    before do
      described_class.create!(instrument: instrument, interval: '5m', indicator: 'combined',
                              params: { p: 1 }, metrics: { m: 1 }, score: 0.9)
      described_class.create!(instrument: instrument, interval: '5m', indicator: 'rsi',
                              params: { p: 2 }, metrics: { m: 2 }, score: 0.5)
      described_class.create!(instrument: instrument, interval: '15m', indicator: 'combined',
                              params: { p: 3 }, metrics: { m: 3 }, score: 0.7)
      other = create(:instrument)
      described_class.create!(instrument: other, interval: '5m', indicator: 'combined',
                              params: { p: 4 }, metrics: { m: 4 }, score: 0.4)
    end

    it '.best_for returns the single combined row for instrument+interval' do
      rows = described_class.best_for(instrument.id, '5m')
      expect(rows.length).to eq(1)
      expect(rows.first.indicator).to eq('combined')
      expect(rows.first.score).to eq(0.9)
    end

    it '.best_for_indicator filters by indicator name' do
      rows = described_class.best_for_indicator(instrument.id, '5m', 'rsi')
      expect(rows.length).to eq(1)
      expect(rows.first.params).to eq({ 'p' => 2 })
    end

    it '.for_instrument_interval returns every indicator for the pair' do
      rows = described_class.for_instrument_interval(instrument.id, '5m')
      expect(rows.length).to eq(2)
    end

    it 'scopes stay within the requested instrument' do
      expect(described_class.for_instrument_interval(instrument.id, '15m').length).to eq(1)
    end
  end
end
