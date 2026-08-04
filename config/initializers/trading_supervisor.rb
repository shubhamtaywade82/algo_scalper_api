# frozen_string_literal: true

# disable completely?
if ENV["DISABLE_TRADING_SUPERVISOR"].to_s == "true"
  Rails.logger.info("[Supervisor] Disabled in this container")
  return
end

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
  (defined?(Rails::Generators) && Rails::Generators.const_defined?(:Base))
 return
end

# bin/dev uses Puma, not Rails::Server
# is_web_process =
#  $PROGRAM_NAME.include?("puma") ||
#  $PROGRAM_NAME.include?("rails") ||
#  ENV["WEB_CONCURRENCY"].present?

# Running inside worker, not web
is_worker = ENV["WORKER_MODE"].to_s == "true"
return unless is_worker

# return unless is_web_process

# --------------------------------------------------------------------
# SUPERVISOR - NO SINGLETONS
# --------------------------------------------------------------------
module TradingSystem
 class Supervisor
   def initialize
     @services = {}     # { name => service_instance }
     @running  = false
   end

   def register(name, instance)
     @services[name] = instance
   end

   def [](name)
     @services[name]
   end

   def start_all
     return if @running

     @services.each do |name, service|
       begin
         service.start
         Rails.logger.info("[Supervisor] started #{name}")
       rescue => e
         Rails.logger.error("[Supervisor] failed starting #{name}: #{e.class} - #{e.message}")
       end
     end

     @running = true
   end

   def stop_all
     return unless @running

     @services.reverse_each do |name, service|
       begin
         service.stop
         Rails.logger.info("[Supervisor] stopped #{name}")
       rescue => e
         Rails.logger.error("[Supervisor] error stopping #{name}: #{e.class} - #{e.message}")
       end
     end

     @running = false
   end
 end
end

Rails.application.config.to_prepare do
  Rails.application.config.x.trading_supervisor = TradingSystem::Bootstrap.build_supervisor
end
