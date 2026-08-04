# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Signal::Engine do
  before do
    allow_any_instance_of(Object).to receive(:fetch_authority_token!).and_return('dummy_token')
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)
    allow(Market::Calendar).to receive_messages(trading_day_today?: true, today_or_last_trading_day: Date.parse('2025-10-31'), trading_days_ago: Date.parse('2025-10-24'))
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)
    allow(AlgoConfig).to receive(:fetch).and_return(supertrend_signals_config)
    allow(nifty_instrument).to receive(:intraday_ohlc).and_wrap_original do |original_method, **kwargs|
      kwargs[:days] = 7 unless kwargs.key?(:days) || kwargs.key?(:from_date)
      original_method.call(**kwargs)
    end
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
    dummy_detector = instance_double(MarketRegimeDetector)
    allow(dummy_detector).to receive(:detect).and_return({ regime: 'TRENDING_UP', confidence: 85.0, metrics: {} })
    allow(MarketRegimeDetector).to receive(:new).with(any_args).and_return(dummy_detector)
    entry_filter = instance_double(Entries::EntryFilterEngine, valid_entry?: true)
    allow(Entries::EntryFilterEngine).to receive(:new).and_return(entry_filter)
  end

  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13', capital_alloc_pct: 0.30, max_same_side: 2, cooldown_sec: 180 } }
  let(:nifty_instrument) { create(:instrument, :nifty_index) }
  let(:supertrend_signals_config) do
    { signals: {
        primary_timeframe: '1m',
        confirmation_timeframe: '5m',
        entry_strategy: { primary: 'supertrend' },
        validation_mode: 'aggressive',
        supertrend: { period: 10, base_multiplier: 2.0, training_period: 50, num_clusters: 3, performance_alpha: 0.1, multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5] },
        adx: { min_strength: 18.0, confirmation_min_strength: 20.0 },
        validation_modes: { aggressive: { require_iv_rank_check: false, require_theta_risk_check: false, require_trend_confirmation: false, theta_risk_cutoff_hour: 15, theta_risk_cutoff_minute: 0 } },
        enable_direction_gate: false
      } }
  end

  it 'traces :long flow' do
    primary_series = double('series', closes: [1, 2, 3], candles: [], atr: 10.0)
    allow(described_class).to receive(:analyze_timeframe).and_return(
      status: :ok, series: primary_series, supertrend: { line: [1.0, 2.0, 3.0], last_value: 3.0 },
      adx_value: 20, direction: :bullish, last_candle_timestamp: Time.current
    )
    allow(SupertrendTrend).to receive(:direction).and_return(:long)
    allow(Trading::PermissionResolver).to receive(:resolve).and_return(:scale_ready)
    allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return([{ symbol: 'NIFTY-X-CE', security_id: '1', segment: 'IDX_I', derivative_id: 1 }])
    allow(Entries::EntryGuard).to receive(:try_enter).and_return(false)

    log_lines = []
    allow(Rails.logger).to receive(:info) { |msg| log_lines << "[INFO] #{msg}" }
    allow(Rails.logger).to receive(:warn) { |msg| log_lines << "[WARN] #{msg}" }
    allow(Rails.logger).to receive(:error) { |msg| log_lines << "[ERROR] #{msg}" }
    allow(Rails.logger).to receive(:fatal) { |msg| log_lines << "[FATAL] #{msg}" }
    allow(Rails.logger).to receive(:debug) { |msg| log_lines << "[DEBUG] #{msg}" }

    described_class.run_for(index_cfg)
    puts "=== FLOW LOG ==="
    log_lines.first(80).each { |l| puts l }
  end
end
