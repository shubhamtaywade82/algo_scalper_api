# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portfolio::PaperPeakTracker do
  let(:redis) { instance_double(Redis) }

  before do
    allow(Time.zone).to receive(:today).and_return(Date.new(2026, 3, 25))
    described_class.instance_variable_set(:@redis, redis)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:set)
    allow(redis).to receive(:del)
  end

  after do
    described_class.instance_variable_set(:@redis, nil)
  end

  describe '.observe!' do
    it 'stores total when higher than previous peak' do
      allow(redis).to receive(:get).with('portfolio:paper:daily_peak:2026-03-25').and_return('100.0')
      described_class.observe!(150)
      expect(redis).to have_received(:set).with('portfolio:paper:daily_peak:2026-03-25', '150.0', ex: described_class::TTL)
    end

    it 'does not lower stored peak' do
      allow(redis).to receive(:get).with('portfolio:paper:daily_peak:2026-03-25').and_return('200.0')
      described_class.observe!(50)
      expect(redis).not_to have_received(:set)
    end
  end

  describe '.current_for' do
    it 'returns stored float' do
      allow(redis).to receive(:get).with('portfolio:paper:daily_peak:2026-03-25').and_return('123.45')
      expect(described_class.current_for).to eq(123.45)
    end
  end

  describe '.reset_day!' do
    it 'deletes the daily key' do
      described_class.reset_day!
      expect(redis).to have_received(:del).with('portfolio:paper:daily_peak:2026-03-25')
    end
  end
end
