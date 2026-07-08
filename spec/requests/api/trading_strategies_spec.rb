# frozen_string_literal: true

require "rails_helper"
require "fileutils"

RSpec.describe "Api::TradingStrategies" do
  let(:headers) { { "X-Api-Key" => ENV.fetch("DASHBOARD_API_TOKEN", "test-token") } }
  let(:valid_code) do
    <<~RUBY
      class DeployableStrategy < Strategies::Base
        def call(context)
          Signals::Hold.new(reason: "ok")
        end
      end
    RUBY
  end
  let(:strategy) do
    TradingStrategy.create!(name: "Deployable", code: valid_code, instruments: ["NIFTY"], parameters: [])
  end

  after do
    dir = Rails.root.join("strategies", strategy.slugify)
    FileUtils.rm_rf(dir) if dir.exist?
  end

  describe "POST /api/trading_strategies/:id/deploy" do
    it "deploys and links the strategy record" do
      post "/api/trading_strategies/#{strategy.id}/deploy", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be true
      expect(body["slug"]).to eq("deployable")
      expect(strategy.reload.strategy_record_id).to be_present
    end

    it "returns 422 with errors when code has no class" do
      strategy.update!(code: "# nothing")

      post "/api/trading_strategies/#{strategy.id}/deploy", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["success"]).to be false
      expect(body["errors"]).to be_present
    end
  end

  describe "PATCH /api/trading_strategies/:id" do
    it "accepts the new rule-panel jsonb fields" do
      patch "/api/trading_strategies/#{strategy.id}",
            params: { trading_strategy: { entry_rules: { min_adx: 25 }, schedule: { start: "09:20" } } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(strategy.reload.entry_rules).to eq({ "min_adx" => 25 })
      expect(strategy.schedule).to eq({ "start" => "09:20" })
    end
  end
end
