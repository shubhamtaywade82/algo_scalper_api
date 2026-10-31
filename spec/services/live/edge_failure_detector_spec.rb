# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::EdgeFailureDetector do
  let(:redis) { instance_double(Redis) }
  let(:detector) do
    inst = described_class.instance
    inst.instance_variable_set(:@redis, redis)
    inst
  end

  let(:enabled_config) do
    {
      risk: {
        edge_failure_detector: {
          enabled: true,
          rolling_window_size: 5,
          rolling_window_threshold_rupees: -3000,
          max_consecutive_sls: 2,
          pause_duration_minutes: 60,
          consecutive_sl_pause_minutes: 30,
          session_based_pause: false
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(enabled_config)
    allow(redis).to receive(:lpush)
    allow(redis).to receive(:ltrim)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:incr)
    allow(redis).to receive(:del)
    allow(redis).to receive(:setex)
    allow(redis).to receive(:scan_each)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
  end

  describe '#entries_paused?' do
    context 'when feature is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          risk: { edge_failure_detector: { enabled: false } }
        )
      end

      it 'returns paused:false' do
        expect(detector.entries_paused?(index_key: 'NIFTY')).to eq({ paused: false, reason: nil })
      end
    end

    context 'when rolling window net PnL is below threshold' do
      before do
        # 5 trades, net PnL = -3500 (below -3000 threshold)
        trades = [
          { 'pnl' => -1000, 'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -800,  'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -500,  'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -700,  'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -500,  'exit_time' => Time.current.to_i }.to_json
        ]
        allow(redis).to receive(:lrange).and_return(trades)
        allow(redis).to receive(:get).and_return(nil) # No existing pause
      end

      it 'pauses with rolling_pnl_window reason' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be true
        expect(result[:reason]).to eq('rolling_pnl_window')
        expect(result[:net_pnl]).to eq(-3500.0)
        expect(result[:resume_at]).to be > Time.current
      end
    end

    context 'when rolling window net PnL is above threshold' do
      before do
        trades = [
          { 'pnl' => 500,  'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -200, 'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => 800,  'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => -100, 'exit_time' => Time.current.to_i }.to_json,
          { 'pnl' => 300,  'exit_time' => Time.current.to_i }.to_json
        ]
        allow(redis).to receive(:lrange).and_return(trades)
        allow(redis).to receive(:get).and_return(nil)
      end

      it 'does not pause' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be false
      end
    end

    context 'when fewer than window_size trades have occurred' do
      before do
        allow(redis).to receive(:lrange).and_return([
          { 'pnl' => -10_000, 'exit_time' => Time.current.to_i }.to_json
        ])
        allow(redis).to receive(:get).and_return(nil)
      end

      it 'does not pause (insufficient sample)' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be false
      end
    end

    context 'when consecutive SL count exceeds max' do
      before do
        # Empty rolling window (skips rolling breaker)
        allow(redis).to receive(:lrange).and_return([])
        allow(redis).to receive(:get).with('edge_failure:consecutive_sl:NIFTY').and_return('3')
        allow(redis).to receive(:get).with('edge_failure:pause:NIFTY:consecutive_sls').and_return(nil)
      end

      it 'pauses with consecutive_sls reason' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be true
        expect(result[:reason]).to eq('consecutive_sls')
        expect(result[:consecutive_count]).to eq(3)
      end
    end

    context 'when already paused for rolling_pnl_window' do
      before do
        trades = [{ 'pnl' => -10_000, 'exit_time' => Time.current.to_i }.to_json] * 5
        allow(redis).to receive(:lrange).and_return(trades)
        existing_pause = {
          'reason' => 'rolling_pnl_window',
          'resume_at' => (Time.current + 30.minutes).to_i,
          'paused_at' => Time.current.to_i,
          'details' => { 'net_pnl' => -10_000 }
        }.to_json
        allow(redis).to receive(:get).with('edge_failure:pause:NIFTY:rolling_pnl_window').and_return(existing_pause)
      end

      it 'returns the existing pause state instead of creating a new one' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be true
        expect(result[:reason]).to eq('rolling_pnl_window')
        expect(result[:details]['net_pnl']).to eq(-10_000)
        # Should not call setex (no new pause)
        expect(redis).not_to receive(:setex)
        detector.entries_paused?(index_key: 'NIFTY')
      end
    end

    context 'when an existing pause has expired' do
      before do
        trades = [{ 'pnl' => -10_000, 'exit_time' => Time.current.to_i }.to_json] * 5
        allow(redis).to receive(:lrange).and_return(trades)
        expired_pause = {
          'reason' => 'rolling_pnl_window',
          'resume_at' => (Time.current - 10.minutes).to_i,
          'paused_at' => (Time.current - 70.minutes).to_i,
          'details' => {}
        }.to_json
        allow(redis).to receive(:get).with('edge_failure:pause:NIFTY:rolling_pnl_window').and_return(expired_pause)
      end

      it 'clears the expired pause and re-evaluates' do
        expect(redis).to receive(:del).with('edge_failure:pause:NIFTY:rolling_pnl_window')
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be true # re-paused because trades are still bad
      end
    end
  end

  describe '#record_trade_result' do
    context 'when exit_reason indicates stop loss' do
      it 'records the trade and increments consecutive SL counter' do
        expect(redis).to receive(:lpush)
        expect(redis).to receive(:ltrim)
        expect(redis).to receive(:expire)
        expect(redis).to receive(:incr).with('edge_failure:consecutive_sl:NIFTY')
        result = detector.record_trade_result(index_key: 'NIFTY', pnl_rupees: -500, exit_reason: 'SL HIT')
        expect(result).to be true
      end
    end

    context 'when exit_reason does NOT indicate stop loss' do
      it 'records the trade and resets consecutive SL counter' do
        expect(redis).to receive(:lpush)
        expect(redis).to receive(:ltrim)
        expect(redis).to receive(:expire)
        expect(redis).to receive(:del).with('edge_failure:consecutive_sl:NIFTY')
        result = detector.record_trade_result(index_key: 'NIFTY', pnl_rupees: 200, exit_reason: 'TP HIT')
        expect(result).to be true
      end
    end

    it 'returns false when redis is unavailable' do
      detector = described_class.instance
      detector.instance_variable_set(:@redis, nil)
      expect(detector.record_trade_result(index_key: 'NIFTY', pnl_rupees: -100, exit_reason: 'SL HIT')).to be false
    end

    it 'returns false on unexpected error' do
      allow(redis).to receive(:lpush).and_raise(StandardError, 'redis gone')
      result = detector.record_trade_result(index_key: 'NIFTY', pnl_rupees: -100, exit_reason: 'SL HIT')
      expect(result).to be false
    end

    it 'normalizes index_key to uppercase' do
      expect(redis).to receive(:lpush).with('edge_failure:rolling_window:NIFTY', anything)
      detector.record_trade_result(index_key: 'nifty', pnl_rupees: 0, exit_reason: 'manual')
    end

    it 'uses GLOBAL when index_key is nil' do
      expect(redis).to receive(:lpush).with('edge_failure:rolling_window:GLOBAL', anything)
      detector.record_trade_result(index_key: nil, pnl_rupees: 0, exit_reason: 'manual')
    end
  end

  describe '#clear_pause' do
    it 'clears only the specified index pause when index_key is given' do
      expect(redis).to receive(:del).with('edge_failure:pause:NIFTY')
      expect(redis).not_to receive(:scan_each)
      detector.clear_pause(index_key: 'NIFTY')
    end

    it 'clears all pauses when index_key is nil' do
      expect(redis).to receive(:scan_each).and_yield('edge_failure:pause:NIFTY').and_yield('edge_failure:pause:BANKNIFTY')
      expect(redis).to receive(:del).with('edge_failure:pause:NIFTY')
      expect(redis).to receive(:del).with('edge_failure:pause:BANKNIFTY')
      detector.clear_pause
    end

    it 'returns false when redis is unavailable' do
      detector = described_class.instance
      detector.instance_variable_set(:@redis, nil)
      expect(detector.clear_pause(index_key: 'NIFTY')).to be false
    end
  end

  describe 'session-based pause (S3 chop/decay)' do
    let(:session_config) do
      {
        risk: {
          edge_failure_detector: {
            enabled: true,
            rolling_window_size: 5,
            rolling_window_threshold_rupees: -3000,
            max_consecutive_sls: 5,           # high so consecutive breaker doesn't fire first
            pause_duration_minutes: 60,
            session_based_pause: true,
            s3_max_consecutive_sls: 2,
            s4_start_time: '13:45'
          }
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(session_config)
      allow(redis).to receive(:lrange).and_return([])
      allow(redis).to receive(:get).with('edge_failure:pause:NIFTY:session_s3_pause').and_return(nil)
    end

    context 'when in CHOP_DECAY regime with s3 consecutive SLs exceeded' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return(Live::TimeRegimeService::CHOP_DECAY)
        allow(redis).to receive(:get).with('edge_failure:consecutive_sl:NIFTY').and_return('2')
      end

      it 'pauses with session_s3_pause reason' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be true
        expect(result[:reason]).to eq('session_s3_pause')
        expect(result[:regime]).to eq(Live::TimeRegimeService::CHOP_DECAY.to_s)
      end
    end

    context 'when in CHOP_DECAY regime but SL count below s3 threshold' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return(Live::TimeRegimeService::CHOP_DECAY)
        allow(redis).to receive(:get).with('edge_failure:consecutive_sl:NIFTY').and_return('1')
      end

      it 'does not pause' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be false
      end
    end

    context 'when NOT in CHOP_DECAY regime' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return(:trend_continuation)
        # Use a low consecutive SL count so the consecutive_sls breaker doesn't fire either;
        # we are isolating the session-based pause logic.
        allow(redis).to receive(:get).with('edge_failure:consecutive_sl:NIFTY').and_return('1')
        allow(redis).to receive(:get).with('edge_failure:pause:NIFTY:consecutive_sls').and_return(nil)
      end

      it 'does not fire session_s3_pause (regime mismatch)' do
        result = detector.entries_paused?(index_key: 'NIFTY')
        expect(result[:paused]).to be false
      end
    end
  end
end
