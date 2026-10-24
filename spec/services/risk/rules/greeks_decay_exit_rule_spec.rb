# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::GreeksDecayExitRule do
  subject(:rule) { described_class.new(config: {}) }

  let(:context) { instance_double(Risk::Rules::RuleContext, active?: true) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        greeks_decay_exit: { enabled: true }
      }
    )
  end

  it 'exposes enabled? to RuleEngine' do
    expect(rule.enabled?(context)).to be(true)
  end

  context 'when disabled in config' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: {
          greeks_decay_exit: { enabled: false }
        }
      )
    end

    it 'returns false from enabled?' do
      expect(rule.enabled?(context)).to be(false)
    end
  end
end
