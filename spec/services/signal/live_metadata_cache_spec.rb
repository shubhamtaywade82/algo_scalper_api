# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::LiveMetadataCache do
  subject(:cache) { described_class.instance }

  let(:signal_id) { 42_001 }

  after do
    cache.clear(signal_id)
  end

  describe '.slim_metadata' do
    it 'keeps only audit-relevant keys for db persistence' do
      full = {
        'regime' => 'TRENDING',
        'strategy' => 'supertrend_adx',
        'mtf_rsi' => { '1m' => 55, '5m' => 60 },
        'gamma_pressure' => 0.8
      }

      slim = described_class.slim_metadata(full)

      expect(slim).to include('regime' => 'TRENDING', 'strategy' => 'supertrend_adx')
      expect(slim).not_to have_key('mtf_rsi')
    end
  end

  describe '#store and #fetch' do
    it 'round-trips full diagnostic metadata' do
      cache.store(signal_id, 'regime' => 'CHOPPY', 'mtf_macd' => { '1m' => 1.2 })

      expect(cache.fetch(signal_id)).to include('regime' => 'CHOPPY', 'mtf_macd' => { '1m' => 1.2 })
    end
  end
end
