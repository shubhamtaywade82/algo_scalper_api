# frozen_string_literal: true

require 'swagger_helper'

# rubocop:disable RSpec/DescribeClass, RSpec/EmptyExampleGroup, RSpec/ScatteredSetup -- RSwag OpenAPI specs
RSpec.describe 'OpenAPI v1 — infrastructure & dashboard reads', openapi_spec: 'v1/swagger.yaml' do
  path '/up' do
    get 'Rails process liveness' do
      tags 'Infrastructure'
      description 'Used by load balancers; does not include trading cluster detail (see /api/health).'
      response '200', 'process booted' do
        run_test!
      end
    end
  end

  path '/api/health' do
    get 'Trading cluster health' do
      tags 'Health'
      produces 'application/json'
      description 'Requires Bearer or X-Api-Key when API_DASHBOARD_TOKEN is set.'

      response '200', 'health JSON' do
        before { stub_health_dependencies! }

        schema type: :object,
               additionalProperties: true,
               properties: {
                 mode: { type: :string },
                 active_positions: { type: :integer },
                 circuit_breaker: { type: :object, additionalProperties: true },
                 websocket: { type: :object, additionalProperties: true }
               }

        run_test!
      end
    end
  end

  path '/api/dashboard' do
    get 'Dashboard snapshot' do
      tags 'Dashboard'
      produces 'application/json'
      description 'Requires Bearer or X-Api-Key when API_DASHBOARD_TOKEN is set.'

      response '200', 'dashboard JSON' do
        before { stub_dashboard_dependencies! }

        schema type: :object,
               additionalProperties: true,
               properties: {
                 mode: { type: :string },
                 system: { type: :object, additionalProperties: true },
                 circuit_breaker: { type: :object, additionalProperties: true }
               }

        run_test!
      end
    end
  end

  path '/api/positions' do
    get 'Positions index' do
      tags 'Positions'
      produces 'application/json'
      parameter name: :date, in: :query, type: :string, required: false, description: 'Filter closed by exit date (YYYY-MM-DD)'
      parameter name: :index_key, in: :query, type: :string, required: false

      response '200', 'open and closed buckets' do
        schema type: :object,
               additionalProperties: true,
               properties: {
                 open: { type: :array, items: {} },
                 closed: { type: :array, items: {} },
                 available_dates: { type: :array, items: { type: :string } },
                 summary: { type: :object, additionalProperties: true }
               }

        run_test!
      end
    end
  end

  path '/api/signals' do
    get 'Trading signals' do
      tags 'Signals'
      produces 'application/json'
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response '200', 'paginated signals' do
        schema type: :object,
               properties: {
                 signals: { type: :array, items: {} },
                 meta: { type: :object, additionalProperties: true }
               },
               required: %w[signals meta]

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/EmptyExampleGroup, RSpec/ScatteredSetup
