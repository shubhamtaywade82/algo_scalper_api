# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::ChainContext do
  # A chain-watch snapshot shape produced by ChainWatchService#run_loop.
  def snapshot_for(legs, spot:, chain_stale: false, expiry: '2026-11-26', index_key: 'NIFTY')
    {
      index_key: index_key, spot: spot, atm_strike: nil, expiry: expiry,
      legs: legs, chain_stale: chain_stale, updated_at: Time.current.iso8601
    }
  end

  # CE/PE leg pair helper with OI/volume/bid/ask, matching the leg hash
  # ChainWatchService builds (merge_tick_data output shape).
  def leg(strike, type, oi:, volume: 0, ltp: 100.0, bid: nil, ask: nil)
    {
      strike: strike.to_f, type: type, security_id: "#{strike}#{type}", segment: 'NSE_FNO',
      lot_size: 75, ltp: ltp, oi: oi, oi_change: 0, volume: volume, iv: nil, delta: nil,
      gamma: nil, theta: nil, vega: nil, bid: bid, ask: ask, feed_stale: false
    }
  end

  describe '.from_snapshot' do
    it 'computes PCR, walls, straddle, expected range and a bearish verdict' do
      # Window around spot 25452.8: call OI dominates (PCR < 0.7), call wall at
      # 25600, put wall at 25500, ATM straddle from LTPs (no bid/ask at 25450).
      legs = [
        leg(25_400, 'CE', oi: 200_000), leg(25_400, 'PE', oi: 300_000),
        leg(25_450, 'CE', oi: 400_000), leg(25_450, 'PE', oi: 500_000),
        leg(25_500, 'CE', oi: 900_000, volume: 2_000_000, ltp: 141.2, bid: 140.8, ask: 141.6),
        leg(25_500, 'PE', oi: 1_200_000, volume: 1_000_000, ltp: 89.4, bid: 89.1, ask: 89.7),
        leg(25_550, 'CE', oi: 500_000), leg(25_550, 'PE', oi: 400_000),
        leg(25_600, 'CE', oi: 2_541_000, volume: 3_000_000), leg(25_600, 'PE', oi: 300_000)
      ]
      spot = 25_452.8

      payload = described_class.from_snapshot(snapshot_for(legs, spot: spot))

      # Totals: call_oi = 4_541_000, put_oi = 2_700_000 -> pcr = 0.59; every
      # strike lies within 3*50 of ATM 25_450 so atm band = window.
      expect(payload['pcr']).to eq(0.59)
      expect(payload['atm_pcr']).to eq(0.59)
      expect(payload['call_resistance']).to eq('strike' => 25_600.0, 'oi' => 2_541_000, 'distance' => 147.2)
      # Max put OI (1.2m) sits ABOVE spot at 25_500 -> distance -47.2: the
      # put wall has been breached, which is itself a bearish signal.
      expect(payload['put_support']).to eq('strike' => 25_500.0, 'oi' => 1_200_000, 'distance' => -47.2)
      expect(payload['headroom_ce']).to eq(147.2)
      expect(payload['headroom_pe']).to eq(-47.2)
      # ATM is 25_450, whose legs carry LTP 100 each (no bid/ask there) ->
      # straddle = 100 + 100 = 200.
      expect(payload['straddle_premium']).to eq(200.0)
      expect(payload['expected_range']).to eq('lower' => 25_250.0, 'upper' => 25_650.0)
      # pcr 0.59 <= 0.7 -> -25; atm_pcr 0.59 <= 0.8 -> -20; call_dist 147.2 > 50 -> +15;
      # put_dist -47.2 <= 0 -> -20; call_volume 5m > put_volume 2.5m * 1.3 -> +15
      # total: -25 -20 +15 -20 +15 = -35 -> BEARISH
      expect(payload['sentiment_score']).to eq(-35)
      expect(payload['bias']).to eq('BEARISH')
      expect(payload['verdict']).to eq('BEARISH (score -35, PCR 0.59, ATM PCR 0.59)')
      expect(payload['schema']).to eq('chain-context/1')
      expect(payload['underlying']).to eq('NIFTY')
      expect(payload['expiry']).to eq('2026-11-26')
      expect(payload['source']).to eq('algo_scalper_api')
      expect(payload['window_strikes']).to eq(3)
    end

    it 'returns neutral PCR 1.0 and spot walls when no leg carries OI' do
      legs = [leg(25_450, 'CE', oi: 0), leg(25_450, 'PE', oi: 0)]
      payload = described_class.from_snapshot(snapshot_for(legs, spot: 25_450.0))

      expect(payload['pcr']).to eq(1.0)
      expect(payload['atm_pcr']).to eq(1.0)
      expect(payload['call_resistance']['strike']).to eq(25_450.0)
      expect(payload['put_support']['oi']).to eq(0)
    end

    it 'uses LTP for the straddle when bid/ask are missing' do
      legs = [
        leg(25_450, 'CE', oi: 1_000, ltp: 120.0),
        leg(25_450, 'PE', oi: 1_000, ltp: 80.0)
      ]
      payload = described_class.from_snapshot(snapshot_for(legs, spot: 25_450.0))

      expect(payload['straddle_premium']).to eq(200.0)
      expect(payload['expected_range']).to eq('lower' => 25_250.0, 'upper' => 25_650.0)
    end

    it 'returns nil for a stale chain (no fresh REST poll this cycle)' do
      legs = [leg(25_450, 'CE', oi: 1_000), leg(25_450, 'PE', oi: 1_000)]
      expect(described_class.from_snapshot(snapshot_for(legs, spot: 25_450.0, chain_stale: true))).to be_nil
    end

    it 'returns nil without spot, legs, or a non-ISO expiry' do
      expect(described_class.from_snapshot(snapshot_for([], spot: nil))).to be_nil
      legs = [leg(25_450, 'CE', oi: 1_000)]
      expect(described_class.from_snapshot(snapshot_for(legs, spot: 0))).to be_nil
      expect(described_class.from_snapshot(snapshot_for(legs, spot: 25_450.0, expiry: 'weekly'))).to be_nil
      expect(described_class.from_snapshot(nil)).to be_nil
    end
  end
end
