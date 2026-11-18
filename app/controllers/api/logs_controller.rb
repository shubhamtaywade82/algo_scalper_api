# frozen_string_literal: true

module Api
  class LogsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    def index
      logs = Logs::TailReader.new(Rails.root.join('log', "#{Rails.env}.log")).call
      logs = filter_by_source(filter_by_level(logs, params[:level]), params[:source])

      render json: paginate(logs)
    end

    private

    def paginate(logs)
      per_page = params[:per_page].to_i.positive? ? [params[:per_page].to_i, MAX_PER_PAGE].min : DEFAULT_PER_PAGE
      total_pages = [1, (logs.size.to_f / per_page).ceil].max
      page = [[params[:page].to_i, 1].max, total_pages].min

      {
        logs: logs.slice((page - 1) * per_page, per_page) || [],
        meta: { total: logs.size, page: page, per_page: per_page, pages: total_pages }
      }
    end

    def filter_by_level(logs, level)
      return logs if level.blank?

      logs.select { |l| l[:level] == level.downcase }
    end

    def filter_by_source(logs, source)
      return logs if source.blank?

      logs.select { |l| l[:source]&.downcase&.include?(source.downcase) }
    end
  end
end
