# frozen_string_literal: true

require 'swagger_helper'

# rubocop:disable-next RSpec/DescribeClass, RSpec/EmptyExampleGroup, RSpec/ScatteredSetup -- RSwag OpenAPI specs
RSpec.describe 'OpenAPI v1 — SMC & analysis', openapi_spec: 'v1/swagger.yaml' do
  path '/api/smc/decision' do
    get 'SMC bias / structure' do
      tags 'SMC'
      produces 'application/json'
      parameter name: :security_id, in: :query, type: :string, required: true
      parameter name: :segment, in: :query, type: :string, required: true
      parameter name: :symbol_name, in: :query, type: :string, required: false
      parameter name: :details, in: :query, type: :string, required: false,
                description: 'Set to 1 for extended structure payload'
      parameter name: :ai, in: :query, type: :string, required: false,
                description: 'Set to 1 for optional AI attachment (operator token when API_OPERATOR_TOKEN is set)'

      response '200', 'decision' do
        let(:security_id) { '13' }
        let(:segment) { 'IDX_I' }

        before do
          inst = create(:instrument, :nifty_future)
          allow(Instrument).to receive(:find_by_sid_and_segment).and_return(inst)
          engine = instance_double(Smc::BiasEngine, decision: 'neutral', details: { timeframes: {} })
          allow(Smc::BiasEngine).to receive(:new).and_return(engine)
        end

        schema type: :object,
               additionalProperties: true,
               properties: {
                 ok: { type: :boolean },
                 decision: { type: :string }
               }

        run_test!
      end

      response '422', 'missing security_id or segment' do
        let(:security_id) { '' }
        let(:segment) { '' }

        schema type: :object,
               properties: {
                 ok: { type: :boolean },
                 error: { type: :string }
               }

        run_test!
      end
    end
  end

  path '/api/analysis/{index_key}' do
    get 'Cached analysis bundle' do
      tags 'Analysis'
      produces 'application/json'
      parameter name: :index_key, in: :path, type: :string, required: true
      parameter name: :force, in: :query, type: :string, required: false

      response '200', 'analysis JSON' do
        let(:index_key) { 'NIFTY' }

        before do
          inst = create(:instrument, :nifty_future)
          stub_analysis_show_dependencies!(inst)
        end

        schema type: :object,
               additionalProperties: true,
               properties: {
                 index_key: { type: :string },
                 ltp: { type: :number, nullable: true }
               }

        run_test!
      end
    end
  end

  path '/api/analysis/{index_key}/historical' do
    get 'Historical options context' do
      tags 'Analysis'
      produces 'application/json'
      parameter name: :index_key, in: :path, type: :string, required: true
      parameter name: :weeks, in: :query, type: :integer, required: false

      response '200', 'historical payload' do
        let(:index_key) { 'NIFTY' }
        let(:weeks) { 4 }

        before do
          analyzer = instance_double(HistoricalOptionsAnalyzer, analyze: { 'weeks' => 4, 'rows' => [] })
          allow(HistoricalOptionsAnalyzer).to receive(:new).and_return(analyzer)
        end

        schema type: :object, additionalProperties: true

        run_test!
      end
    end
  end

  path '/api/analysis/{index_key}/ai_snapshot' do
    post 'On-demand AI snapshot (sync)' do
      tags 'Analysis'
      produces 'application/json'
      parameter name: :index_key, in: :path, type: :string, required: true

      response '503', 'AI not configured or unavailable' do
        let(:index_key) { 'NIFTY' }

        before do
          inst = create(:instrument, :nifty_future)
          allow(IndexConfigLoader).to receive(:load_indices).and_return(
            [
              { key: 'NIFTY', segment: inst.exchange_segment, sid: inst.security_id.to_s }
            ]
          )
          allow(Instrument).to receive(:find_by_sid_and_segment).and_return(inst)
          allow(Live::TickCache).to receive(:ltp).and_return(22_450.0)
          allow(AnalysisStore).to receive(:read_all).and_return({})
          allow(CalibrationRun).to receive(:where).and_return(CalibrationRun.none)
          client = instance_double(Services::Ai::OllamaClient, enabled?: false)
          allow(Services::Ai::OllamaClient).to receive(:instance).and_return(client)
        end

        schema type: :object,
               properties: { error: { type: :string } },
               required: ['error']

        run_test!
      end
    end
  end
end
