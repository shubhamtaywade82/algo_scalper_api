# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::MarketBriefs' do
  include ActiveJob::TestHelper

  def ready_report(**attrs)
    report, = MarketBriefReport.request!(mode: :paper, now: attrs.delete(:now) || Time.current)
    report.update!({ status: 'ready', snapshot: { 'setup' => { 'decision' => 'NO_TRADE' } },
                     snapshot_generated_at: Time.current, ai_status: 'unavailable', ai_error: 'no_response' }.merge(attrs))
    report
  end

  describe 'GET /api/reports/market_brief' do
    it 'returns brief: null (not an error) when no report exists yet' do
      get '/api/reports/market_brief'
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('success' => true, 'brief' => nil, 'in_progress' => nil, 'mode' => 'paper')
    end

    it 'returns the latest ready report with AI status and freshness metadata' do
      ready_report(now: 1.hour.ago)
      latest = ready_report

      get '/api/reports/market_brief'
      brief = response.parsed_body['brief']
      expect(brief['id']).to eq(latest.id)
      expect(brief['snapshot']['setup']['decision']).to eq('NO_TRADE')
      expect(brief['ai']).to include('status' => 'unavailable', 'error' => 'no_response', 'analysis' => nil)
    end

    it 'reports an in-flight build newer than the latest ready report' do
      ready_report(now: 1.hour.ago)
      pending, = MarketBriefReport.request!(mode: :paper)

      get '/api/reports/market_brief'
      expect(response.parsed_body['in_progress']).to include('id' => pending.id, 'status' => 'pending')
    end

    it 'fetches a specific report by id and 404s on an unknown id' do
      report = ready_report
      get '/api/reports/market_brief', params: { id: report.id }
      expect(response.parsed_body.dig('brief', 'id')).to eq(report.id)

      get '/api/reports/market_brief', params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end

    it 'requires the dashboard token when configured' do
      stub_const('ENV', ENV.to_h.merge('API_DASHBOARD_TOKEN' => 'dash-secret'))
      get '/api/reports/market_brief'
      expect(response).to have_http_status(:unauthorized)

      get '/api/reports/market_brief', headers: { 'X-Api-Key' => 'dash-secret' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /api/reports/market_brief/live' do
    it 'returns realtime facts plus AI status without enqueuing or calling the model' do
      allow(Reports::MarketBrief::LiveBrief).to receive(:call).and_call_original
      expect(Services::Ai::OllamaClient).not_to receive(:instance)

      expect { get '/api/reports/market_brief/live' }.not_to have_enqueued_job(Reports::MarketBriefJob)
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('success' => true, 'live' => true, 'mode' => 'paper')
      expect(body['snapshot']).to include('schema_version' => 1, 'setup' => hash_including('decision'))
      expect(body['ai']).to include('status')
    end

    it 'requires the dashboard token when configured' do
      stub_const('ENV', ENV.to_h.merge('API_DASHBOARD_TOKEN' => 'dash-secret'))
      get '/api/reports/market_brief/live'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/reports/market_brief' do
    it 'accepts the request and enqueues one build' do
      expect do
        post '/api/reports/market_brief'
      end.to have_enqueued_job(Reports::MarketBriefJob).exactly(:once)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include('enqueued' => true)
      expect(response.parsed_body.dig('brief', 'status')).to eq('pending')
    end

    it 'deduplicates repeated requests within the slot (no extra LLM calls)' do
      post '/api/reports/market_brief'
      expect { post '/api/reports/market_brief' }.not_to have_enqueued_job(Reports::MarketBriefJob)
      expect(response.parsed_body['enqueued']).to be(false)
      expect(MarketBriefReport.count).to eq(1)
    end

    it 'retries a failed report in the same slot' do
      post '/api/reports/market_brief'
      MarketBriefReport.last.update!(status: 'failed', error: 'boom')
      expect { post '/api/reports/market_brief' }.to have_enqueued_job(Reports::MarketBriefJob)
      expect(MarketBriefReport.last.status).to eq('pending')
    end

    it 'requires the operator token to force AI past the market-closed gate' do
      stub_const('ENV', ENV.to_h.merge('API_DASHBOARD_TOKEN' => 'dash', 'API_OPERATOR_TOKEN' => 'op'))
      post '/api/reports/market_brief', params: { force_ai: true }, headers: { 'X-Api-Key' => 'dash' }
      expect(response).to have_http_status(:unauthorized)
      expect(MarketBriefReport.count).to eq(0)
    end

    it 'has no order-execution side effects' do
      expect { post '/api/reports/market_brief' }.not_to change(PositionTracker, :count)
    end
  end
end
