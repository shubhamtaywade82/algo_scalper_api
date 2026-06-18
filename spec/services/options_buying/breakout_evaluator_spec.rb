# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::BreakoutEvaluator do
  let(:index_sid) { '13' }
  let(:option_sid) { '456' }
  let(:resistance) { 24_500.0 }
  let(:option_ticks) do
    [
      { ltp: 150.0, oi: 5000, vol: 10_000, ts: Time.current.to_i - 40 },
      { ltp: 152.0, oi: 4500, vol: 10_500, ts: Time.current.to_i - 10 }
    ]
  end

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', sid: index_sid }])
    allow(OptionsBuying::Mode).to receive_messages(
      breakout_enabled?: true,
      intraday?: true,
      streams_enabled?: false,
      telemetry_sink_enabled?: false,
      config: {
        breakout: { volume_multiplier: 2.0, require_oi_unwind: true, compression_arm: false }
      }
    )
    allow(OptionsBuying::StateStore).to receive(:resistance).with('NIFTY').and_return(resistance)
    allow(OptionsBuying::StateStore).to receive(:support).with('NIFTY').and_return(nil)
    allow(OptionsBuying::StateStore).to receive(:volume_threshold_baseline).with(option_sid).and_return(150.0)
    allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bullish).and_return(false)
    allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return([])
  end

  describe '.evaluate!' do
    it 'arms breakout when index spot clears resistance and option flow confirms' do
      bucket = 1_700_000_000
      allow(OptionsBuying::StateStore).to receive(:minute_ticks).with(option_sid, bucket).and_return(option_ticks)
      allow(OptionsBuying::StateStore).to receive(:cache_snapshot).with(index_sid).and_return({ ltp: 24_520.0 })

      expect(OptionsBuying::StateStore).to receive(:set_breakout_ready!).with('NIFTY', direction: :bullish)

      described_class.evaluate!(index_key: 'NIFTY', security_id: option_sid, bucket: bucket)
    end

    it 'skips telemetry when breakout is already armed' do
      allow(OptionsBuying::Mode).to receive(:telemetry_sink_enabled?).and_return(true)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bullish).and_return(true)

      bucket = 1_700_000_000
      allow(OptionsBuying::StateStore).to receive(:minute_ticks).with(option_sid, bucket).and_return(option_ticks)
      allow(OptionsBuying::StateStore).to receive(:cache_snapshot).with(index_sid).and_return({ ltp: 24_520.0 })
      expect(OptionsBuying::TelemetrySinkJob).not_to receive(:perform_later)

      described_class.evaluate!(index_key: 'NIFTY', security_id: option_sid, bucket: bucket)
    end
  end

  describe '.evaluate_stream_tick!' do
    before do
      allow(OptionsBuying::Mode).to receive(:streams_enabled?).and_return(true)
    end

    it 'uses index spot from trigger ticks and option stream for volume delta' do
      index_ticks = [
        { ltp: 24_510.0, oi: 0, vol: 0, ts: Time.current.to_i - 40 },
        { ltp: 24_520.0, oi: 0, vol: 0, ts: Time.current.to_i - 30 },
        { ltp: 24_525.0, oi: 0, vol: 0, ts: Time.current.to_i - 20 },
        { ltp: 24_530.0, oi: 0, vol: 0, ts: Time.current.to_i - 10 },
        { ltp: 24_535.0, oi: 0, vol: 0, ts: Time.current.to_i }
      ]
      allow(OptionsBuying::StateStore).to receive(:primary_radar_strike).with('NIFTY', type: 'CE').and_return(
        { security_id: option_sid, volume: 20_000 }
      )
      allow(OptionsBuying::StateStore).to receive(:primary_radar_strike).with('NIFTY', type: 'PE').and_return(nil)
      allow(OptionsBuying::StateStore).to receive(:stream_window).with(index_sid).and_return(index_ticks[0...-1])
      allow(OptionsBuying::StateStore).to receive(:stream_window).with(option_sid).and_return(
        [
          { ltp: 150.0, oi: 5000, vol: 10_000, ts: Time.current.to_i - 40 },
          { ltp: 151.0, oi: 4900, vol: 10_100, ts: Time.current.to_i - 30 },
          { ltp: 152.0, oi: 4800, vol: 10_250, ts: Time.current.to_i - 20 },
          { ltp: 153.0, oi: 4700, vol: 10_400, ts: Time.current.to_i - 10 },
          { ltp: 154.0, oi: 4500, vol: 10_500, ts: Time.current.to_i }
        ]
      )

      expect(OptionsBuying::StateStore).to receive(:set_breakout_ready!).with('NIFTY', direction: :bullish)

      described_class.evaluate_stream_tick!(
        index_key: 'NIFTY',
        security_id: index_sid,
        current_tick: index_ticks.last
      )
    end

    it 'uses cached index spot when an option tick triggers evaluation' do
      current_tick = { ltp: 155.0, oi: 4400, vol: 10_600, ts: Time.current.to_i }
      allow(OptionsBuying::StateStore).to receive(:stream_window).with(option_sid).and_return(
        [
          { ltp: 150.0, oi: 5000, vol: 10_000, ts: Time.current.to_i - 40 },
          { ltp: 151.0, oi: 4900, vol: 10_100, ts: Time.current.to_i - 30 },
          { ltp: 152.0, oi: 4800, vol: 10_250, ts: Time.current.to_i - 20 },
          { ltp: 153.0, oi: 4700, vol: 10_400, ts: Time.current.to_i - 10 }
        ]
      )
      allow(OptionsBuying::StateStore).to receive(:cache_snapshot).with(index_sid).and_return({ ltp: 24_520.0 })

      expect(OptionsBuying::StateStore).to receive(:set_breakout_ready!).with('NIFTY', direction: :bullish)

      described_class.evaluate_stream_tick!(
        index_key: 'NIFTY',
        security_id: option_sid,
        current_tick: current_tick
      )
    end
  end

  describe 'bearish breakdown (long PE)' do
    let(:pe_sid) { '789' }
    let(:support) { 24_500.0 }

    before do
      allow(OptionsBuying::Mode).to receive(:config).and_return(
        breakout: { volume_multiplier: 2.0, require_oi_unwind: true, compression_arm: false }
      )
      allow(OptionsBuying::StateStore).to receive(:support).with('NIFTY').and_return(support)
      allow(OptionsBuying::StateStore).to receive(:resistance).with('NIFTY').and_return(25_000.0)
      allow(OptionsBuying::StateStore).to receive(:volume_threshold_baseline).with(pe_sid).and_return(150.0)
      allow(OptionsBuying::StateStore).to receive(:volume_threshold_baseline).with(option_sid).and_return(150.0)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bearish).and_return(false)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bullish).and_return(false)
      allow(OptionsBuying::StateStore).to receive(:primary_radar_strike).with('NIFTY', type: 'PE').and_return(
        { security_id: pe_sid, type: 'PE', volume: 20_000 }
      )
      allow(OptionsBuying::StateStore).to receive(:primary_radar_strike).with('NIFTY', type: 'CE').and_return(
        { security_id: option_sid, type: 'CE', volume: 20_000 }
      )
      # PE strike must be discoverable so an option-triggered evaluation resolves to :bearish.
      allow(OptionsBuying::StateStore).to receive(:radar_strikes).with('NIFTY').and_return(
        [{ security_id: pe_sid, type: 'PE', volume: 20_000 }]
      )
    end

    it 'arms a bearish breakout when index spot breaks below support and PE flow confirms' do
      bucket = 1_700_000_000
      allow(OptionsBuying::StateStore).to receive(:minute_ticks).with(pe_sid, bucket).and_return(option_ticks)
      allow(OptionsBuying::StateStore).to receive(:minute_ticks).with(option_sid, bucket).and_return([])
      # index broke DOWN through support
      allow(OptionsBuying::StateStore).to receive(:cache_snapshot).with(index_sid).and_return({ ltp: 24_480.0 })

      expect(OptionsBuying::StateStore).to receive(:set_breakout_ready!).with('NIFTY', direction: :bearish)

      described_class.evaluate!(index_key: 'NIFTY', security_id: pe_sid, bucket: bucket)
    end
  end
end
