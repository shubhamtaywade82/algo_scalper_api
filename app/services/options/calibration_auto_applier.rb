# frozen_string_literal: true

module Options
  # Applies a fresh CalibrationRun to algo_config_overrides when config gates pass.
  #
  # Historical path: weekly DhanHQ expired-options stats → CalibrationConfigPatchBuilder.
  # AI path: recent paper trades → Ollama → proposed_patch (still validated in Runner).
  #
  # All gates default conservative: off unless explicitly enabled in config/algo.yml.
  class CalibrationAutoApplier
    Result = Struct.new(:applied, :reason, :suppress_notification)

    DEFAULT_MIN_WEEKS = 4
    DEFAULT_MIN_AI_TRADES = 15

    def self.call(run:, source:)
      new(run: run, source: source).call
    end

    def initialize(run:, source:)
      @run = run
      @source = source.to_sym
    end

    def call
      return skip('run missing', suppress: true) if @run.blank?
      return skip('already applied', suppress: true) if @run.applied_at.present?
      return skip('empty proposed_patch') if @run.proposed_patch.blank?

      cfg = auto_apply_cfg
      return skip('calibration.auto_apply.enabled is false', suppress: true) unless truthy?(cfg[:enabled])

      unless source_allowed?(cfg)
        return skip("calibration.auto_apply.#{source_flag_key} is false", suppress: true)
      end

      if truthy?(cfg[:require_paper_trading]) && !paper_trading?
        return skip('require_paper_trading: not in paper mode')
      end

      if truthy?(cfg[:reject_on_regime_shift]) && @run.is_regime_shift
        return skip("regime shift flagged: #{@run.regime_reason}")
      end

      cooldown_reason = cooldown_block_reason(cfg)
      return skip(cooldown_reason) if cooldown_reason

      insufficient = insufficient_history_reason(cfg)
      return skip(insufficient) if insufficient

      @run.apply!(applied_by: applied_by_label)
      log_applied
      Result.new(true, nil, false)
    rescue StandardError => e
      Rails.logger.error("[CalibrationAutoApplier] #{e.class} — #{e.message}")
      Result.new(false, e.message, false)
    end

    private

    def skip(reason, suppress: false)
      Rails.logger.info("[CalibrationAutoApplier] Skipped CalibrationRun ##{@run&.id}: #{reason}")
      Result.new(false, reason, suppress)
    end

    def auto_apply_cfg
      cal = AlgoConfig.fetch[:calibration]
      return {} unless cal.is_a?(Hash)

      aa = cal[:auto_apply]
      aa.is_a?(Hash) ? aa : {}
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def paper_trading?
      truthy?(AlgoConfig.fetch.dig(:paper_trading, :enabled))
    end

    def source_allowed?(cfg)
      case @source
      when :historical
        truthy?(cfg[:historical_weekly])
      when :ai
        truthy?(cfg[:ai_trades])
      else
        false
      end
    end

    def source_flag_key
      @source == :historical ? :historical_weekly : :ai_trades
    end

    def applied_by_label
      "auto_#{@source}"
    end

    def log_applied
      Rails.logger.info(
        "[CalibrationAutoApplier] Applied CalibrationRun ##{@run.id} symbol=#{@run.symbol} source=#{@source}"
      )
    end

    def cooldown_block_reason(cfg)
      days = cfg[:cooldown_days_between_applies].to_i
      return nil if days <= 0

      last = CalibrationRun.where(symbol: @run.symbol).where.not(applied_at: nil).order(applied_at: :desc).first
      return nil if last.blank?

      elapsed = Time.current - last.applied_at
      return nil if elapsed >= days.days

      "cooldown: last apply #{last.applied_at.in_time_zone('Asia/Kolkata').to_date} " \
        "(wait #{days}d between applies)"
    end

    def insufficient_history_reason(cfg)
      if ai_calibration_run?
        min_trades = cfg[:min_ai_trades].to_i
        min_trades = DEFAULT_MIN_AI_TRADES if min_trades <= 0
        got = dataset_total_trades
        return nil if got >= min_trades

        "insufficient AI dataset: #{got} trades (min #{min_trades})"
      else
        min_weeks = cfg[:min_weeks_analyzed].to_i
        min_weeks = DEFAULT_MIN_WEEKS if min_weeks <= 0
        got = effective_weeks_available
        return nil if got >= min_weeks

        "insufficient history: #{got} expiries available (min #{min_weeks})"
      end
    end

    def ai_calibration_run?
      @run.strike_mode.to_s == 'ai_calibration' || @source == :ai
    end

    def effective_weeks_available
      rs = @run.raw_stats
      return @run.weeks_analyzed.to_i unless rs.is_a?(Hash)

      w = rs[:weeks_available] || rs['weeks_available']
      w.present? ? w.to_i : @run.weeks_analyzed.to_i
    end

    def dataset_total_trades
      rs = @run.raw_stats
      return 0 unless rs.is_a?(Hash)

      meta = rs[:dataset_meta] || rs['dataset_meta']
      return 0 unless meta.is_a?(Hash)

      (meta[:total_trades] || meta['total_trades']).to_i
    end
  end
end
