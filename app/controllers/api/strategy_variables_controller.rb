# frozen_string_literal: true

module Api
  # Strategy-scoped platform variables (secrets masked on read).
  class StrategyVariablesController < ApplicationController
    include Api::TokenAuthenticatable
    include Api::StrategyScoped
    include Api::VariableSerialization

    before_action :authenticate_dashboard_token!
    before_action :find_strategy

    # GET /api/strategies/:strategy_slug/variables
    def show
      vars = ::PlatformVariable.for_strategy(@strategy.id)
      render json: { success: true, variables: vars.map { |v| serialize_variable(v) } }
    end

    # PUT /api/strategies/:strategy_slug/variables
    def update
      updates = params.permit(variables: %i[key value value_type secret])[:variables]
      return render json: { success: false, error: "Missing variables" }, status: :unprocessable_content unless updates

      upserted = updates.map { |var| upsert_variable(var, @strategy.id) }

      render json: { success: true, variables: upserted.map { |v| serialize_variable(v) } }
    end

    private

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
