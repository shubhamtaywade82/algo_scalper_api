# frozen_string_literal: true

class GetAlgoConfigTool < ApplicationMCPTool
  # Credential-bearing sections (AlgoConfig::SENSITIVE_SECTIONS) are excluded outright;
  # remaining sections still pass through redact for stray secret-looking keys.
  CONFIG_SECTIONS = %w[
    paper_trading ledger realtime trading_time_restrictions midday_guard
    expiry_week_power_trend loss_streak_guard sizing feature_flags trade_limits
    broker_fees risk position_sizing profit_lock market_context signals
    chain_analyzer option_chain data_freshness smc
  ].freeze

  tool_name 'get_algo_config'
  description 'Read one section of the effective algo config (YAML + profile + DB overrides). ' \
              'Credential sections (dhanhq, telegram, ai) and run_mode are not exposed. Read-only.'

  property :section, type: 'string', required: true, description: 'Config section to read', enum: CONFIG_SECTIONS

  def perform
    section_data = AlgoConfig.fetch[section.to_sym]
    return render_json(error: "unknown or unavailable section #{section}") if section_data.nil?

    render_json(section: section, config: redact(section_data))
  end
end
