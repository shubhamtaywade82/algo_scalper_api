# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strategies::AdHocBacktester do
  let(:instrument) { create(:instrument, :nifty_index) }

  let(:passing_code) do
    <<~RUBY
      class PassingStrategy < Strategies::Base
        def call(context)
          Signals::Hold.new(reason: "ok")
        end
      end
    RUBY
  end

  let(:trading_strategy) do
    TradingStrategy.new(name: "Passing", code: passing_code, instruments: ["NIFTY"], parameters: [])
  end

  before do
    instrument
    series = CandleSeries.new(symbol: "NIFTY", interval: "1m")
    build_list(:candle, 40).each { |c| series.add_candle(c) }
    allow(Candles::Repository).to receive(:series).and_return(series)
  end

  it "passes syntax, security, and backtest checks for valid code" do
    result = described_class.new(trading_strategy).run

    expect(result[:checks][:syntax]).to eq("passed")
    expect(result[:checks][:logic]).to eq("passed")
    expect(result[:checks][:risk]).to eq("passed")
    expect(result[:checks][:backtest]).to eq("passed")
    expect(result[:backtest_results]["signal_counts"]).to include("Hold" => be > 0)
    expect(result[:backtest_results]["candle_count"]).to eq(40)
    expect(result[:backtest_results]["error"]).to be_nil
  end

  it "fails the syntax check on a Ruby syntax error" do
    trading_strategy.code = "class Broken < Strategies::Base def call(c) end"

    result = described_class.new(trading_strategy).run

    expect(result[:checks][:syntax]).to eq("failed")
    expect(result[:checks][:backtest]).to eq("failed")
  end

  it "fails the risk check when the code uses a blocked call" do
    trading_strategy.code = <<~RUBY
      class RiskyStrategy < Strategies::Base
        def call(context)
          `ls`
          Signals::Hold.new(reason: "x")
        end
      end
    RUBY

    result = described_class.new(trading_strategy).run

    expect(result[:checks][:risk]).to eq("failed")
  end

  it "fails the backtest check and records the error when #call raises" do
    trading_strategy.code = <<~RUBY
      class ExplodingStrategy < Strategies::Base
        def call(context)
          raise "boom"
        end
      end
    RUBY

    result = described_class.new(trading_strategy).run

    expect(result[:checks][:backtest]).to eq("failed")
    expect(result[:backtest_results]["error"]).to match(/boom/)
  end
end
