# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::DerivativeChainAnalyzer do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: 13 } }
  let(:analyzer) { described_class.new(index_key: 'NIFTY') }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
  end

  describe '#find_nearest_expiry' do
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(instrument)
    end

    context 'when nearest upcoming expiry is within max_expiry_days (monthly expiry week)' do
      let(:today) { Date.new(2026, 11, 23) }
      let(:monthly_expiry) { today }
      let(:next_weekly_expiry) { Date.new(2026, 12, 1) }

      before do
        allow(Time.zone).to receive(:today).and_return(today)
        allow(instrument).to receive(:expiry_list).and_return([monthly_expiry, next_weekly_expiry])
      end

      it 'returns the nearest current-week expiry directly' do
        expect(analyzer.find_nearest_expiry).to eq('2026-11-23')
      end
    end

    context 'when earliest expiry is beyond max_expiry_days and weekly expiries exist' do
      let(:today) { Date.new(2026, 11, 1) }
      let(:first_weekly_expiry) { Date.new(2026, 11, 12) }
      let(:second_weekly_expiry) { Date.new(2026, 11, 19) }

      before do
        allow(Time.zone).to receive(:today).and_return(today)
        allow(instrument).to receive(:expiry_list).and_return([first_weekly_expiry, second_weekly_expiry])
        allow(analyzer).to receive(:weekly_expiries_in_db).and_return(Set.new([first_weekly_expiry]))
      end

      it 'finds the weekly expiry' do
        expect(analyzer.find_nearest_expiry).to eq('2026-11-12')
      end
    end
  end
end
