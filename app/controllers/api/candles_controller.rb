# frozen_string_literal: true

module Api
  # Read-only OHLC candle series for the dashboard charting view.
  # Wraps the same DhanHQ intraday historical-data source used by Signal::Engine /
  # alpha strategies — no order/gateway involvement.
  class CandlesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    ALLOWED_INTERVALS = %w[1 5 15 25 60].freeze
    MAX_DAYS = 30

    def index
      index_key = params[:index_key].to_s.upcase
      instrument = find_instrument(index_key)
      return render json: { error: 'Index not found' }, status: :not_found unless instrument

      interval = ALLOWED_INTERVALS.include?(params[:interval].to_s) ? params[:interval].to_s : '5'
      days = (params[:days] || 5).to_i.clamp(1, MAX_DAYS)

      bars = fetch_bars(instrument, interval: interval, days: days)

      render json: {
        index_key: index_key,
        interval: interval,
        candles: bars.map { |bar| serialize_bar(bar) }
      }
    rescue StandardError => e
      Rails.logger.error("[Api::CandlesController] #{e.class}: #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    private

    def find_instrument(index_key)
      index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
      return nil unless index_cfg

      Instrument.find_by_sid_and_segment(
        security_id: index_cfg[:sid],
        segment_code: index_cfg[:segment]
      )
    end

    # DhanHQ intraday fetch is the slow part (network round-trip per request).
    # Cache the raw bars per index/interval/days — TTL scaled to the candle size so
    # the cache naturally refreshes roughly once per bar close. Keyed by today's date
    # so the cache can't bleed stale data across sessions.
    def fetch_bars(instrument, interval:, days:)
      cache_key = "candles/#{instrument.security_id}/#{interval}/#{days}d/#{Time.zone.today}"
      Rails.cache.fetch(cache_key, expires_in: cache_ttl(interval)) do
        DhanHQ::Models::HistoricalData.intraday(
          security_id: instrument.security_id,
          exchange_segment: instrument.exchange_segment,
          instrument: DhanHQ::Constants::InstrumentType::INDEX,
          interval: interval,
          from_date: (Time.zone.today - days.days).to_s,
          to_date: Time.zone.today.to_s
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[Api::CandlesController] historical fetch failed: #{e.message}")
      []
    end

    def cache_ttl(interval)
      { '1' => 30.seconds, '5' => 1.minute, '15' => 3.minutes, '25' => 5.minutes, '60' => 10.minutes }
        .fetch(interval, 1.minute)
    end

    def serialize_bar(bar)
      {
        time: bar_timestamp(bar),
        open: bar_value(bar, :open),
        high: bar_value(bar, :high),
        low: bar_value(bar, :low),
        close: bar_value(bar, :close),
        volume: bar_value(bar, :volume)
      }
    end

    def bar_value(bar, key)
      (bar[key] || bar[key.to_s]).to_f
    end

    def bar_timestamp(bar)
      raw = bar[:timestamp] || bar['timestamp'] || bar[:start_time] || bar['start_time']
      return raw.to_i if raw.is_a?(Numeric)

      Time.zone.parse(raw.to_s)&.to_i
    end
  end
end
