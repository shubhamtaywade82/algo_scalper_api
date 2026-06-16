# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::TickMetrics do
  describe '.volume_delta' do
    it 'uses last minus first cumulative volume' do
      ticks = [
        { vol: 10_000 },
        { vol: 10_400 },
        { vol: 10_900 }
      ]

      expect(described_class.volume_delta(ticks)).to eq(900)
    end

    it 'returns zero when volume does not increase' do
      ticks = [{ vol: 100 }, { vol: 100 }]

      expect(described_class.volume_delta(ticks)).to eq(0)
    end
  end

  describe '.oi_delta' do
    it 'returns signed open interest change' do
      ticks = [{ oi: 5000 }, { oi: 4500 }]

      expect(described_class.oi_delta(ticks)).to eq(-500)
    end
  end

  describe '.mean_interval_volume_delta' do
    it 'returns average positive tick-to-tick volume deltas' do
      ticks = [
        { vol: 10_000 },
        { vol: 10_200 },
        { vol: 10_500 },
        { vol: 10_700 }
      ]

      expect(described_class.mean_interval_volume_delta(ticks)).to be_within(0.01).of(233.33)
    end

    it 'returns nil when there are not enough positive deltas' do
      ticks = [{ vol: 100 }, { vol: 100 }]

      expect(described_class.mean_interval_volume_delta(ticks, min_samples: 2)).to be_nil
    end
  end
end
