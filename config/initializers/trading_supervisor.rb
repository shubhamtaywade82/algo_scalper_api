# frozen_string_literal: true

# --------------------------------------------------------------------
# REGISTER-ONLY INITIALIZER (no auto-start)
# --------------------------------------------------------------------
#
# Trading services are started by a separate process:
#   ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
#
# The web server should not auto-start long-running threads.
if Rails.env.test? ||
   defined?(Rails::Console) ||
   (defined?(Rails::Generators) && Rails::Generators.const_defined?(:Base)) ||
   ENV['BACKTEST_MODE'] == '1' ||
   ENV['SCRIPT_MODE'] == '1' ||
   ENV['DISABLE_TRADING_SERVICES'] == '1'
  return
end

Rails.application.config.to_prepare do
  Rails.application.config.x.trading_supervisor = TradingSystem::Bootstrap.build_supervisor
end
