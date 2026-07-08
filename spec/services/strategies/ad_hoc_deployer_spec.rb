# frozen_string_literal: true

require "rails_helper"
require "fileutils"

RSpec.describe Strategies::AdHocDeployer do
  let(:strategies_root) { Rails.root.join("strategies") }
  let(:code) do
    <<~RUBY
      class MyTestStrategy < BaseStrategy
        class << self
          def timeframes = %w[1m]
          def instruments = %w[NIFTY]
          def params_schema = {}
        end

        def call(context)
          Signals::Hold.new(reason: "test")
        end
      end
    RUBY
  end
  let(:trading_strategy) do
    TradingStrategy.create!(
      name: "My Test Strategy",
      code: code,
      instruments: ["NIFTY"],
      timeframe: "1m",
      parameters: []
    )
  end

  after do
    dir = strategies_root.join(trading_strategy.slugify)
    FileUtils.rm_rf(dir) if dir.exist?
  end

  it "writes manifest.yml and strategy.rb, deploys, and links the record" do
    result = described_class.call(trading_strategy)

    expect(result[:ok]).to be true
    expect(result[:errors]).to be_empty
    expect(strategies_root.join("my-test-strategy", "manifest.yml")).to exist
    expect(strategies_root.join("my-test-strategy", "strategy.rb")).to exist

    trading_strategy.reload
    expect(trading_strategy.slug).to eq("my-test-strategy")
    expect(trading_strategy.strategy_record_id).to eq(result[:strategy_record].id)
    expect(trading_strategy.status).to eq("active")
  end

  it "returns errors and does not link when code has no class definition" do
    trading_strategy.update!(code: "# no class here")

    result = described_class.call(trading_strategy)

    expect(result[:ok]).to be false
    expect(result[:errors]).to include(match(/no strategy class found/i))
    expect(trading_strategy.reload.strategy_record_id).to be_nil
  end
end
