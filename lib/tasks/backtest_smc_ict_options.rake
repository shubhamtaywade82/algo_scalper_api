# frozen_string_literal: true

namespace :backtest do
  desc 'Run SMC/ICT/Price Action options backtest. ' \
       'Usage: bundle exec rake backtest:smc_ict_options[NIFTY,30,5]'
  task :smc_ict_options, %i[symbol days_back interval] => :environment do |_t, args|
    ENV['BACKTEST_MODE'] = '1'

    symbol = (args[:symbol] || 'NIFTY').to_s
    days_back = (args[:days_back] || '30').to_i
    interval = (args[:interval] || '5').to_s

    puts "=== Running SMC/ICT/Price Action Options Backtest ==="
    puts "Symbol: #{symbol} | Days: #{days_back} | Interval: #{interval}m"

    backtest = BacktestService.run(
      symbol: symbol,
      interval: interval,
      days_back: days_back,
      strategy: SmcIctOptionBacktestStrategy
    )

    backtest.print_summary
  end
end
