# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::GatewayFactory do
  describe '.build' do
    context 'when paper_mode is explicitly provided' do
      it 'returns GatewayPaper when paper_mode is true' do
        expect(described_class.build(paper_mode: true)).to be_a(Orders::GatewayPaper)
      end

      it 'returns GatewayLive when paper_mode is false' do
        expect(described_class.build(paper_mode: false)).to be_a(Orders::GatewayLive)
      end
    end

    context 'when paper_mode is derived from config' do
      it 'returns GatewayPaper when config has paper_trading: true' do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
        expect(described_class.build).to be_a(Orders::GatewayPaper)
      end

      it 'returns GatewayLive when config has paper_trading: false' do
        allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: false } })
        expect(described_class.build).to be_a(Orders::GatewayLive)
      end

      it 'defaults to GatewayPaper when config fetch fails' do
        allow(AlgoConfig).to receive(:fetch).and_raise(StandardError, "Config error")
        expect(described_class.build).to be_a(Orders::GatewayPaper)
      end
    end
  end
end
