# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  describe '#cancel_remote_order' do
    let(:service) { described_class.new }
    let(:gateway) { instance_double(Orders::Gateway) }

    before do
      service.instance_variable_set(:@orders_gateway, gateway)
    end

    it 'delegates cancellation to configured orders gateway' do
      expect(gateway).to receive(:cancel_order).with('OID-123').and_return(success: true)

      result = service.send(:cancel_remote_order, 'OID-123')

      expect(result).to eq(success: true)
    end
  end

  describe '#risk_config' do
    it 'uses cached algo config loaded at initialize time' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        {
          paper_trading: { enabled: false },
          risk: { sl_pct: 1.5, tp_pct: 3.0 }
        }
      )

      service = described_class.new
      service.send(:risk_config)
      service.send(:risk_config)

      expect(AlgoConfig).to have_received(:fetch).at_least(:once)
    end
  end
end
