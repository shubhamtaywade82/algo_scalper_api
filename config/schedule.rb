# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

set :output, "log/cron.log"
set :environment, ENV['RAILS_ENV'] || 'development'

# Update the path to your application
# set :path, '/home/nemesis/project/trading-workspace/algo_scalper_api'

# 8:45 AM Start the application using bin/dev
every :weekday, at: '8:45 am' do
  command "cd /home/nemesis/project/trading-workspace/algo_scalper_api && ./bin/dev >> log/startup.log 2>&1"
end

# 4:15 PM Stop everything (Foreman/bin/dev and all child processes)
every :weekday, at: '4:15 pm' do
  command "pkill -f 'foreman' || true"
  command "pkill -f 'rails' || true"
  command "pkill -f 'rake' || true"
  command "pkill -f 'npm' || true"
end

# To update crontab run: bundle exec whenever --update-crontab
# To clear crontab run: bundle exec whenever --clear-crontab

# Ensure instruments are imported daily at 8:45 AM (redundant with recurring.yml but good as fallback)
every :weekday, at: '8:45 am' do
  rake "instruments:import"
end
