# frozen_string_literal: true

module Api
  # Shared by StrategiesController and the controllers nested under /api/strategies/:strategy_slug.
  module StrategyScoped
    extend ActiveSupport::Concern

    private

    def strategy_slug
      params[:strategy_slug] || params[:slug]
    end

    def find_strategy
      @strategy = ::Strategies::Record.find_by!(slug: strategy_slug)
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: "Strategy not found: #{strategy_slug}" }, status: :not_found
    end

    def find_manager
      return nil unless defined?(::Strategies::Manager)

      ObjectSpace.each_object(::Strategies::Manager).first
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
  end
end
