# frozen_string_literal: true

require "rails_helper"

# Hard domain boundaries from docs/investing/TECHNICAL_DESIGN.md §2:
# the intraday Trading engine and the Investing domain may share
# infrastructure (Instrument master, DhanHQ client, Redis, PG) but must
# never reference each other's models or services. These greps fail the
# build if either side starts reaching across the line (A-ARCH-01).
TRADING_DIRS = %w[
  app/services/live
  app/services/entries
  app/services/auto_exp
  app/services/exits
  app/services/capital
  app/services/trading
].freeze

INVESTING_PATTERN = /(Investing::|investment_|InvestmentPortfolio|InvestmentPolicy)/m
TRADING_PATTERN   = /(PositionTracker|EntryGuard|Live::|AutoExp|TrailingStop)/m

RSpec.describe "Investing/Trading domain isolation" do
  def ruby_files_under(dirs)
    dirs.filter_map do |dir|
      path = Rails.root.join(dir)
      Dir.glob(path.join("**", "*.rb").to_s) if Dir.exist?(path.to_s)
    end.flatten
  end

  it "trading services never reference the investing domain" do
    offenses = ruby_files_under(TRADING_DIRS)
               .select { |file| File.read(file).match?(INVESTING_PATTERN) }

    expect(offenses).to be_empty,
                        "Trading files reference the Investing domain: #{offenses.join(', ')}"
  end

  it "investing services never reference the intraday trading machinery" do
    offenses = ruby_files_under(%w[app/services/investing])
               .select { |file| File.read(file).match?(TRADING_PATTERN) }

    expect(offenses).to be_empty,
                        "Investing files reference the Trading domain: #{offenses.join(', ')}"
  end

  it "investing models never reference the intraday position tracker" do
    offenses = Dir.glob(Rails.root.join("app/models/investment_*.rb").to_s)
                  .select { |file| File.read(file).match?(TRADING_PATTERN) }

    expect(offenses).to be_empty
  end
end
