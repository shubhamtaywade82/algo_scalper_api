# Paper-mode / boot sanity for the scalp exit stack against real config/algo.yml.
# Run: RAILS_ENV=test bundle exec rails runner scripts/scalp_boot_sanity.rb
cfg = AlgoConfig.fetch

puts "run_mode: #{cfg[:run_mode].inspect}"
scalp_exit = cfg.dig(:risk, :scalp_exit) || {}
puts "risk.scalp_exit.enabled: #{scalp_exit[:enabled].inspect} (#{scalp_exit.except(:enabled).inspect})"
ms = cfg.dig(:risk, :underlying_context_exit, :momentum_scaling) || {}
puts "momentum_scaling.enabled: #{ms[:enabled].inspect}"
chain_ctx = cfg.dig(:risk, :scalp_exit, :chain_context) || {}
puts "chain_context keys: #{chain_ctx.keys.inspect}"
pnl_exit = cfg.dig(:risk, :percentage_pnl_exit) || {}
puts "percentage_pnl_exit: #{pnl_exit.inspect}"

puts "Scalp::FeeAwareExitTargets.enabled? = #{Scalp::FeeAwareExitTargets.enabled?}"
puts "Scalp::MomentumScaler.enabled?      = #{Scalp::MomentumScaler.enabled?}"
puts "Scalp::MomentumScaler death/mult    = #{Scalp::MomentumScaler.from_config.death?(0.25)} / " \
     "#{Scalp::MomentumScaler.from_config.multiplier(0.75)}"

# Fee math against the shipped config with a live-ish tracker double:
nifty = Scalp::FeeAwareExitTargets.new(
  OpenStruct.new(entry_price: 150.0, quantity: 75)
)
puts "NIFTY 150x75: friction=#{nifty.friction_pct&.round(5)} " \
     "min_target(0.05)=#{nifty.min_target_pct(0.05).round(4)} " \
     "breakeven_lock=#{nifty.breakeven_lock_price.inspect}"

sensex = Scalp::FeeAwareExitTargets.new(
  OpenStruct.new(entry_price: 50.0, quantity: 20)
)
puts "SENSEX 50x20:  friction=#{sensex.friction_pct&.round(5)} " \
     "min_target(0.05)=#{sensex.min_target_pct(0.05).round(4)} " \
     "breakeven_lock=#{sensex.breakeven_lock_price.inspect}"
puts "SANITY_OK"
