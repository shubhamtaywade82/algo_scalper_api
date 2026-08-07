# frozen_string_literal: true

module Api
  # REST API for strategy lifecycle management.
  # All endpoints require dashboard token authentication.
  class StrategiesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :find_strategy, only: %i[show start stop restart versions signals logs variables update_variables]

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
      return render json: { success: false, error: "Invalid slug" }, status: :unprocessable_content unless slug

      name = params[:name].presence || slug.humanize
      template = params[:template].presence || "basic"

      scaffold_strategy(slug, name, template)

      render json: { success: true, slug: slug, name: name, status: "draft" }, status: :created
    rescue StandardError => e
      render json: { success: false, error: e.message }, status: :unprocessable_content
    end

    # POST /api/strategies/:slug/deploy
    def deploy
      slug = params[:slug]
      result = ::Strategies::DeployPipeline.call(slug)

      if result[:ok]
        render json: { success: true, version: serialize_version(result[:version]), scan_report: result[:scan_report] }
      else
        render json: { success: false, errors: result[:errors], scan_report: result[:scan_report] },
               status: :unprocessable_content
      end
    end

    # POST /api/strategies/:slug/start
    def start
      @strategy.update!(desired_status: "running")
      try_nudge_manager
      render json: { success: true, slug: @strategy.slug, status: "starting" }, status: :accepted
    end

    # POST /api/strategies/:slug/stop
    def stop
      @strategy.update!(desired_status: "stopped")
      try_nudge_manager
      render json: { success: true, slug: @strategy.slug, status: "stopping" }, status: :accepted
    end

    # POST /api/strategies/:slug/restart
    def restart
      @strategy.update!(desired_status: "stopped")
      try_nudge_manager
      @strategy.update!(desired_status: "running")
      try_nudge_manager
      render json: { success: true, slug: @strategy.slug, status: "restarting" }, status: :accepted
    end

    # GET /api/strategies/:slug/versions
    def versions
      records = @strategy.versions.order(version: :desc).limit(50)
      render json: {
        success: true,
        versions: records.map { |v| serialize_version(v) }
      }
    end

    # GET /api/strategies/:slug/signals
    def signals
      scope = @strategy.signals.order(emitted_at: :desc)
      scope = scope.where(action: params[:filter_action]) if params[:filter_action].present?
      scope = scope.where(outcome: params[:outcome]) if params[:outcome].present?

      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 1].max, 200].min
      total = scope.count
      records = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        success: true,
        signals: records.map { |s| serialize_signal(s) },
        meta: { total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil }
      }
    end

    # GET /api/strategies/:slug/logs
    def logs
      limit = [params[:limit].to_i, 1].max
      limit = [limit, 1000].min

      entries = ::Strategies::LogStream.fetch(@strategy.slug, limit: limit)
      render json: { success: true, logs: entries }
    end

    # GET /api/strategies/:slug/variables
    def variables
      vars = ::PlatformVariable.for_strategy(@strategy.id)
      render json: { success: true, variables: vars.map { |v| serialize_variable(v) } }
    end

    # PUT /api/strategies/:slug/variables
    def update_variables
      updates = params.permit(variables: %i[key value value_type secret])[:variables]
      return render json: { success: false, error: "Missing variables" }, status: :unprocessable_content unless updates

      upserted = updates.map { |var| upsert_variable(var, @strategy.id) }

      render json: { success: true, variables: upserted.map { |v| serialize_variable(v) } }
    end

    private

    def find_strategy
      @strategy = ::Strategies::Record.find_by!(slug: params[:slug])
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: "Strategy not found: #{params[:slug]}" }, status: :not_found
    end

    def find_manager
      return nil unless defined?(::Strategies::Manager)

      ObjectSpace.each_object(::Strategies::Manager).first
    end

    def try_nudge_manager
      # The manager's control loop polls every 2s, so no direct nudge needed.
      # This is consistent with D-02.4: "daemon reconciles" design.
    end

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
        instruments: ["NIFTY", "BANKNIFTY", "SENSEX"],
        description: "Adaptive Supertrend & technical indicators signal generator for index options scalping.",
        runtime: "Ruby 3.3 / Rails 8",
        timeframe: "1m",
        last_heartbeat: runner&.dig(:last_heartbeat),
        error_count: runner&.dig(:error_count) || 0,
        runner_status: runner
      }
    end


    def serialize_version(v)
      {
        id: v.id,
        version: v.version,
        checksum: v.checksum,
        file_path: v.file_path,
        deployed_at: v.deployed_at,
        scan_summary: v.scan_report&.slice("blocked_count", "warning_count", "findings")
      }
    end

    def serialize_signal(s)
      {
        id: s.id,
        instrument_key: s.instrument_key,
        action: s.action,
        confidence: s.confidence,
        reason: s.reason,
        outcome: s.outcome,
        emitted_at: s.emitted_at
      }
    end

    def serialize_variable(v)
      {
        id: v.id,
        key: v.key,
        value: v.secret ? "•••" : v.value,
        value_type: v.value_type,
        secret: v.secret
      }
    end

    def resolve_params_schema
      return {} unless @strategy.current_version

      manifest = @strategy.current_version.manifest
      manifest["params"] || {}
    end

    def upsert_variable(attrs, strategy_id)
      variable = ::PlatformVariable.find_or_initialize_by(
        scope: "strategy",
        strategy_id: strategy_id,
        key: attrs[:key]
      )
      variable.value_type = attrs[:value_type] || "string"
      variable.secret = ActiveModel::Type::Boolean.new.cast(attrs[:secret]) if attrs.key?(:secret)

      case variable.value_type
      when "string"  then variable.string_value = attrs[:value].to_s
      when "decimal" then variable.decimal_value = attrs[:value].to_f
      when "boolean" then variable.boolean_value = ActiveModel::Type::Boolean.new.cast(attrs[:value])
      when "json"    then variable.json_value = attrs[:value]
      end

      variable.save!
      variable
    end
  end
end
