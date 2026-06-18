# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig::Validator do
  describe '.validate!' do
    let(:valid_config) do
      {
        entry_quality: { min_score: 50, gates: { min_adx: 22, min_body_ratio: 0.38 } },
        signals: {
          min_confidence: 70,
          signal_tier: 'standard',
          entry_dte_guard: { reject_when_days_to_expiry_lte: -1 }
        },
        option_chain: { min_strike_score: 125.0 },
        risk: { sl_pct: 0.02 }
      }
    end

    context 'when every value is within range' do
      it 'returns true' do
        expect(described_class.validate!(valid_config)).to be(true)
      end
    end

    context 'when a key is absent' do
      it 'skips the rule and does not raise' do
        expect(described_class.validate!({ risk: { sl_pct: 0.02 } })).to be(true)
      end
    end

    context 'when min_adx is below its range' do
      it 'raises with a reason naming the offending path' do
        config = valid_config.deep_merge(entry_quality: { gates: { min_adx: -5 } })

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /min_adx/)
      end
    end

    context 'when min_score exceeds its range' do
      it 'raises a ValidationError' do
        config = valid_config.deep_merge(entry_quality: { min_score: 250 })

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /min_score/)
      end
    end

    context 'when min_body_ratio exceeds 1.0' do
      it 'raises a ValidationError' do
        config = valid_config.deep_merge(entry_quality: { gates: { min_body_ratio: 1.5 } })

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /min_body_ratio/)
      end
    end

    context 'when signal_tier is not an allowed value' do
      it 'raises a ValidationError' do
        config = valid_config.deep_merge(signals: { signal_tier: 'wild' })

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /signal_tier/)
      end
    end

    context 'when entry_dte_guard threshold is outside the integer range' do
      it 'raises a ValidationError' do
        config = valid_config.deep_merge(
          signals: { entry_dte_guard: { reject_when_days_to_expiry_lte: 99 } }
        )

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /reject_when_days_to_expiry_lte/)
      end
    end

    context 'when a numeric gate receives a non-numeric value' do
      it 'raises a ValidationError' do
        config = valid_config.deep_merge(entry_quality: { min_score: 'high' })

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError, /min_score/)
      end
    end

    context 'when an out-of-range value sits under an unchanged top-level key' do
      it 'does not raise when that key is outside changed_paths' do
        config = valid_config.deep_merge(signals: { min_confidence: 999 })

        expect(described_class.validate!(config, changed_paths: ['/risk'])).to be(true)
      end

      it 'raises when the key is within changed_paths' do
        config = valid_config.deep_merge(signals: { min_confidence: 999 })

        expect { described_class.validate!(config, changed_paths: ['/signals']) }
          .to raise_error(AlgoConfig::ValidationError, /min_confidence/)
      end
    end

    context 'when changed_paths is a forced-bootstrap sentinel' do
      it 'validates the whole document' do
        config = valid_config.deep_merge(entry_quality: { min_score: 250 })

        expect { described_class.validate!(config, changed_paths: ['/__forced_bootstrap__']) }
          .to raise_error(AlgoConfig::ValidationError, /min_score/)
      end
    end

    context 'when multiple values are invalid' do
      it 'reports every offending path in the error' do
        config = valid_config.deep_merge(
          entry_quality: { min_score: 250, gates: { min_adx: -5 } }
        )

        expect { described_class.validate!(config) }
          .to raise_error(AlgoConfig::ValidationError) { |e| expect(e.errors.size).to be >= 2 }
      end
    end
  end
end
