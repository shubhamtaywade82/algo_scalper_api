# frozen_string_literal: true

require_relative '../api/dhan_research_client'
require_relative '../market_data/spot_options_combiner'
require_relative '../utils/logger'
require 'csv'
require 'json'

module Backtest
  # Orchestrates fetching and analyzing spot + expired options data
  class OptionsResearchOrchestrator
    def initialize(access_token: ENV.fetch('DHAN_ACCESS_TOKEN', nil))
      @client = Api::DhanResearchClient.new(access_token: access_token)
    end

    def run_research(underlying: :nifty, from_date:, to_date:, strike: 'ATM', interval: '1', expiry_flag: 'WEEK', save_to_csv: true)
      security_id = map_underlying_id(underlying)

      # 1. Fetch Spot Data
      spot_data = @client.fetch_spot_intraday(
        security_id: security_id,
        from_date: from_date,
        to_date: to_date,
        interval: interval
      )

      # 2. Fetch Call Data
      call_data = @client.fetch_rolling_options(
        security_id: security_id,
        option_type: 'CALL',
        from_date: from_date,
        to_date: to_date,
        interval: interval,
        strike: strike,
        expiry_flag: expiry_flag
      )

      # 3. Fetch Put Data
      put_data = @client.fetch_rolling_options(
        security_id: security_id,
        option_type: 'PUT',
        from_date: from_date,
        to_date: to_date,
        interval: interval,
        strike: strike,
        expiry_flag: expiry_flag
      )

      # 4. Combine Datasets
      combined_dataset = MarketData::SpotOptionsCombiner.combine(
        spot_data: spot_data,
        call_data: call_data,
        put_data: put_data
      )

      # 5. Save/Return Results
      if save_to_csv && combined_dataset.any?
        save_dataset_to_csv(combined_dataset, underlying, from_date, to_date, strike)
      end

      combined_dataset
    end

    private

    def map_underlying_id(underlying)
      case underlying.to_sym
      when :nifty then 13
      when :banknifty then 25
      when :finnifty then 27
      when :sensex then 51
      else raise "Unsupported underlying: #{underlying}"
      end
    end

    def save_dataset_to_csv(dataset, underlying, from, to, strike)
      filename = "research_results/#{underlying}_#{strike}_#{from}_to_#{to}.csv"
      Dir.mkdir('research_results') unless Dir.exist?('research_results')

      CSV.open(filename, 'wb') do |csv|
        csv << dataset.first.keys
        dataset.each { |row| csv << row.values }
      end

      ::Utils::Logger.info("research.saved_csv", path: filename, count: dataset.size)
    end
  end
end
