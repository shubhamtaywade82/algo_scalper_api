# frozen_string_literal: true

module Strategies
  # Bridges the Strategy Creator UI (TradingStrategy) onto the real
  # Strategies::Manager plugin platform: renders manifest.yml + strategy.rb
  # to disk under strategies/<slug>/ and runs the existing DeployPipeline.
  class AdHocDeployer
    STRATEGIES_ROOT = Rails.root.join("strategies")
    CLASS_NAME_PATTERN = /^\s*class\s+([A-Z]\w*)\s*<\s*(\S+)/

    def self.call(trading_strategy)
      new(trading_strategy).call
    end

    def initialize(trading_strategy)
      @trading_strategy = trading_strategy
      @errors = []
    end

    def call
      class_name, superclass_name = extract_class_info
      return error_result("No strategy class found in code (expected `class Foo < Strategies::Base` or `< BaseStrategy`)") unless class_name

      slug = @trading_strategy.slugify
      write_files(slug, class_name, superclass_name)

      result = DeployPipeline.call(slug)
      return error_result(*result[:errors]) unless result[:ok]

      link_and_activate(slug, result[:version])
      { ok: true, errors: [], scan_report: result[:scan_report],
        strategy_record: result[:version].strategy_record, version: result[:version] }
    end

    private

    def extract_class_info
      match = CLASS_NAME_PATTERN.match(@trading_strategy.code.to_s)
      return nil unless match

      [match[1], match[2]]
    end

    def write_files(slug, class_name, superclass_name)
      dir = STRATEGIES_ROOT.join(slug)
      dir.mkpath

      dir.join("strategy.rb").write(render_strategy_rb(class_name, superclass_name))
      dir.join("manifest.yml").write(render_manifest(slug, class_name))
    end

    def render_strategy_rb(class_name, superclass_name)
      body = @trading_strategy.code.to_s
      return body if superclass_name == "Strategies::Base"

      # Legacy scaffold code subclasses `BaseStrategy` — alias it so it loads
      # under the real platform without requiring the user to edit their code.
      "BaseStrategy = Strategies::Base unless defined?(BaseStrategy)\n\n#{body}"
    end

    def render_manifest(slug, class_name)
      {
        "slug" => slug,
        "name" => @trading_strategy.name,
        "class_name" => class_name,
        "timeframes" => [@trading_strategy.timeframe].compact,
        "instruments" => @trading_strategy.instruments.presence || ["NIFTY"],
        "params" => params_schema
      }.to_yaml
    end

    def params_schema
      Array(@trading_strategy.parameters).each_with_object({}) do |p, schema|
        next if p["name"].blank?

        schema[p["name"]] = { "type" => p["type"], "default" => p["default_value"] }
      end
    end

    def link_and_activate(slug, version)
      @trading_strategy.update!(
        slug: slug,
        strategy_record_id: version.strategy_id,
        status: TradingStrategy::STATUS_ACTIVE
      )
    end

    def error_result(*errors)
      { ok: false, errors: errors, scan_report: nil, strategy_record: nil, version: nil }
    end
  end
end
