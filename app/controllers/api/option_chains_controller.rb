# frozen_string_literal: true

module Api
  class OptionChainsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def show
      index_key = params[:index_key].to_s.upcase
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
      return render json: { error: "Unknown index key: #{index_key}" }, status: :bad_request unless index_cfg

      analyzer = ::Options::DerivativeChainAnalyzer.new(index_key: index_key)
      spot = analyzer.spot_ltp
      expiry = analyzer.find_nearest_expiry

      if spot.nil? || spot <= 0
        spot = fallback_spot_price(index_key)
      end

      if spot.nil? || spot <= 0
        return render json: { error: "Could not resolve spot price for #{index_key}" }, status: :unprocessable_content
      end

      unless expiry
        return render json: { error: "No listed contracts found for #{index_key}" }, status: :unprocessable_content
      end

      # Load ATM±5 strikes for Option Chain view
      analyzer_config = { strike_window_steps: 5 }
      analyzer = ::Options::DerivativeChainAnalyzer.new(index_key: index_key, config: analyzer_config)

      legs = analyzer.load_chain_for_expiry(expiry, spot)

      atm_strike = nearest_atm(spot, legs)

      render json: {
        index_key: index_key,
        spot: spot.to_f,
        atm_strike: atm_strike,
        expiry: expiry,
        legs: formatted_legs(legs),
        chain_stale: legs.empty?,
        updated_at: Time.current.iso8601
      }
    end

    private

    def fallback_spot_price(index_key)
      case index_key
      when 'NIFTY'
        Live::TickCache.fetch('IDX_I', '13')&.dig(:ltp) || Live::TickCache.fetch('IDX_I', '13')&.dig(:prev_close)
      when 'BANKNIFTY'
        Live::TickCache.fetch('IDX_I', '25')&.dig(:ltp) || Live::TickCache.fetch('IDX_I', '25')&.dig(:prev_close)
      when 'SENSEX'
        Live::TickCache.fetch('IDX_I', '51')&.dig(:ltp) || Live::TickCache.fetch('IDX_I', '51')&.dig(:prev_close)
      end
    end

    def nearest_atm(spot, legs)
      strikes = legs.pluck(:strike).uniq
      return nil if strikes.empty?

      strikes.min_by { |s| (s - spot).abs }
    end

    def formatted_legs(legs)
      legs.map do |l|
        {
          strike: l[:strike],
          type: l[:type],
          security_id: l[:security_id],
          segment: l[:segment],
          lot_size: l[:lot_size],
          ltp: l[:ltp]&.to_f,
          oi: l[:oi].to_i,
          oi_change: l[:oi_change].to_i,
          bid: l[:bid]&.to_f,
          ask: l[:ask]&.to_f,
          iv: l[:iv].to_f,
          volume: l[:volume].to_i,
          prev_close: l[:prev_close]&.to_f,
          delta: l[:delta].to_f,
          gamma: l[:gamma].to_f,
          theta: l[:theta].to_f,
          vega: l[:vega].to_f
        }
      end
    end
  end
end
