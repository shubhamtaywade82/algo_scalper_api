# frozen_string_literal: true

# Pre-market job that seeds the IvRankTracker with historical IV samples
# from expired option chains, so percentile-rank calculations are meaningful
# as soon as the market opens (without waiting for 30+ live samples).
class PreMarketIvBaselineJob < ApplicationJob
  queue_as :background

  MAX_WEEKS = 6
  MAX_DAYS  = 31

  def perform
    IndexConfigLoader.load_indices.each do |cfg|
      index_key = cfg[:key].to_s
      next if index_key.blank?

      seed_baseline_for(index_key, cfg)
    rescue StandardError => e
      Rails.logger.warn("[PreMarketIvBaselineJob] #{index_key}: #{e.class} - #{e.message}")
    end
  end

  private

  def seed_baseline_for(index_key, cfg)
    samples = historical_iv_samples(index_key, cfg)
    return if samples.empty?

    ok = Options::IvRankTracker.instance.seed_history(index_key: index_key, samples: samples)
    Rails.logger.info(
      "[PreMarketIvBaselineJob] #{index_key}: seeded #{samples.size} IV samples (seed_ok=#{ok})"
    )
  rescue StandardError => e
    Rails.logger.warn("[PreMarketIvBaselineJob] #{index_key} seed failed: #{e.class} - #{e.message}")
  end

  # Pulls expired-options ATM IV time-series for the past N weeks and
  # collapses each day into a single average CE+PE ATM IV.
  def historical_iv_samples(index_key, cfg)
    security_id = (cfg[:sid] || cfg[:security_id]).to_s
    segment     = (cfg[:segment] || 'NSE_FNO').to_s
    sid         = security_id.presence || resolve_security_id(index_key)
    return [] unless sid

    to_date   = Time.zone.today
    preferred  = to_date - (MAX_WEEKS * 7).days
    from_date  = [preferred, to_date - MAX_DAYS.days].max
    if from_date > preferred
      Rails.logger.info(
        "[PreMarketIvBaselineJob] #{index_key}: clamped IV history window from #{preferred} to #{from_date} " \
        "(#{((to_date - from_date).to_i)} days) to honor DhanHQ 31-day limit"
      )
    end

    ce_samples = fetch_daily_iv_series(sid, segment, from_date, to_date, 'CALL')
    pe_samples = fetch_daily_iv_series(sid, segment, from_date, to_date, 'PUT')

    merged_avg(ce_samples + pe_samples)
  rescue StandardError => e
    Rails.logger.warn("[PreMarketIvBaselineJob] #{index_key} history fetch failed: #{e.class} - #{e.message}")
    []
  end

  # Collapses raw per-candle IVs into one daily average IV.
  def fetch_daily_iv_series(security_id, segment, from_date, to_date, option_type)
    raw = DhanHQ::Models::ExpiredOptionsData.fetch(
      exchange_segment: segment,
      interval: '1',
      security_id: security_id,
      instrument: 'OPTIDX',
      expiry_flag: 'WEEK',
      expiry_code: 1,
      strike: 'ATM',
      drv_option_type: option_type,
      required_data: %w[open high low close volume],
      from_date: from_date.strftime('%Y-%m-%d'),
      to_date: to_date.strftime('%Y-%m-%d')
    )

    return [] unless raw&.data

    side_data = raw.data[option_type.downcase]
    return [] unless side_data&.dig('timestamp')&.any?

    timestamps = side_data['timestamp']
    ivs        = side_data['iv'] || Array.new(timestamps.size, nil)

    by_day = Hash.new { |h, k| h[k] = [] }
    timestamps.each_with_index do |ts, i|
      next unless ivs[i]

      day = Time.at(ts).in_time_zone('Asia/Kolkata').to_date.to_s
      by_day[day] << ivs[i].to_f
    end

    by_day.map do |day_str, day_ivs|
      avg = day_ivs.sum / day_ivs.size
      {
        timestamp: Date.parse(day_str).in_time_zone('Asia/Kolkata').end_of_day.to_f,
        iv: avg
      }
    end
  rescue StandardError => e
    Rails.logger.warn("[PreMarketIvBaselineJob] #{security_id} #{option_type}: #{e.class} - #{e.message}")
    []
  end

  # Average IVs from multiple option types / fetches that land on the same day,
  # then cap + dedupe to a single sample per day.
  def merged_avg(samples)
    by_ts = Hash.new { |h, k| h[k] = [] }
    samples.each { |s| by_ts[s[:timestamp]] << s[:iv] }
    by_ts.map { |ts, ivs| { timestamp: ts, iv: ivs.sum / ivs.size } }
  end

  # Fallback: look up the index security ID from configured indices.
  def resolve_security_id(index_key)
    cfg = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.casecmp(index_key.to_s).zero? }
    (cfg && cfg[:sid]).to_s.presence
  end
end
