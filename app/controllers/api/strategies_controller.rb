# frozen_string_literal: true

module Api
  # Strategy plugin records. Lifecycle sub-resources (deployment, run, versions, signals,
  # logs, variables) live in the Strategy*Controller classes nested under /api/strategies/:slug.
  class StrategiesController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::VariableSerialization
    include Api::StrategyScoped

    before_action :authenticate_dashboard_token!
    before_action :find_strategy, only: :show

    STRATEGIES_ROOT = Rails.root.join("strategies")

    # GET /api/strategies
    def index
      records = ::Strategies::Record.includes(:current_version).order(:slug)
      manager = find_manager

      render json: {
        success: true,
        strategies: records.map { |r| serialize_strategy(r, manager) }
      }
    end

    # GET /api/strategies/:slug
    def show
      manager = find_manager
      runner = manager&.runner_status(@strategy.slug)
      variables = ::PlatformVariable.for_strategy(@strategy.id).map { |v| serialize_variable(v) }

      render json: {
        success: true,
        strategy: serialize_strategy(@strategy, manager).merge(
          manifest: @strategy.current_version&.manifest,
          params_schema: resolve_params_schema,
          variables: variables,
          runner: runner
        )
      }
    end

    # POST /api/strategies
    def create
      slug = params.require(:slug).to_s.parameterize.presence
      begin
        slug = ::Strategies::SlugValidator.validate!(slug)
      rescue ::Strategies::SlugValidator::InvalidSlug => e
        return render json: { success: false, error: e.message }, status: :unprocessable_content
      end

      name = params[:name].presence || slug.humanize
      template = params[:template].presence || "basic"
      begin
        template = ::Strategies::SlugValidator.validate!(template, what: 'template')
      rescue ::Strategies::SlugValidator::InvalidSlug => e
        return render json: { success: false, error: e.message }, status: :unprocessable_content
      end

      scaffold_strategy(slug, name, template)

      render json: { success: true, slug: slug, name: name, status: "draft" }, status: :created
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :unprocessable_content
    end

    private

    def scaffold_strategy(slug, name, template)
      target_dir = STRATEGIES_ROOT.join(slug)
      raise "Strategy directory already exists: #{target_dir}" if target_dir.exist?

      template_dir = STRATEGIES_ROOT.join("_templates", template)
      raise "Unknown template: #{template}" unless template_dir.exist?

      FileUtils.cp_r(template_dir.to_s, target_dir.to_s)

      manifest_path = target_dir.join("manifest.yml")
      if manifest_path.exist?
        manifest = YAML.safe_load_file(manifest_path)
        manifest["slug"] = slug
        manifest["name"] = name
        File.write(manifest_path, manifest.to_yaml)
      end

      ::Strategies::Record.create!(
        slug: slug,
        name: name,
        status: "draft"
      )
    end

    def serialize_strategy(r, manager)
      runner = manager&.runner_status(r.slug)
      {
        id: r.id,
        slug: r.slug,
        name: r.name,
        status: r.status,
        desired_status: r.desired_status,
        current_version: r.current_version ? serialize_version(r.current_version) : nil,
        version: r.current_version&.version || 1,
        instruments: %w[NIFTY BANKNIFTY SENSEX],
        description: "Adaptive Supertrend & technical indicators signal generator for index options scalping.",
        runtime: "Ruby 3.3 / Rails 8",
        timeframe: "1m",
        last_heartbeat: runner&.dig(:last_heartbeat),
        error_count: runner&.dig(:error_count) || 0,
        runner_status: runner
      }
    end

    def resolve_params_schema
      return {} unless @strategy.current_version

      manifest = @strategy.current_version.manifest
      manifest["params"] || {}
    end
  end
end
