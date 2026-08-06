# frozen_string_literal: true

# disable completely?
if ENV["DISABLE_TRADING_SUPERVISOR"].to_s == "true"
  Rails.logger.info("[Supervisor] Disabled in this container")
  return
end

# --------------------------------------------------------------------
# Supervisor construction lives in TradingSystem::Bootstrap.build_supervisor,
# wired up by TradingSystem::Daemon#setup_supervisor! when the daemon process
# starts (ENABLE_TRADING_SERVICES=true). This initializer used to redefine
# TradingSystem::Supervisor and build a second, stale supervisor here, which
# raced Bootstrap's via Rails.application.config.x.trading_supervisor ||= ...
# and always won — leaving the daemon running an outdated, incomplete
# supervisor missing health_check/restart_service. Do not reintroduce that.
# --------------------------------------------------------------------
