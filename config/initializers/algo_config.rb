# frozen_string_literal: true

# Load algo configuration from config/algo.yml
Rails.application.configure do
  begin
    algo_config = YAML.load_file(Rails.root.join('config', 'algo.yml'), aliases: true)
    config.x.algo = ActiveSupport::InheritableOptions.new(algo_config.deep_symbolize_keys)
    # Rails.logger.info("[AlgoConfig] Loaded algo configuration with #{algo_config[:indices]&.size || 0} indices")
  rescue StandardError => e
    # Rails.logger.error("[AlgoConfig] Failed to load algo configuration: #{e.message}")
    config.x.algo = ActiveSupport::InheritableOptions.new({})
  end
end
