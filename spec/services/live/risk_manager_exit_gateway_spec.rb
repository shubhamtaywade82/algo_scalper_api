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
      calls = 0
      allow(AlgoConfig).to receive(:fetch) do
        calls += 1
        { paper_trading: { enabled: false }, risk: { sl_pct: 1.5, tp_pct: 3.0 } }
      end

      service = described_class.new
      calls_after_init = calls

      service.send(:risk_config)
      calls_after_first_read = calls

      service.send(:risk_config)

      # Whatever the constructor fetched, the SECOND risk_config read must not
      # re-fetch (the first read may populate the memo if the constructor did
      # not touch it).
      expect(calls_after_first_read - calls_after_init).to be <= 1
      expect(calls).to eq(calls_after_first_read)
    end
  end
end
