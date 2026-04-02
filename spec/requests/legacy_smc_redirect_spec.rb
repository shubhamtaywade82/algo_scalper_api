# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- route behavior, not a single class
RSpec.describe 'Legacy SMC route redirect' do
  it 'returns 301 to /api/smc/decision with query preserved' do
    get '/smc/decision', params: { security_id: '13', segment: 'IDX_I', details: '1' }

    expect(response).to have_http_status(:moved_permanently)
    uri = URI.parse(response.headers['Location'])
    expect(uri.path).to eq('/api/smc/decision')
    q = Rack::Utils.parse_query(uri.query)
    expect(q).to include('security_id' => '13', 'segment' => 'IDX_I', 'details' => '1')
  end
end
# rubocop:enable RSpec/DescribeClass
