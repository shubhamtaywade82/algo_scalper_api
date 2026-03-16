# frozen_string_literal: true

# Shared session detection from risk.time_regimes config.
# Compares current IST time against configured session boundaries.
module SessionDetector
  def detect_current_session
    time_regimes = AlgoConfig.fetch.dig(:risk, :time_regimes)
    return nil unless time_regimes.is_a?(Hash)

    now = Time.current.in_time_zone('Asia/Kolkata')
    current_hhmm = now.strftime('%H:%M')

    time_regimes.each do |name, cfg|
      next unless cfg.is_a?(Hash)

      start_time = cfg[:start] || cfg['start']
      end_time = cfg[:end] || cfg['end']
      next unless start_time && end_time

      return name.to_sym if current_hhmm >= start_time.to_s && current_hhmm < end_time.to_s
    end

    nil
  end
end
