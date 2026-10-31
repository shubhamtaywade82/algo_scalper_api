# frozen_string_literal: true

# Investing domain configuration bootstrap (TDD §5.2).
#
# Loads config/investing.yml ONCE at boot into Rails.application.config.x so
# Investing::Config (autoloaded) stays a cheap reader at call time. The two
# fail-closed checks below are inlined because Rails does not allow
# autoloading application constants during initialization — Investing::Config
# re-implements them (tested) for programmatic callers.

investing_config = Rails.application.config_for(:investing).deep_symbolize_keys

mode = investing_config.dig(:execution, :mode).to_s
unless %w[paper live].include?(mode)
  raise "config/investing.yml: execution.mode must be paper or live (got #{mode.inspect})"
end

if mode == "live" && investing_config.dig(:execution, :require_approval) == false
  raise "config/investing.yml: require_approval cannot be false while mode is live"
end

Rails.application.config.x.investing = investing_config
