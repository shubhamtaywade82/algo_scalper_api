# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Settings' do
  let(:doc_key) { AlgoConfig::DocumentStore::DOCUMENT_KEY }

  after do
    Setting.where(key: doc_key).delete_all
    AlgoConfigChangeLog.delete_all
    AlgoConfig.reset!
  end

  describe 'GET /api/settings' do
    it 'returns 200 with config' do
      get '/api/settings'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['config']).to be_a(Hash)
    end
  end

  describe 'PATCH /api/settings/bulk' do
    around do |example|
      prior = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
      ENV.delete('SETTINGS_UPDATE_TOKEN')
      example.run
    ensure
      if prior
        ENV['SETTINGS_UPDATE_TOKEN'] = prior
      else
        ENV.delete('SETTINGS_UPDATE_TOKEN')
      end
    end

    before do
      Setting.put(doc_key, { mode: 'paper', risk: { sl_pct: 0.02 } }.to_json)
      AlgoConfig.reset!
    end

    it 'replaces a permitted top-level subtree' do
      patch '/api/settings/bulk',
            params: { settings: { risk: { sl_pct: 0.03, trailing: { drawdown_pct: 0.02 } } } }
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('risk', 'sl_pct').to_f).to eq(0.03)
      expect(doc.dig('risk', 'trailing', 'drawdown_pct').to_f).to eq(0.02)
    end

    it 'writes api_settings_bulk change log' do
      patch '/api/settings/bulk', params: { settings: { signals: { enable_adx_filter: false } } }
      log = AlgoConfigChangeLog.order(:id).last
      expect(log.source).to eq('api_settings_bulk')
      expect(log.changed_paths).to include('/signals')
    end

    it 'returns 400 when settings param missing' do
      patch '/api/settings/bulk', params: {}
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 422 when all settings keys are filtered out' do
      patch '/api/settings/bulk', params: { settings: { bogus_key: { a: 1 } } }
      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json['error']).to match(/No permitted/)
    end
  end

  describe 'GET /api/settings/change_logs' do
    before do
      AlgoConfigChangeLog.create!(
        source: 'test',
        actor: 'rspec',
        request_id: nil,
        patch: { x: 1 },
        changed_paths: ['/risk'],
        metadata: {}
      )
    end

    it 'returns change logs with pagination metadata' do
      get '/api/settings/change_logs', params: { limit: 10 }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json).to include('total' => a_kind_of(Integer), 'limit' => 10, 'offset' => 0)
    end

    it 'includes source in each change log entry' do
      get '/api/settings/change_logs', params: { limit: 10 }
      json = response.parsed_body
      expect(json['change_logs'].first['source']).to eq('test')
    end

    it 'clamps limit to valid range' do
      get '/api/settings/change_logs', params: { limit: 999 }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['limit']).to eq(200)
    end
  end
end
