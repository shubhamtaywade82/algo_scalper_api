# frozen_string_literal: true

require 'spec_helper'
require_relative '../../src/utils/logger'
require_relative '../../src/api/dhan_client'

RSpec.describe Api::DhanClient do
  let(:client) { described_class.new(client_id: 'test_client_id', access_token: 'test_access_token') }

  describe '#get_fund_limit', vcr: { cassette_name: 'api/get_fund_limit' } do
    it 'fetches fund limits successfully' do
      response = client.get_fund_limit
      expect(response[:availabelBalance]).to eq(485000.0)
      expect(response[:dhanClientId]).to eq('test_client_id')
    end
  end

  describe 'retry logic' do
    it 'retries on 429 Too Many Requests' do
      stub_request(:get, "https://api.dhan.co/fundlimit")
        .to_return({ status: 429, body: 'Rate Limit Exceeded' }, { status: 200, body: '{"availabelBalance":100}', headers: { 'Content-Type' => 'application/json' } })

      response = client.get_fund_limit
      expect(response[:availabelBalance]).to eq(100)
    end
  end
end
