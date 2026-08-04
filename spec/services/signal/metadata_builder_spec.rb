# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::MetadataBuilder do
  describe '.build' do
    let(:primary_analysis) do
      { adx_value: 45.0, supertrend: { last_value: 22_500.0 }, direction: :bearish }
    end

    let(:signals_cfg) { { validation_mode: 'exit_testing' } }

    context 'when ta_result has nested indicators with timeframe data' do
      let(:ta_result) do
        {
          signal: :bearish,
          confidence: 0.72,
          bias_summary: { summary: { bias: 'bearish' } },
          indicators: {
            meta: { exchange_segment: 'IDX_I', security_id: '13' },
            indicators: {
              m5:  { rsi: 62.1, macd: { macd: 1.2, signal: 0.8, hist: 0.4 }, atr: 45.0 },
              m15: { rsi: 58.4, macd: { macd: 0.9, signal: 0.7, hist: 0.2 }, atr: 52.0 },
              m60: { rsi: 55.0, macd: { macd: 0.5, signal: 0.3, hist: 0.2 }, atr: 60.0 }
            }
          }
        }
      end

      subject(:metadata) do
        described_class.build(
          primary_analysis: primary_analysis,
          regime: 'TRENDING_DOWN',
          regime_result: { confidence: 0.8, metrics: {} },
          ta_result: ta_result,
          options_analysis: nil,
          validation_result: { valid: true },
          state_snapshot: { count: 1, multiplier: 1 },
          effective_validation_mode: 'balanced',
          signals_cfg: signals_cfg,
          primary_tf: '5m',
          effective_timeframe: '5m',
          confirmation_tf: nil,
          enable_confirmation: false,
          smc_decision: :put,
          permission: :scale_ready,
          confirmation_analysis: nil
        )
      end

      it 'extracts RSI per timeframe from the nested indicators path' do
        expect(metadata[:mtf_rsi]).to eq({ m5: 62.1, m15: 58.4, m60: 55.0 })
      end

      it 'extracts MACD per timeframe from the nested indicators path' do
        expect(metadata[:mtf_macd]).to eq({
                                            m5:  { macd: 1.2, signal: 0.8, hist: 0.4 },
                                            m15: { macd: 0.9, signal: 0.7, hist: 0.2 },
                                            m60: { macd: 0.5, signal: 0.3, hist: 0.2 }
                                          })
      end

      it 'extracts ATR per timeframe from the nested indicators path' do
        expect(metadata[:mtf_atr]).to eq({ m5: 45.0, m15: 52.0, m60: 60.0 })
      end

      it 'does not produce the meta/indicators wrapper as the value' do
        expect(metadata[:mtf_rsi]).not_to eq({ meta: nil, indicators: nil })
        expect(metadata[:mtf_rsi]).not_to include(:meta)
      end
    end

    context 'when ta_result is nil' do
      subject(:metadata) do
        described_class.build(
          primary_analysis: primary_analysis,
          regime: 'EXIT_TESTING',
          regime_result: { confidence: 0, metrics: {} },
          ta_result: nil,
          options_analysis: nil,
          validation_result: { valid: true },
          state_snapshot: { count: 1, multiplier: 1 },
          effective_validation_mode: 'exit_testing',
          signals_cfg: signals_cfg,
          primary_tf: '1m',
          effective_timeframe: '1m',
          confirmation_tf: nil,
          enable_confirmation: false,
          smc_decision: :put,
          permission: :exit_testing,
          confirmation_analysis: nil
        )
      end

      it 'returns nil for mtf fields without crashing' do
        expect(metadata[:mtf_rsi]).to be_nil
        expect(metadata[:mtf_macd]).to be_nil
        expect(metadata[:mtf_atr]).to be_nil
      end
    end
  end
end
