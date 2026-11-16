# frozen_string_literal: true

module Api
  # ?since= / ?until= filter on exited_at shared by the report endpoints.
  module ReportDateRange
    extend ActiveSupport::Concern

    private

    def date_filtered_scope(scope)
      scope = scope.where(exited_at: params[:since].presence&.to_time..) if params[:since].present?
      scope = scope.where(exited_at: ..params[:until].presence&.to_time) if params[:until].present?
      scope
    end
  end
end
