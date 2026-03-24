# frozen_string_literal: true

namespace :backtest do
  desc 'SMC historical replay (spot metrics + optional permission + optional option PnL). ' \
       'Usage: BACKTEST_MODE=1 bundle exec rake backtest:smc[NIFTY,30] ' \
       '(symbol, days_back, forward_horizon, min_bars, include_permission, simulate_options). ' \
       'Env: SMC_REPLAY_OPTIONS=1 to simulate options; SMC_REPLAY_PERMISSION=0 to skip permission labels.'
  task :smc, %i[symbol days_back forward_horizon min_bars include_permission simulate_options] => :environment do |_t, args|
    ENV['BACKTEST_MODE'] = '1'

    symbol = (args[:symbol] || ENV['SMC_REPLAY_SYMBOL'] || 'NIFTY').to_s
    days_back = (args[:days_back] || ENV['SMC_REPLAY_DAYS'] || '30').to_i
    forward_horizon = (args[:forward_horizon] || ENV['SMC_REPLAY_HORIZON'] || '12').to_i
    min_bars = (args[:min_bars] || ENV['SMC_REPLAY_MIN_BARS'] || '25').to_i
    include_permission = args[:include_permission] != 'false' &&
                         ENV['SMC_REPLAY_PERMISSION'] != 'false'
    simulate_options = args[:simulate_options] == 'true' ||
                       ENV['SMC_REPLAY_OPTIONS'] == 'true'

    runner = Backtest::SmcReplayRunner.new(
      symbol: symbol,
      days_back: days_back,
      forward_horizon: forward_horizon,
      min_bars: min_bars,
      include_permission: include_permission,
      simulate_options: simulate_options
    )

    result = runner.call
    if result[:error]
      puts "[backtest:smc] #{result[:error]}"
      exit 1
    end

    runner.print_summary
  end
end
