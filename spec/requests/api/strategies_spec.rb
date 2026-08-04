# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Strategies' do
  describe 'GET /api/strategies' do
    it 'returns an empty list when no strategies exist' do
      get '/api/strategies'
       if response.status != 200
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be true
      expect(body['strategies']).to eq([])
    end

    it 'lists strategies' do
      create(:strategy_record, slug: 'alpha', name: 'Alpha', status: 'running')
      create(:strategy_record, slug: 'beta', name: 'Beta', status: 'deployed')

      get '/api/strategies'
      body = response.parsed_body
      slugs = body['strategies'].pluck('slug')
      expect(slugs).to contain_exactly('alpha', 'beta')
    end
  end

  describe 'POST /api/strategies' do
    let(:template_dir) { Rails.root.join("strategies/_templates/basic") }

    before do
      template_dir.mkpath unless template_dir.directory?
      template_dir.join('manifest.yml').write({ 'slug' => 'placeholder', 'name' => 'Placeholder' }.to_yaml)
      template_dir.join('strategy.rb').write('class PlaceholderStrategy < Strategies::Base; def call(c) = nil; end')
    end

    after do
      FileUtils.rm_rf(Rails.root.join("strategies/my_new_strategy"))
    end

    it 'scaffolds a new strategy' do
      post '/api/strategies', params: { slug: 'my_new_strategy', name: 'My New Strategy', template: 'basic' }
      
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['slug']).to eq('my_new_strategy')
      expect(body['status']).to eq('draft')
      expect(Strategies::Record.find_by(slug: 'my_new_strategy')).to be_present
    end

    it 'returns 422 for a missing slug' do
      post '/api/strategies', params: { name: 'No Slug' }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /api/strategies/:slug' do
    let!(:strategy) { create(:strategy_record, slug: 'detail_test', name: 'Detail Test') }

    it 'returns strategy details' do
      get "/api/strategies/#{strategy.slug}"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['strategy']['slug']).to eq('detail_test')
      expect(body['strategy']['name']).to eq('Detail Test')
    end

    it 'returns 404 for unknown slug' do
      get '/api/strategies/unknown'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/strategies/:slug/deploy' do
    let(:slug) { 'deploy_test' }
    let(:strategy_dir) { Rails.root.join('strategies', slug) }

    before do
      strategy_dir.mkpath
      strategy_dir.join('manifest.yml').write(<<~YAML)
        slug: #{slug}
        name: Deploy Test
        class_name: DeployTestStrategy
        params: {}
        instruments:
          - NIFTY
        timeframes:
          - 1m
      YAML
      strategy_dir.join('strategy.rb').write(<<~RUBY)
        class DeployTestStrategy < Strategies::Base
          def call(context) = nil
        end
      RUBY
    end

    after do
      FileUtils.rm_rf(strategy_dir)
      Strategies::Record.find_by(slug: slug)&.destroy
    end

    it 'deploys the strategy' do
      post "/api/strategies/#{slug}/deploy"
       if response.status != 200
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be true
      expect(body['version']['version']).to eq(1)
    end
  end

  describe 'POST /api/strategies/:slug/start' do
    let!(:strategy) { create(:strategy_record, slug: 'start_test', status: 'deployed') }

    it 'sets desired_status to running' do
      post "/api/strategies/#{strategy.slug}/start"
       if response.status != 202
      expect(response).to have_http_status(:accepted)
      expect(strategy.reload.desired_status).to eq('running')
    end
  end

  describe 'POST /api/strategies/:slug/stop' do
    let!(:strategy) { create(:strategy_record, slug: 'stop_test', status: 'running', desired_status: 'running') }

    it 'sets desired_status to stopped' do
      post "/api/strategies/#{strategy.slug}/stop"
      expect(response).to have_http_status(:accepted)
      expect(strategy.reload.desired_status).to eq('stopped')
    end
  end

  describe 'POST /api/strategies/:slug/restart' do
    let!(:strategy) { create(:strategy_record, slug: 'restart_test', status: 'running', desired_status: 'running') }

    it 'cycles desired_status through stopped to running' do
      post "/api/strategies/#{strategy.slug}/restart"
      expect(response).to have_http_status(:accepted)
      expect(strategy.reload.desired_status).to eq('running')
    end
  end

  describe 'GET /api/strategies/:slug/versions' do
    let!(:strategy) { create(:strategy_record, slug: 'versions_test') }
    let!(:v1) { create(:strategy_version, strategy_record: strategy, version: 1) }
    let!(:v2) { create(:strategy_version, strategy_record: strategy, version: 2) }

    it 'returns version history' do
      get "/api/strategies/#{strategy.slug}/versions"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['versions'].size).to eq(2)
      expect(body['versions'].first['version']).to eq(2)
    end
  end

  describe 'GET /api/strategies/:slug/signals' do
    let!(:strategy) { create(:strategy_record, slug: 'signals_test') }
    let!(:version) { create(:strategy_version, strategy_record: strategy) }
    let!(:run) { create(:strategy_run, strategy_record: strategy, strategy_version: version) }
    let!(:signal) { create(:strategy_signal, strategy_record: strategy, strategy_version: version, strategy_run: run, action: 'buy_call') }

    it 'returns signals' do
      get "/api/strategies/#{strategy.slug}/signals"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['signals'].size).to eq(1)
      expect(body['signals'].first['action']).to eq('buy_call')
    end
  end

  describe 'GET /api/strategies/:slug/logs' do
    let!(:strategy) { create(:strategy_record, slug: 'logs_test') }

    it 'returns empty logs array' do
      get "/api/strategies/#{strategy.slug}/logs"
       if response.status != 200
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['logs']).to eq([])
    end
  end

  describe 'GET /api/strategies/:slug/variables' do
    let!(:strategy) { create(:strategy_record, slug: 'vars_test') }

    it 'upserts and returns variables' do
      put "/api/strategies/#{strategy.slug}/variables", params: {
        variables: [
          { key: 'api_key', value: 'secret123', value_type: 'string', secret: true },
          { key: 'threshold', value: '0.05', value_type: 'decimal' }
        ]
      }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['variables'].size).to eq(2)
      secret_var = body['variables'].find { |v| v['key'] == 'api_key' }
      expect(secret_var['value']).to eq('•••')
      expect(secret_var['secret']).to be true

      get "/api/strategies/#{strategy.slug}/variables"
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['variables'].size).to eq(2)
    end
  end
end
