# frozen_string_literal: true

require 'rails_helper'

# Wave 3 of the error-handling review: the risk manager's config layer must
# never silently degrade to defaults. A corrupt config document propagates
# (enforcement cycles log-and-isolate); documented defaults apply ONLY to
# absent keys; an operator's explicit values are honoured exactly.
RSpec.describe Live::RiskManagerService, '#config strictness (wave 3)' do
  let(:service) { described_class.new(exit_engine: nil) }
  # Default: a valid (empty) document — contexts override; the corrupt
  # context re-stubs fetch to raise inside its examples.
  let(:config) { {} }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(config)
  end

  subject(:risk_config) { service.send(:risk_config) }

  context 'with a healthy config document' do
    let(:config) do
      {
        risk: {
          sl_pct: 0.10,
          tp_pct: 0.30,
          trail_step_pct: 0.05,
          etf: { enabled: true, activation_profit_pct: 0.07 }
        },
        realtime: { tick_stale_after_seconds: 5, min_enforcement_gap_ms: 100 }
      }
    end

    it 'resolves aliases and honours explicit values' do
      expect(risk_config[:sl_pct]).to eq(0.10)
      expect(risk_config[:stop_loss_pct]).to eq(0.10)
      expect(risk_config[:tp_pct]).to eq(0.30)
      expect(risk_config[:trail_step_pct]).to eq(0.05)
    end

    it 'honours the explicit staleness window and enforcement gap' do
      expect(service.send(:realtime_tick_stale_after_seconds)).to eq(5.0)
      expect(service.send(:realtime_min_enforcement_gap_seconds)).to eq(0.1)
    end
  end

  context 'with a corrupt config document' do
    # The service pins config at boot (@algo_config memo) — the real safety
    # property is that a corrupt document refuses to start the service at
    # all (it used to boot on {} and select the LIVE gateway).
    it 'refuses to start instead of booting on a fabricated empty config' do
      allow(AlgoConfig).to receive(:fetch).and_raise(Errors::ConfigurationError, 'corrupt algo.yml')
      expect { described_class.new(exit_engine: nil) }.to raise_error(Errors::ConfigurationError)
    end

    it 'propagates from risk_config instead of reading as "no risk config" (post-boot corruption)' do
      service # boot on the healthy stub
      allow(AlgoConfig).to receive(:fetch).and_raise(Errors::ConfigurationError, 'corrupt algo.yml')
      service.instance_variable_set(:@algo_config, nil) # clear the boot-time memo
      expect { risk_config }.to raise_error(Errors::ConfigurationError)
    end

    it 'propagates from post_profit_zone_config instead of running the layer on manufactured thresholds' do
      service
      allow(AlgoConfig).to receive(:fetch).and_raise(Errors::ConfigurationError, 'corrupt algo.yml')
      service.instance_variable_set(:@algo_config, nil)
      expect { service.send(:post_profit_zone_config) }.to raise_error(Errors::ConfigurationError)
    end

    it 'propagates from the early-trend-failure layer instead of disabling it' do
      service
      allow(AlgoConfig).to receive(:fetch).and_raise(Errors::ConfigurationError, 'corrupt algo.yml')
      service.instance_variable_set(:@algo_config, nil)
      expect { service.send(:enforce_early_trend_failure, exit_engine: nil) }
        .to raise_error(Errors::ConfigurationError)
    end
  end

  describe 'absent-key defaults' do
    let(:config) { {} }

    it 'returns an empty risk config (documented no-config outcome)' do
      expect(risk_config).to eq({})
    end

    it 'keeps exit layers on their documented default-enabled state' do
      expect(service.send(:structure_invalidation_enabled?)).to be(true)
      expect(service.send(:premium_momentum_failure_enabled?)).to be(true)
      expect(service.send(:time_stop_enabled?)).to be(true)
    end

    it 'uses the documented staleness/gap defaults' do
      expect(service.send(:realtime_tick_stale_after_seconds)).to eq(3.0)
      expect(service.send(:realtime_min_enforcement_gap_seconds)).to eq(0.25)
    end
  end

  describe 'explicit-but-invalid values' do
    let(:config) { { realtime: realtime_cfg } }

    context 'tick_stale_after_seconds is garbage' do
      let(:realtime_cfg) { { tick_stale_after_seconds: 'soon' } }

      it 'raises instead of silently reverting to 3.0s' do
        expect { service.send(:realtime_tick_stale_after_seconds) }
          .to raise_error(Errors::ConfigurationError, /tick_stale_after_seconds/)
      end
    end

    context 'tick_stale_after_seconds is zero' do
      let(:realtime_cfg) { { tick_stale_after_seconds: 0 } }

      it 'raises (a zero window is not a valid staleness bound)' do
        expect { service.send(:realtime_tick_stale_after_seconds) }
          .to raise_error(Errors::ConfigurationError, /must be > 0/)
      end
    end

    context 'min_enforcement_gap_ms is explicitly zero' do
      let(:realtime_cfg) { { min_enforcement_gap_ms: 0 } }

      it 'honours the operator choice: throttle disabled (used to snap back to 0.25s)' do
        expect(service.send(:realtime_min_enforcement_gap_seconds)).to eq(0.0)
      end
    end

    context 'min_enforcement_gap_ms is negative' do
      let(:realtime_cfg) { { min_enforcement_gap_ms: -5 } }

      it 'raises' do
        expect { service.send(:realtime_min_enforcement_gap_seconds) }
          .to raise_error(Errors::ConfigurationError, /must be >= 0/)
      end
    end
  end
end
