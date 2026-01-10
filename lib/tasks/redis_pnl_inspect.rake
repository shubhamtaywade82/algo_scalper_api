# frozen_string_literal: true

# lib/tasks/redis_pnl_inspect.rake
namespace :redis do
  desc 'Inspect pnl:tracker:* keys with color-coded PnL'
  task inspect: :environment do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    keys = redis.keys('pnl:tracker:*')
    if keys.empty?
      puts 'No pnl:tracker keys found.'
      next
    end

    keys.each do |key|
      data = redis.hgetall(key)
      pnl = data['pnl']&.to_f
      pnl_pct = data['pnl_pct']&.to_f
      ltp = data['ltp']&.to_f
      updated = Time.zone.at(data['updated_at'].to_i).strftime('%H:%M:%S')

      color =
        if pnl.to_f.positive?
          "\e[32m"  # green
        elsif pnl.to_f.negative?
          "\e[31m"  # red
        else
          "\e[33m"  # yellow
        end

      puts "#{color}#{key.ljust(25)} PnL=#{pnl.round(2)} (#{(pnl_pct * 100).round(2)}%) LTP=#{ltp.round(2)} updated=#{updated}\e[0m"
    end
  end
end
