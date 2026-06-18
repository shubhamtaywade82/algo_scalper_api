# frozen_string_literal: true

require 'swagger_helper'

# rubocop:disable RSpec/DescribeClass, RSpec/EmptyExampleGroup, RSpec/ScatteredSetup -- RSwag OpenAPI specs
RSpec.describe 'OpenAPI v1 — settings, risk, debug', openapi_spec: 'v1/swagger.yaml' do
  path '/api/settings' do
    get 'Full algo config (YAML merge + DB overrides)' do
      tags 'Settings'
      produces 'application/json'
      description 'Requires dashboard token when API_DASHBOARD_TOKEN is set.'

      response '200', 'config envelope' do
        before do
          allow(AlgoConfig).to receive(:fetch).and_return({ paper_trading: { enabled: true } })
        end

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 config: { type: :object, additionalProperties: true }
               },
               required: %w[success config]

        run_test!
      end
    end
  end

  path '/api/settings/update_ip' do
    post 'Refresh Dhan-registered IP' do
      tags 'Settings'
      produces 'application/json'
      description 'Requires operator token when API_OPERATOR_TOKEN is set.'

      response '200', 'success flag' do
        before do
          allow(Dhan::IpService).to receive(:update_ip).and_return({ success: true, flag: 'ok' })
          allow(DhanHQ::Utils::NetworkInspector).to receive(:public_ipv4).and_return('198.51.100.2')
        end

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 flag: { type: :string, nullable: true }
               }

        run_test!
      end
    end
  end

  path '/api/circuit_breaker' do
    get 'Circuit breaker status' do
      tags 'CircuitBreaker'
      produces 'application/json'

      response '200', 'status' do
        before do
          allow(Risk::CircuitBreaker.instance).to receive(:status).and_return({ tripped: false })
        end

        schema type: :object, additionalProperties: true

        run_test!
      end
    end
  end

  path '/api/circuit_breaker/trip' do
    post 'Trip breaker (halt trading)' do
      tags 'CircuitBreaker'
      produces 'application/json'
      parameter name: 'X-Circuit-Breaker-Token', in: :header, type: :string, required: true
      parameter name: :reason, in: :query, type: :string, required: false
      security [{ circuitBreakerAuth: [] }]

      response '200', 'tripped' do
        let(:'X-Circuit-Breaker-Token') { 'cb-spec-token' }

        before do
          ENV['CIRCUIT_BREAKER_TOKEN'] = 'cb-spec-token'
          allow(Risk::CircuitBreaker.instance).to receive(:trip!).and_return({ tripped: true, reason: 'spec' })
        end

        after { ENV.delete('CIRCUIT_BREAKER_TOKEN') }

        schema type: :object, additionalProperties: true

        run_test!
      end
    end
  end

  path '/api/drawdown_guard/reset' do
    delete 'Reset intraday drawdown guard' do
      tags 'Risk'
      produces 'application/json'
      description 'Requires operator token when API_OPERATOR_TOKEN is set.'

      response '200', 'reset' do
        before do
          allow(Portfolio::DrawdownGuard).to receive(:reset_day!)
          allow(Portfolio::PnlTracker).to receive(:reset_day!)
        end

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string }
               }

        run_test!
      end
    end
  end

  path '/api/test_broadcast' do
    post 'Inject a test tick into TickCache' do
      tags 'Debug'
      produces 'application/json'
      description 'Allowed in development/test without operator token; in staging/production requires API_OPERATOR_TOKEN.'

      response '200', 'tick written' do
        before do
          allow(Live::TickCache).to receive(:put)
        end

        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 data: { type: :object, additionalProperties: true }
               }

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/EmptyExampleGroup, RSpec/ScatteredSetup
