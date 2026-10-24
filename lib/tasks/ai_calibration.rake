# frozen_string_literal: true

namespace :ai do
  desc 'Run AI calibration for one or all symbols. Usage: rake ai:calibrate[NIFTY,30]'
  task :calibrate, %i[symbol days] => :environment do |_, args|
    symbol = args[:symbol]&.upcase
    days   = (args[:days] || 30).to_i

    symbols = symbol ? [symbol] : %w[NIFTY BANKNIFTY SENSEX]

    puts "[AI Calibration] Running for: #{symbols.join(', ')} | Days: #{days}"
    puts '=' * 60

    symbols.each do |sym|
      puts "\n[#{sym}] Building dataset..."

      run = Ai::Calibration::Runner.call(symbol: sym, days: days)

      if run
        puts "[#{sym}] ✅ CalibrationRun ##{run.id} created"
        puts "[#{sym}] Primary failure: #{run.raw_stats.dig('diagnosis', 'primary_failure')}"
        puts "[#{sym}] Proposed patch:"
        puts JSON.pretty_generate(run.proposed_patch)
        puts ''
        puts "[#{sym}] To apply:"
        puts "         CalibrationRun.find(#{run.id}).apply!(applied_by: 'rake')"
      else
        puts "[#{sym}] ⚠️  No actionable calibration produced (insufficient data or AI unavailable)"
      end

    rescue Ai::Calibration::Runner::InsufficientDataError => e
      puts "[#{sym}] ⚠️  #{e.message}"
    rescue StandardError => e
      puts "[#{sym}] ❌ Error: #{e.class} — #{e.message}"
      puts e.backtrace.first(3).join("\n") if ENV['DEBUG']
    end

    puts "\n[AI Calibration] Done."
  end

  desc 'Apply a pending CalibrationRun by ID. Usage: rake ai:apply_calibration[42]'
  task :apply_calibration, [:run_id] => :environment do |_, args|
    run_id = args[:run_id]&.to_i
    raise ArgumentError, 'run_id required' unless run_id&.positive?

    run = CalibrationRun.find(run_id)

    if run.applied_at.present?
      puts "[AI Calibration] CalibrationRun ##{run_id} already applied at #{run.applied_at}"
      exit 0
    end

    puts "[AI Calibration] Proposed patch for #{run.symbol}:"
    puts JSON.pretty_generate(run.proposed_patch)
    puts ''
    puts 'Applying...'

    run.apply!(applied_by: 'rake')

    puts "✅ Applied CalibrationRun ##{run_id} at #{run.applied_at}"
  rescue ActiveRecord::RecordNotFound
    puts "❌ CalibrationRun ##{run_id} not found"
    exit 1
  end
end
