# frozen_string_literal: true

module Entries
  module Guards
    # Detects the "expiry-week afternoon power trend" pattern and enriches entry context.
    #
    # Pattern: High-ADX directional move (ADX >= 40) during the final week before monthly
    # expiry, entered in the 12:00-13:45 window. Near-ATM options return 3-6x on a
    # 0.8-1.4% spot move due to elevated gamma. Does NOT block entries — only enriches
    # context[:expiry_power_trend] = true when the pattern is detected.
    #
    # Required pipeline position: AFTER InstrumentLookupGuard (needs context[:instrument])
    # and BEFORE TimeRegimeGuard (so it can bypass the S3 chop-zone block).
    class ExpiryWeekPowerTrendGuard
      DEFAULT_ADX_MIN = 40
      DEFAULT_EXPIRY_DAYS_MAX = 5
      DEFAULT_ENTRY_START = '12:00'
      DEFAULT_ENTRY_END = '13:45'

      class << self
        include BaseGuard

        def call(context)
          return PASS unless enabled?
          return PASS unless entry_window?
          return PASS unless power_trend?(context)
          return PASS unless expiry_week?(context)

          context[:expiry_power_trend] = true
          (context[:entry_metadata] ||= {})[:expiry_power_trend] = true

          PASS
        end

        private

        def config
          AlgoConfig.fetch.dig(:expiry_week_power_trend) || {}
        rescue StandardError
          {}
        end

        def enabled?
          config[:enabled] == true
        end

        def adx_min
          config[:adx_min]&.to_f || DEFAULT_ADX_MIN
        end

        def expiry_days_max
          config[:expiry_days_max]&.to_i || DEFAULT_EXPIRY_DAYS_MAX
        end

        def entry_start
          config[:entry_start].presence || DEFAULT_ENTRY_START
        end

        def entry_end
          config[:entry_end].presence || DEFAULT_ENTRY_END
        end

        def entry_window?
          time = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
          time.between?(entry_start, entry_end)
        end

        def power_trend?(context)
          adx = context.dig(:pick, :adx_value)&.to_f
          adx.present? && adx >= adx_min
        end

        def expiry_week?(context)
          instrument = context[:instrument]
          today = Time.zone.today
          expiry = nearest_monthly_expiry(instrument, today)
          return false if expiry.nil?

          days = (expiry - today).to_i
          days.between?(0, expiry_days_max)
        rescue StandardError
          false
        end

        # Finds the nearest upcoming monthly expiry date.
        # Uses DhanHQ expiry_list from the instrument when available;
        # falls back to last-Thursday-of-month heuristic.
        def nearest_monthly_expiry(instrument, today)
          expiry_list = instrument&.expiry_list&.compact
          if expiry_list.present?
            parsed = expiry_list.filter_map { |raw| coerce_date(raw) }.uniq.sort
            monthly = parsed
              .group_by { |d| [d.year, d.month] }
              .map { |_, dates| dates.max }
              .sort
            nearest = monthly.find { |d| d >= today }
            return nearest if nearest
          end

          last_thursday_on_or_after(today)
        end

        def last_thursday_on_or_after(from)
          last_day = from.end_of_month
          thu = last_day - ((last_day.wday - 4) % 7).days
          return thu if thu >= from

          last_day = (from >> 1).end_of_month
          last_day - ((last_day.wday - 4) % 7).days
        end

        def coerce_date(raw)
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String then Date.parse(raw)
          end
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
