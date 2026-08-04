# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Variables' do
  describe 'GET /api/variables' do
    it 'returns empty list when no variables exist' do
      get '/api/variables'
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['variables']).to eq([])
    end

    it 'lists global variables with secret masking' do
      PlatformVariable.create!(key: 'api_key', value_type: 'string', string_value: 'supersecret', secret: true, scope: 'global')
      PlatformVariable.create!(key: 'timeout', value_type: 'decimal', decimal_value: 30.0, scope: 'global')

      get '/api/variables'
      body = response.parsed_body
      vars = body['variables'].index_by { |v| v['key'] }
      expect(vars['api_key']['value']).to eq('•••')
      expect(vars['timeout']['value']).to eq("30.0")
    end
  end

  describe 'PUT /api/variables' do
    it 'upserts variables' do
      put '/api/variables', params: {
        variables: [
          { key: 'max_positions', value: '5', value_type: 'decimal' }
        ]
      }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['variables'].size).to eq(1)
      expect(body['variables'].first['key']).to eq('max_positions')
      expect(body['variables'].first['value']).to eq("5.0")
    end

    it 'returns 422 when variables param is missing' do
      put '/api/variables', params: {}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'updates existing variables' do
      PlatformVariable.create!(key: 'existing_key', value_type: 'string', string_value: 'old', scope: 'global')

      put '/api/variables', params: {
        variables: [{ key: 'existing_key', value: 'new', value_type: 'string' }]
      }
      expect(response).to have_http_status(:ok)
      expect(PlatformVariable.find_by(key: 'existing_key').string_value).to eq('new')
    end
  end
end
