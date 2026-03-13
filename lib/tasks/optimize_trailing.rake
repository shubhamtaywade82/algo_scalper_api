# frozen_string_literal: true

namespace :optimize do
  desc 'Optimize trailing stop parameters based on MFE/MAE analytics'
  task trailing: :environment do
    indices = %w[NIFTY SENSEX BANKNIFTY]
    results = {}

    indices.each do |index|
      puts "Optimizing #{index}..."
      optimizer = Optimization::TrailingOptimizer.new(index_key: index)
      res = optimizer.optimize
      if res
        results[index.downcase] = res[:best_params]
        puts "Best for #{index}: #{res[:best_params]} (Score: #{res[:score].round(4)} from #{res[:trade_count]} trades)"
      else
        puts "No data for #{index}"
      end
    end

    if results.any?
      update_config(results)
    else
      puts "No optimization results to apply."
    end
  end

  def update_config(results)
    config_path = Rails.root.join('config/algo.yml')
    config = YAML.safe_load(File.read(config_path))

    results.each do |index, params|
      # Update institutional_trailing in config
      # Match the structure in algo.yml: risk -> institutional_trailing -> index
      if config['risk'] && config['risk']['institutional_trailing'] && config['risk']['institutional_trailing'][index]
        params.each do |key, value|
          config['risk']['institutional_trailing'][index][key.to_s] = value
        end
        puts "Updated #{index} in config/algo.yml"
      end
    end

    File.write(config_path, config.to_yaml)
    puts "Configuration saved to config/algo.yml"
  end
end
