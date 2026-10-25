# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API alerts CRUD' do
  let(:controller_store) { Api::AlertsController }

  before do
    controller_store.mutex.synchronize { controller_store.alerts.clear }
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe 'GET /api/alerts' do
    it 'returns an empty list when no alerts exist' do
      get '/api/alerts'
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'returns alerts created through the API' do
      controller_store.push_alert(type: 'system', severity: 'warn', message: 'feed stale')

      get '/api/alerts'
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first['type']).to eq('system')
      expect(body.first['severity']).to eq('warn')
      expect(body.first['message']).to eq('feed stale')
      expect(body.first['read']).to be(false)
    end

    it 'broadcasts each created alert to the alerts channel' do
      post '/api/alerts', params: { type: 'price', severity: 'info', message: 'above vwap' }, as: :json

      expect(ActionCable.server).to have_received(:broadcast).with('alerts', hash_including(alert: hash_including(type: 'price')))
    end
  end

  describe 'POST /api/alerts' do
    it 'creates an alert and returns it with 201' do
      post '/api/alerts', params: { type: 'risk', severity: 'critical', message: 'drawdown breach' }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['id']).to be_a(Integer)
      expect(body['type']).to eq('risk')
      expect(body['severity']).to eq('critical')
      expect(body['message']).to eq('drawdown breach')
      expect(body['read']).to be(false)
      expect(body['created_at']).to be_present
    end

    it 'defaults type/severity/message when params are missing' do
      post '/api/alerts', params: {}, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['type']).to eq('custom')
      expect(body['severity']).to eq('info')
      expect(body['message']).to eq('No message')
    end
  end

  describe 'PATCH /api/alerts/:id' do
    it 'marks an alert as read' do
      alert = controller_store.push_alert(type: 'system', severity: 'info', message: 'reconnected')

      patch "/api/alerts/#{alert[:id]}", params: { read: 'true' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['read']).to be(true)
    end

    it 'leaves read unchanged for other values' do
      alert = controller_store.push_alert(type: 'system', severity: 'info', message: 'reconnected')

      patch "/api/alerts/#{alert[:id]}", params: { read: 'nope' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['read']).to be(false)
    end

    it 'returns 404 for an unknown id' do
      patch '/api/alerts/999999', params: { read: 'true' }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('not_found')
    end
  end

  describe 'DELETE /api/alerts/:id' do
    it 'removes the alert' do
      alert = controller_store.push_alert(type: 'system', severity: 'info', message: 'gone soon')

      delete "/api/alerts/#{alert[:id]}"

      expect(response).to have_http_status(:no_content)
      expect(controller_store.alerts).to be_empty
    end

    it 'returns 404 for an unknown id' do
      delete '/api/alerts/999999'
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('not_found')
    end
  end

  describe 'authentication' do
    around do |example|
      previous = ENV.fetch('API_DASHBOARD_TOKEN', nil)
      ENV['API_DASHBOARD_TOKEN'] = 'dash-secret'
      example.run
    ensure
      if previous
        ENV['API_DASHBOARD_TOKEN'] = previous
      else
        ENV.delete('API_DASHBOARD_TOKEN')
      end
    end

    it 'returns 401 without a token' do
      get '/api/alerts'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with a matching Bearer token' do
      get '/api/alerts', headers: { 'Authorization' => 'Bearer dash-secret' }
      expect(response).to have_http_status(:ok)
    end
  end
end
