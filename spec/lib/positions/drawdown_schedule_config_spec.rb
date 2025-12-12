# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::DrawdownSchedule, 'configuration variations' do
  describe '.allowed_upward_drawdown_pct with different configs' do
    context 'conservative configuration' do
      let(:config) do
        {
          risk: {
            drawdown: {
              activation_profit_pct: 3.0,
              profit_min: 3.0,
              profit_max: 30.0,
              dd_start_pct: 10.0, # Tighter start
              dd_end_pct: 0.5,    # Tighter end
              exponential_k: 5.0,  # Steeper curve
              index_floors: {
                'NIFTY' => 0.5,
                'BANKNIFTY' => 0.7
              }
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns tighter drawdowns' do
        dd_5 = described_class.allowed_upward_drawdown_pct(5.0, index_key: 'NIFTY')
        dd_10 = described_class.allowed_upward_drawdown_pct(10.0, index_key: 'NIFTY')
        dd_30 = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'NIFTY')

        expect(dd_5).to be < 10.0  # Tighter than start
        expect(dd_10).to be < 5.0  # Tighter than mid
        expect(dd_30).to be >= 0.5 # Respects floor
      end
    end

    context 'aggressive configuration' do
      let(:config) do
        {
          risk: {
            drawdown: {
              activation_profit_pct: 3.0,
              profit_min: 3.0,
              profit_max: 30.0,
              dd_start_pct: 20.0, # Wider start
              dd_end_pct: 2.0,    # Wider end
              exponential_k: 2.0,  # Gentler curve
              index_floors: {
                'NIFTY' => 2.0,
                'BANKNIFTY' => 2.5
              }
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns wider drawdowns' do
        dd_5 = described_class.allowed_upward_drawdown_pct(5.0, index_key: 'NIFTY')
        dd_10 = described_class.allowed_upward_drawdown_pct(10.0, index_key: 'NIFTY')
        dd_30 = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'NIFTY')

        expect(dd_5).to be > 10.0  # Wider than conservative
        expect(dd_10).to be > 5.0  # Wider than conservative
        expect(dd_30).to be >= 2.0 # Respects floor
      end
    end

    context 'with missing config' do
      let(:config) { {} }

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'uses default values' do
        dd = described_class.allowed_upward_drawdown_pct(5.0)
        expect(dd).to be_a(Numeric)
        expect(dd).to be > 0
      end
    end

    context 'with invalid config values' do
      let(:config) do
        {
          risk: {
            drawdown: {
              profit_min: nil,
              profit_max: nil,
              dd_start_pct: nil,
              dd_end_pct: nil,
              exponential_k: nil
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'uses default values gracefully' do
        dd = described_class.allowed_upward_drawdown_pct(5.0)
        expect(dd).to be_a(Numeric)
      end
    end
  end

  describe '.reverse_dynamic_sl_pct with different configs' do
    context 'conservative reverse SL' do
      let(:config) do
        {
          risk: {
            reverse_loss: {
              enabled: true,
              max_loss_pct: 15.0,  # Tighter max
              min_loss_pct: 3.0,   # Tighter min
              loss_span_pct: 30.0,
              time_tighten_per_min: 3.0, # Faster tightening
              atr_penalty_thresholds: [
                { threshold: 0.80, penalty_pct: 2.0 },
                { threshold: 0.65, penalty_pct: 4.0 }
              ]
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns tighter loss allowances' do
        sl_5 = described_class.reverse_dynamic_sl_pct(-5.0)
        sl_15 = described_class.reverse_dynamic_sl_pct(-15.0)
        sl_30 = described_class.reverse_dynamic_sl_pct(-30.0)

        expect(sl_5).to be < 20.0  # Tighter than default max
        expect(sl_15).to be < 10.0 # Tighter than default mid
        expect(sl_30).to be >= 3.0 # Respects min
      end

      it 'applies time tightening faster' do
        sl_no_time = described_class.reverse_dynamic_sl_pct(-10.0, seconds_below_entry: 0)
        sl_2min = described_class.reverse_dynamic_sl_pct(-10.0, seconds_below_entry: 120)

        expect(sl_2min).to be < sl_no_time
        expect(sl_2min).to be_within(10.0).of(sl_no_time - 6.0) # 2 min * 3% per min
      end
    end

    context 'aggressive reverse SL' do
      let(:config) do
        {
          risk: {
            reverse_loss: {
              enabled: true,
              max_loss_pct: 25.0,  # Wider max
              min_loss_pct: 7.0,   # Wider min
              loss_span_pct: 30.0,
              time_tighten_per_min: 1.0, # Slower tightening
              atr_penalty_thresholds: [
                { threshold: 0.70, penalty_pct: 2.0 },
                { threshold: 0.50, penalty_pct: 4.0 }
              ]
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns wider loss allowances' do
        sl_5 = described_class.reverse_dynamic_sl_pct(-5.0)
        sl_15 = described_class.reverse_dynamic_sl_pct(-15.0)
        sl_30 = described_class.reverse_dynamic_sl_pct(-30.0)

        expect(sl_5).to be > 15.0  # Wider than conservative
        expect(sl_15).to be > 7.0  # Wider than conservative
        expect(sl_30).to be >= 7.0 # Respects min
      end
    end

    context 'when reverse_loss is disabled' do
      let(:config) do
        {
          risk: {
            reverse_loss: {
              enabled: false,
              max_loss_pct: 20.0,
              min_loss_pct: 5.0
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns nil' do
        expect(described_class.reverse_dynamic_sl_pct(-10.0)).to be_nil
      end
    end

    context 'with missing config' do
      let(:config) { {} }

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'returns nil when disabled' do
        expect(described_class.reverse_dynamic_sl_pct(-10.0)).to be_nil
      end
    end

    context 'ATR penalty thresholds' do
      let(:config) do
        {
          risk: {
            reverse_loss: {
              enabled: true,
              max_loss_pct: 20.0,
              min_loss_pct: 5.0,
              loss_span_pct: 30.0,
              atr_penalty_thresholds: [
                { threshold: 0.75, penalty_pct: 3.0 },
                { threshold: 0.60, penalty_pct: 5.0 },
                { threshold: 0.40, penalty_pct: 8.0 } # Additional threshold
              ]
            }
          }
        }
      end

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(config)
      end

      it 'applies correct penalty for each threshold' do
        sl_normal = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 1.0)
        sl_075 = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 0.70)
        sl_060 = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 0.55)
        sl_040 = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 0.35)

        expect(sl_075).to be < sl_normal
        expect(sl_060).to be < sl_075
        expect(sl_040).to be < sl_060
      end
    end
  end

  describe 'index-specific floors' do
    let(:config) do
      {
        risk: {
          drawdown: {
            activation_profit_pct: 3.0,
            profit_min: 3.0,
            profit_max: 30.0,
            dd_start_pct: 15.0,
            dd_end_pct: 1.0,
            exponential_k: 3.0,
            index_floors: {
              'NIFTY' => 1.0,
              'BANKNIFTY' => 1.2,
              'SENSEX' => 1.5,
              'FINNIFTY' => 0.8
            }
          }
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(config)
    end

    it 'respects NIFTY floor' do
      dd = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'NIFTY')
      expect(dd).to be >= 1.0
    end

    it 'respects BANKNIFTY floor' do
      dd = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'BANKNIFTY')
      expect(dd).to be >= 1.2
    end

    it 'respects SENSEX floor' do
      dd = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'SENSEX')
      expect(dd).to be >= 1.5
    end

    it 'uses default floor for unknown index' do
      dd = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'UNKNOWN')
      expect(dd).to be >= 1.0 # Uses dd_end_pct as default
    end
  end
end
