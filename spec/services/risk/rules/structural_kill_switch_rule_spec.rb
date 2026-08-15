# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::StructuralKillSwitchRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:index_instrument) { create(:instrument, :nifty_future) }
  let(:watchable) { create(:derivative, instrument: index_instrument) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: index_instrument,
      watchable: watchable,
      status: 'active',
      entry_price: 100.0,
      side: 'long_ce',
      meta: { 'direction' => 'long_ce', 'index_key' => 'NIFTY' }
    )
  end
  let(:position_data) do
    Positions::PositionData.new(tracker_id: tracker.id, entry_price: 100.0, current_ltp: 100.0)
  end
  let(:context) { Risk::Rules::RuleContext.new(position: position_data, tracker: tracker, risk_config: {}) }

  let(:series) { instance_double(CandleSeries, candles: Array.new(10), current_vwap: 25_000.0, ema: 25_000.0) }
  let(:underlying_ltp) { 25_000.0 }

  before do
    allow(Live::TickQuery).to receive(:for_security).and_return(
      MarketTick.new(segment: 'IDX_I', security_id: '13', ltp: underlying_ltp, timestamp: Time.current,
                     oi: nil, oi_change: nil, bid: nil, ask: nil, volume: nil, prev_close: nil)
    )
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(index_instrument)
    allow(Live::CandleSeriesCache).to receive(:fetch).and_return(series)
  end

  describe '#evaluate' do
    context 'when underlying breaks VWAP against a long call' do
      let(:underlying_ltp) { 24_900.0 } # below vwap*(1-0.002)

      it 'exits' do
        result = rule.evaluate(context)

        expect(result.exit?).to be true
        expect(result.reason).to eq('STRUCTURAL_KILL_VWAP')
      end
    end

    context 'when underlying holds above VWAP and EMA9' do
      let(:underlying_ltp) { 25_100.0 }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when candle series is too short' do
      let(:underlying_ltp) { 24_900.0 }
      let(:series) { instance_double(CandleSeries, candles: Array.new(3)) }

      it 'returns no_action' do
        result = rule.evaluate(context)

        expect(result.no_action?).to be true
      end
    end

    context 'when position is not active' do
      let(:underlying_ltp) { 24_900.0 }

      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)

        expect(result.skip?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 22' do
        expect(described_class::PRIORITY).to eq(22)
      end
    end
  end
end
