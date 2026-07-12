# frozen_string_literal: true

module Api
  module Research
    # Shared offset/limit pagination for the two Research index actions
    # (signals, lifecycles) — mirrors Api::SignalsController's pagination
    # style without duplicating it twice inside this module.
    module Paginatable
      extend ActiveSupport::Concern

      PER_PAGE_DEFAULT = 25
      PER_PAGE_MAX = 100

      private

      def paginate(scope)
        total = scope.count
        page = [params[:page].to_i, 1].max
        per_page = per_page_value
        records = scope.offset((page - 1) * per_page).limit(per_page)

        [records, { total: total, page: page, per_page: per_page, pages: (total.to_f / per_page).ceil }]
      end

      def per_page_value
        raw = params[:per_page].to_i
        raw = PER_PAGE_DEFAULT if raw <= 0
        [raw, PER_PAGE_MAX].min
      end
    end
  end
end
