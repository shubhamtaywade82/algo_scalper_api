# frozen_string_literal: true

namespace :optimize do
  desc 'Optimize trailing stop parameters based on MFE/MAE analytics (proposes CalibrationRun for approval)'
  task trailing: :environment do
    indices = %w[NIFTY SENSEX BANKNIFTY]
    auto_apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', 'false'))
    created_runs = []

    indices.each do |index|
      puts "Optimizing #{index}..."
      optimizer = Optimization::TrailingOptimizer.new(index_key: index)
      res = optimizer.optimize
      unless res
        puts "No data for #{index}"
        next
      end

      puts "Best for #{index}: #{res[:best_params]} (Score: #{res[:score].round(4)} from #{res[:trade_count]} trades)"

      patch = Options::CalibrationConfigPatchBuilder.from_trailing_params(
        symbol: index,
        params: res[:best_params]
      )
      if patch.blank?
        puts "No significant trailing changes for #{index} (below 10% threshold)"
        next
      end

      run = CalibrationRun.create!(
        symbol: index,
        weeks_analyzed: 0,
        strike_mode: 'trailing_optimizer',
        raw_stats: {
          source: 'trailing_optimizer',
          trade_count: res[:trade_count],
          score: res[:score],
          best_params: res[:best_params]
        },
        proposed_patch: patch
      )
      run.propose_config!
      created_runs << run
      puts "Created CalibrationRun ##{run.id} for #{index} (pending approval)"
    end

    if created_runs.empty?
      puts 'No optimization results to propose.'
      next
    end

    if auto_apply
      created_runs.each do |run|
        run.apply!(applied_by: 'rake_optimize_trailing')
        puts "Applied CalibrationRun ##{run.id} for #{run.symbol}"
      end
    else
      puts 'Proposed patches saved. Apply via POST /api/calibration_runs/:id/apply or rerun with APPLY=1.'
    end
  end
end
