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

    it 'returns 422 with errors when a value is out of range' do
      patch '/api/settings/bulk', params: { settings: { signals: { min_confidence: 999 } } }
      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json['errors'].join).to match(/min_confidence/)
    end

    it 'does not persist an out-of-range value' do
      patch '/api/settings/bulk', params: { settings: { signals: { min_confidence: 999 } } }
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc['signals']).to be_nil
    end
  end

  describe 'PATCH /api/settings/deep_merge' do
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
      yaml_keys = YAML.load_file(Rails.root.join('config/algo.yml')).keys
      seed = yaml_keys.index_with { {} }
      seed['risk'] = { sl_pct: 0.02 }
      Setting.put(doc_key, seed.to_json)
      AlgoConfig.reset!
    end

    it 'deep-merges previously blocked options_buying key' do
      patch '/api/settings/deep_merge',
            params: { patch: { options_buying: { mode: 'intraday_scalper' } } }
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('options_buying', 'mode')).to eq('intraday_scalper')
    end

    it 'deep-merges entry_quality key' do
      patch '/api/settings/deep_merge',
            params: { patch: { entry_quality: { min_score: 55 } } }
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('entry_quality', 'min_score').to_i).to eq(55)
    end

    it 'rejects credential sections' do
      patch '/api/settings/deep_merge', params: { patch: { dhanhq: { client_id: 'x' } } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'deep-merges trading_time_restrictions for session discipline' do
      patch '/api/settings/deep_merge',
            params: {
              patch: {
                trading_time_restrictions: {
                  enabled: true,
                  avoid_periods: ['11:00-13:45'],
                  block_exits: false
                },
                signals: { signal_tier: 'selective' }
              }
            }
      expect(response).to have_http_status(:ok)
      doc = JSON.parse(Setting.find_by!(key: doc_key).value)
      expect(doc.dig('trading_time_restrictions', 'enabled').to_s).to eq('true')
      expect(doc.dig('trading_time_restrictions', 'avoid_periods')).to eq(['11:00-13:45'])
      expect(doc.dig('signals', 'signal_tier')).to eq('selective')
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

  describe 'GET /api/settings/fast_entry_mode' do
    it 'returns persisted and effective status' do
      get '/api/settings/fast_entry_mode'
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['fast_entry_mode']).to include('persisted', 'effective', 'env_override')
    end
  end

  describe 'PATCH /api/settings/fast_entry_mode' do
    around do |example|
      prior_token = ENV.fetch('SETTINGS_UPDATE_TOKEN', nil)
      prior_fast = ENV.fetch('FAST_ENTRY_MODE', nil)
      ENV.delete('SETTINGS_UPDATE_TOKEN')
      ENV.delete('FAST_ENTRY_MODE')
      example.run
    ensure
      if prior_token
        ENV['SETTINGS_UPDATE_TOKEN'] = prior_token
      else
        ENV.delete('SETTINGS_UPDATE_TOKEN')
      end
      if prior_fast
        ENV['FAST_ENTRY_MODE'] = prior_fast
      else
        ENV.delete('FAST_ENTRY_MODE')
      end
    end

    before do
      Setting.put(doc_key, { signals: { fast_entry_mode: { enabled: false } } }.to_json)
      AlgoConfig.reset!
      Signal::FastEntryMode.reset!
    end

    it 'enables fast entry mode without daemon restart' do
      patch '/api/settings/fast_entry_mode', params: { enabled: true }
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json.dig('fast_entry_mode', 'persisted')).to be(true)
      expect(json.dig('fast_entry_mode', 'effective')).to be(true)
      expect(Signal::FastEntryMode.enabled?).to be(true)
    end

    it 'disables fast entry mode' do
      patch '/api/settings/fast_entry_mode', params: { enabled: false }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('fast_entry_mode', 'effective')).to be(false)
    end
  end
end
