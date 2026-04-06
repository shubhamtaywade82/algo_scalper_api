# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig do
  after { described_class.reset! }

  describe '.fetch' do
    it 'returns a hash with symbolized keys' do
      result = described_class.fetch
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it 'caches consecutive calls within TTL' do
      first = described_class.fetch
      second = described_class.fetch
      expect(first).to equal(second)
    end

    it 'returns fresh config after reset!' do
      first = described_class.fetch
      described_class.reset!
      second = described_class.fetch
      expect(first).not_to equal(second)
    end
  end

  describe '.mode' do
    it 'returns mode from config' do
      allow(described_class).to receive(:fetch).and_return({ mode: 'paper' })
      expect(described_class.mode).to eq('paper')
    end
  end
end
