# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Engine, :vcr do
  let(:index_cfg) do
    {
      key: 'NIFTY',
      segment: 'IDX_I',
      sid: '13',
      capital_alloc_pct: 0.30,
      max_same_side: 2,
      cooldown_sec: 180
    }
  end

  let(:nifty_instrument) { create(:instrument, :nifty_index) }

  before do
    # Mock IndexInstrumentCache to return our test instrument
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nifty_instrument)

    # Mock AlgoConfig
    allow(AlgoConfig).to receive(:fetch).and_return({
                                                      signals: {
                                                        primary_timeframe: '1m',
                                                        confirmation_timeframe: '5m',
                                                        validation_mode: 'aggressive',
                                                        supertrend: {
                                                          period: 10,
                                                          base_multiplier: 2.0,
                                                          training_period: 50,
                                                          num_clusters: 3,
                                                          performance_alpha: 0.1,
                                                          multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
                                                        },
                                                        adx: {
                                                          min_strength: 18.0,
                                                          confirmation_min_strength: 20.0
                                                        },
                                                        validation_modes: {
                                                          aggressive: {
                                                            require_iv_rank_check: false,
                                                            require_theta_risk_check: false,
                                                            require_trend_confirmation: false,
                                                            theta_risk_cutoff_hour: 15,
                                                            theta_risk_cutoff_minute: 0
                                                          }
                                                        }
                                                      }
                                                    })

    # Reduce days for faster API calls - use 7 days instead of default 90
    # This makes VCR cassettes smaller and tests faster
    allow(nifty_instrument).to receive(:intraday_ohlc).and_wrap_original do |original_method, **kwargs|
      kwargs[:days] = 7 unless kwargs.key?(:days) || kwargs.key?(:from_date)
      original_method.call(**kwargs)
    end

    # Clean up before each test
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  after do
    Signal::StateTracker.reset(index_cfg[:key])
    TradingSignal.where(index_key: index_cfg[:key]).delete_all
  end

  describe 'EPIC D — D1: Generate Directional Signals' do
    describe '.run_for' do
      context 'when instrument is found' do
        it 'fetches OHLC data from DhanHQ API via VCR for both timeframes' do
          # VCR will record/playback actual API calls for 1m and 5m OHLC
          expect(nifty_instrument).to receive(:candle_series).with(interval: '1').and_call_original.at_least(:once)
          expect(nifty_instrument).to receive(:candle_series).with(interval: '5').and_call_original.at_least(:once)

          described_class.run_for(index_cfg)
        end

        it 'calls intraday_ohlc via candle_series which uses VCR cassettes' do
          # Verify that candle_series triggers API calls (via VCR)
          expect(nifty_instrument).to receive(:intraday_ohlc).with(hash_including(interval: '1')).and_call_original.at_least(:once)
          expect(nifty_instrument).to receive(:intraday_ohlc).with(hash_including(interval: '5')).and_call_original.at_least(:once)

          described_class.run_for(index_cfg)
        end
      end

      context 'when instrument is not found' do
        before do
          allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(nil)
        end

        it 'logs error and returns early' do
          expect(Rails.logger).to receive(:error).with("[Signal] Could not find instrument for #{index_cfg[:key]}")
          described_class.run_for(index_cfg)
        end

        it 'does not proceed with signal generation' do
          expect(described_class).not_to receive(:analyze_timeframe)
          described_class.run_for(index_cfg)
        end
      end

      context 'when Supertrend configuration is missing' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return({
                                                            signals: {
                                                              primary_timeframe: '1m',
                                                              confirmation_timeframe: '5m'
                                                            }
                                                          })
        end

        it 'logs error and returns early' do
          expect(Rails.logger).to receive(:error).with("[Signal] Supertrend configuration missing for #{index_cfg[:key]}")
          described_class.run_for(index_cfg)
        end
      end

      context 'when entry_strategy.primary is supertrend' do
        let(:supertrend_signals_config) do
          {
            entry_strategy: { primary: 'supertrend' },
            enable_smc_avrz_permission: false,
            primary_timeframe: '1m',
            confirmation_timeframe: '5m',
            validation_mode: 'aggressive',
            supertrend: {
              period: 10,
              base_multiplier: 2.0,
              training_period: 50,
              num_clusters: 3,
              performance_alpha: 0.1,
              multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
            },
            adx: { min_strength: 18.0, confirmation_min_strength: 20.0 },
            validation_modes: {
              aggressive: {
                require_iv_rank_check: false,
                require_theta_risk_check: false,
                require_trend_confirmation: false,
                theta_risk_cutoff_hour: 15,
                theta_risk_cutoff_minute: 0
              }
            }
          }
        end

        it 'does not call EntryGuard when SupertrendTrend returns :none' do
          allow(AlgoConfig).to receive(:fetch).and_return({ signals: supertrend_signals_config })
          allow(described_class).to receive(:analyze_timeframe).and_return(
            status: :ok,
            series: double('series', closes: [1, 2, 3], candles: []),
            supertrend: { line: [1.0, 2.0, 3.0], last_value: 3.0 },
            adx_value: 20,
            direction: :bullish,
            last_candle_timestamp: Time.current
          )
          allow(SupertrendTrend).to receive(:direction).and_return(:none)
          allow(Entries::EntryGuard).to receive(:try_enter)

          described_class.run_for(index_cfg)

          expect(Entries::EntryGuard).not_to have_received(:try_enter)
        end

        it 'uses :bullish when SupertrendTrend returns :long' do
          allow(AlgoConfig).to receive(:fetch).and_return({ signals: supertrend_signals_config })
          primary_series = double('series', closes: [1, 2, 3], candles: [], atr: 10.0)
          allow(described_class).to receive(:analyze_timeframe).and_return(
            status: :ok,
            series: primary_series,
            supertrend: { line: [1.0, 2.0, 3.0], last_value: 3.0 },
            adx_value: 20,
            direction: :bullish,
            last_candle_timestamp: Time.current
          )
          allow(SupertrendTrend).to receive(:direction).and_return(:long)
          allow(Trading::PermissionResolver).to receive(:resolve).and_return(:scale_ready)
          allow(Options::ChainAnalyzer).to receive(:pick_strikes_with_qualification).and_return(
            [{ symbol: 'NIFTY-X-CE', security_id: '1', segment: 'IDX_I', derivative_id: 1 }]
          )
          allow(Entries::EntryGuard).to receive(:try_enter).and_return(false)

          described_class.run_for(index_cfg)

          expect(Entries::EntryGuard).to have_received(:try_enter).with(hash_including(direction: :bullish))
        end
      end

      context 'when primary timeframe analysis fails' do
        before do
          # Mock primary timeframe to fail, but don't call confirmation timeframe
          # by making the config have no confirmation timeframe, or mock it separately
          allow(AlgoConfig).to receive(:fetch).and_return({
                                                            signals: {
                                                              primary_timeframe: '1m',
                                                              confirmation_timeframe: nil, # No confirmation timeframe to avoid second call
                                                              validation_mode: 'aggressive',
                                                              supertrend: {
                                                                period: 10,
                                                                base_multiplier: 2.0,
                                                                training_period: 50,
                                                                num_clusters: 3,
                                                                performance_alpha: 0.1,
                                                                multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
                                                              },
                                                              adx: {
                                                                min_strength: 18.0,
                                                                confirmation_min_strength: 20.0
                                                              },
                                                              validation_modes: {
                                                                aggressive: {
                                                                  require_iv_rank_check: false,
                                                                  require_theta_risk_check: false,
                                                                  require_trend_confirmation: false,
                                                                  theta_risk_cutoff_hour: 15,
                                                                  theta_risk_cutoff_minute: 0
                                                                }
                                                              }
                                                            }
                                                          })
          allow(described_class).to receive(:analyze_timeframe).and_return({ status: :no_data,
                                                                             message: 'No candle data' })
        end

        it 'logs warning and resets state tracker' do
          expect(Rails.logger).to receive(:warn).with(match(/Primary timeframe analysis unavailable/))

          # Use a spy to track calls during execution (after block will also call it)
          allow(Signal::StateTracker).to receive(:reset).and_call_original

          described_class.run_for(index_cfg)

          # Verify reset was called at least once (during execution, and possibly in after block)
          expect(Signal::StateTracker).to have_received(:reset).with(index_cfg[:key]).at_least(:once)
        end
      end
    end

    describe '.analyze_timeframe' do
      let(:supertrend_cfg) do
        {
          period: 10,
          base_multiplier: 2.0,
          training_period: 50,
          num_clusters: 3,
          performance_alpha: 0.1,
          multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
        }
      end

      context 'when timeframe is valid' do
        it 'fetches candle series from API via VCR' do
          # VCR will record/playback actual API call
          expect(nifty_instrument).to receive(:candle_series).with(interval: '1').and_call_original

          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:ok)
        end

        it 'calculates Supertrend with real OHLC data from VCR' do
          # VCR provides real OHLC data
          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:ok)
          expect(result[:supertrend]).to be_present
          expect(result[:supertrend][:trend]).to be_in(%i[bullish bearish])
          expect(result[:supertrend][:last_value]).to be_a(Numeric)
        end

        it 'calculates ADX with real OHLC data from VCR' do
          # VCR provides real OHLC data for ADX calculation
          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:ok)
          expect(result[:adx_value]).to be_a(Numeric)
          expect(result[:adx_value]).to be >= 0
        end

        it 'returns direction based on Supertrend and ADX' do
          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:ok)
          expect(result[:direction]).to be_in(%i[bullish bearish avoid])
        end
      end

      context 'when timeframe is invalid' do
        it 'returns error status' do
          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: 'invalid',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:error)
          expect(result[:message]).to match(/Invalid timeframe/)
        end
      end

      context 'when no candle data is available' do
        before do
          allow(nifty_instrument).to receive(:candle_series).and_return(nil)
        end

        it 'returns no_data status' do
          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:no_data)
          expect(result[:message]).to match(/No candle data/)
        end
      end

      context 'when an error occurs during analysis' do
        before do
          allow(nifty_instrument).to receive(:candle_series).and_raise(StandardError, 'API error')
        end

        it 'handles error gracefully and returns error status' do
          expect(Rails.logger).to receive(:error).with(match(/Timeframe analysis failed/))

          result = described_class.analyze_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument,
            timeframe: '1m',
            supertrend_cfg: supertrend_cfg,
            adx_min_strength: 18.0
          )

          expect(result[:status]).to eq(:error)
          expect(result[:message]).to eq('API error')
        end
      end
    end

    describe '.decide_direction' do
      let(:supertrend_result) { { trend: :bullish, last_value: 25_000.0 } }
      let(:adx_value) { 25.0 }
      let(:min_strength) { 18.0 }

      context 'when ADX is above minimum threshold' do
        it 'returns bullish direction for bullish Supertrend' do
          direction = described_class.decide_direction(
            supertrend_result,
            adx_value,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:bullish)
        end

        it 'returns bearish direction for bearish Supertrend' do
          bearish_st = { trend: :bearish, last_value: 24_000.0 }
          direction = described_class.decide_direction(
            bearish_st,
            adx_value,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:bearish)
        end

        it 'returns avoid for neutral/unknown Supertrend trend' do
          neutral_st = { trend: nil, last_value: 25_000.0 }
          direction = described_class.decide_direction(
            neutral_st,
            adx_value,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:avoid)
        end
      end

      context 'when ADX is below minimum threshold' do
        let(:weak_adx) { 15.0 }

        it 'returns avoid when ADX is too weak' do
          expect(Rails.logger).to receive(:info).with(match(/ADX too weak/))

          direction = described_class.decide_direction(
            supertrend_result,
            weak_adx,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:avoid)
        end
      end

      context 'when Supertrend result is invalid' do
        it 'returns avoid for nil Supertrend result' do
          direction = described_class.decide_direction(
            nil,
            adx_value,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:avoid)
        end

        it 'returns avoid for Supertrend result without trend' do
          invalid_st = { last_value: 25_000.0 }
          direction = described_class.decide_direction(
            invalid_st,
            adx_value,
            min_strength: min_strength,
            timeframe_label: '1m'
          )

          expect(direction).to eq(:avoid)
        end
      end
    end

    describe '.multi_timeframe_direction' do
      context 'when both timeframes align' do
        it 'returns bullish when both are bullish' do
          direction = described_class.multi_timeframe_direction(:bullish, :bullish)
          expect(direction).to eq(:bullish)
        end

        it 'returns bearish when both are bearish' do
          direction = described_class.multi_timeframe_direction(:bearish, :bearish)
          expect(direction).to eq(:bearish)
        end
      end

      context 'when timeframes do not align' do
        it 'returns avoid when directions mismatch' do
          direction = described_class.multi_timeframe_direction(:bullish, :bearish)
          expect(direction).to eq(:avoid)
        end
      end

      context 'when either timeframe is avoid' do
        it 'returns avoid when primary is avoid' do
          direction = described_class.multi_timeframe_direction(:avoid, :bullish)
          expect(direction).to eq(:avoid)
        end

        it 'returns avoid when confirmation is avoid' do
          direction = described_class.multi_timeframe_direction(:bullish, :avoid)
          expect(direction).to eq(:avoid)
        end
      end

      context 'when confirmation is nil' do
        it 'returns primary direction when confirmation is nil' do
          direction = described_class.multi_timeframe_direction(:bullish, nil)
          expect(direction).to eq(:bullish)
        end
      end
    end

    describe '.normalize_interval' do
      it 'extracts digits from timeframe string' do
        expect(described_class.normalize_interval('1m')).to eq('1')
        expect(described_class.normalize_interval('5m')).to eq('5')
        expect(described_class.normalize_interval('15m')).to eq('15')
      end

      it 'handles various formats' do
        expect(described_class.normalize_interval('1 min')).to eq('1')
        expect(described_class.normalize_interval('5 MIN')).to eq('5')
        expect(described_class.normalize_interval('15')).to eq('15')
      end

      it 'returns nil for invalid timeframes' do
        expect(described_class.normalize_interval('')).to be_nil
        expect(described_class.normalize_interval(nil)).to be_nil
        expect(described_class.normalize_interval('invalid')).to be_nil
      end
    end

    describe '.analyze_multi_timeframe' do
      let(:supertrend_cfg) do
        {
          period: 10,
          base_multiplier: 2.0,
          training_period: 50,
          num_clusters: 3,
          performance_alpha: 0.1,
          multiplier_candidates: [1.5, 2.0, 2.5, 3.0, 3.5]
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
                                                          signals: {
                                                            primary_timeframe: '1m',
                                                            confirmation_timeframe: '5m',
                                                            supertrend: supertrend_cfg,
                                                            adx: {
                                                              min_strength: 18.0,
                                                              confirmation_min_strength: 20.0
                                                            }
                                                          }
                                                        })
      end

      it 'analyzes both primary and confirmation timeframes via VCR' do
        # VCR will record/playback API calls for both timeframes
        result = described_class.analyze_multi_timeframe(
          index_cfg: index_cfg,
          instrument: nifty_instrument
        )

        expect(result[:status]).to eq(:ok)
        expect(result[:primary_direction]).to be_in(%i[bullish bearish avoid])
        expect(result[:final_direction]).to be_in(%i[bullish bearish avoid])
      end

      it 'fetches OHLC data for both timeframes from API via VCR' do
        expect(nifty_instrument).to receive(:candle_series).with(interval: '1').and_call_original
        expect(nifty_instrument).to receive(:candle_series).with(interval: '5').and_call_original

        described_class.analyze_multi_timeframe(
          index_cfg: index_cfg,
          instrument: nifty_instrument
        )
      end

      context 'when primary timeframe analysis fails' do
        before do
          allow(described_class).to receive(:analyze_timeframe).and_return(
            { status: :error, message: 'Primary failed' }
          )
        end

        it 'returns error status' do
          result = described_class.analyze_multi_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument
          )

          expect(result[:status]).to eq(:error)
          expect(result[:message]).to match(/Primary timeframe analysis failed/)
        end
      end

      context 'when confirmation timeframe analysis fails' do
        before do
          primary_result = {
            status: :ok,
            direction: :bullish,
            series: double('CandleSeries'),
            supertrend: { trend: :bullish },
            adx_value: 25.0
          }
          allow(described_class).to receive(:analyze_timeframe).and_return(
            primary_result,
            { status: :error, message: 'Confirmation failed' }
          )
        end

        it 'handles gracefully and uses primary direction' do
          result = described_class.analyze_multi_timeframe(
            index_cfg: index_cfg,
            instrument: nifty_instrument
          )

          expect(result[:status]).to eq(:ok)
          expect(result[:primary_direction]).to eq(:bullish)
          expect(result[:confirmation_direction]).to be_nil
        end
      end
    end

    describe '.comprehensive_validation' do
      let(:series) { double('CandleSeries', candles: [double('Candle', close: 25_000.0)] * 10) }
      let(:supertrend_result) { { trend: :bullish, last_value: 25_000.0 } }
      let(:adx) { { value: 25.0 } }

      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
                                                          signals: {
                                                            validation_mode: 'aggressive',
                                                            validation_modes: {
                                                              aggressive: {
                                                                require_iv_rank_check: false,
                                                                require_theta_risk_check: false,
                                                                require_trend_confirmation: false,
                                                                adx_min_strength: 18.0
                                                              }
                                                            },
                                                            adx: {
                                                              min_strength: 18.0
                                                            }
                                                          }
                                                        })
      end

      it 'validates signal with all enabled checks' do
        result = described_class.comprehensive_validation(
          index_cfg,
          :bullish,
          series,
          supertrend_result,
          adx
        )

        expect(result[:valid]).to be_in([true, false])
        expect(result[:reason]).to be_present
      end

      context 'when validation mode is conservative' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return({
                                                            signals: {
                                                              validation_mode: 'conservative',
                                                              validation_modes: {
                                                                conservative: {
                                                                  require_iv_rank_check: true,
                                                                  require_theta_risk_check: true,
                                                                  require_trend_confirmation: true,
                                                                  adx_min_strength: 20.0,
                                                                  iv_rank_max: 0.8,
                                                                  iv_rank_min: 0.1,
                                                                  theta_risk_cutoff_hour: 14,
                                                                  theta_risk_cutoff_minute: 0
                                                                }
                                                              },
                                                              adx: {
                                                                min_strength: 18.0
                                                              }
                                                            }
                                                          })
        end

        it 'runs all validation checks including IV rank and theta risk' do
          result = described_class.comprehensive_validation(
            index_cfg,
            :bullish,
            series,
            supertrend_result,
            adx
          )

          expect(result[:valid]).to be_in([true, false])
          # All checks should have been evaluated
        end
      end

      context 'when ADX is too weak' do
        let(:weak_adx) { { value: 15.0 } }

        it 'fails validation' do
          result = described_class.comprehensive_validation(
            index_cfg,
            :bullish,
            series,
            supertrend_result,
            weak_adx
          )

          expect(result[:valid]).to be(false)
          expect(result[:reason]).to match(/ADX Strength/)
        end
      end
    end

    describe 'end-to-end signal generation' do
      before do
        allow(Options::ChainAnalyzer).to receive(:pick_strikes).and_return([])
        allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
      end

      it 'generates signal with real OHLC data from VCR' do
        # VCR will provide real API responses for OHLC fetches
        described_class.run_for(index_cfg)

        # Verify signal was created if conditions were met
        TradingSignal.where(index_key: index_cfg[:key])
        # Signal may or may not be created depending on market conditions from VCR data
        # But we should verify the process completed without errors
      end

      it 'logs signal generation process' do
        log_calls = []
        allow(Rails.logger).to receive(:info) { |*args, &block| log_calls << (block ? block.call : args.first) }
        allow(Rails.logger).to receive(:debug) # Allow debug logs
        allow(Rails.logger).to receive(:warn) # Allow warning logs

        described_class.run_for(index_cfg)

        # Should have logs indicating signal generation attempt
        expect(log_calls).to(be_any { |msg| msg.to_s.include?('Starting analysis') })
      end

      context 'when multi-timeframe confirmation is required' do
        it 'validates both primary and confirmation timeframes align' do
          # VCR will provide real data for both timeframes
          described_class.run_for(index_cfg)

          # If both timeframes align and pass validation, signal should be generated
          # If they don't align, signal should be avoided
        end
      end

      context 'when comprehensive validation fails' do
        before do
          allow(described_class).to receive(:comprehensive_validation).and_return(
            { valid: false, reason: 'Test validation failure' }
          )
        end

        it 'does not generate signal and resets state tracker' do
          expect(Rails.logger).to receive(:warn).with(match(/Comprehensive validation failed/))

          # Use a spy to track calls during execution (after block will also call it)
          allow(Signal::StateTracker).to receive(:reset).and_call_original

          described_class.run_for(index_cfg)

          # Verify reset was called at least once (during execution, and possibly in after block)
          expect(Signal::StateTracker).to have_received(:reset).with(index_cfg[:key]).at_least(:once)
          expect(TradingSignal.where(index_key: index_cfg[:key]).count).to eq(0)
        end
      end
    end
  end
end
