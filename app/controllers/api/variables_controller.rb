# frozen_string_literal: true

module Api
  # CRUD for global platform variables.
  #
  # Secrets are masked in reads; full values accessible only at runtime.
  class VariablesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    # GET /api/variables
    def index
      vars = ::PlatformVariable.global.order(:key)
      render json: {
        success: true,
        variables: vars.map { |v| serialize_variable(v) }
      }
    end

    # PUT /api/variables
    def update
      updates = params.permit(variables: %i[key value value_type secret])[:variables]
      return render json: { success: false, error: "Missing variables" }, status: :unprocessable_content unless updates

      upserted = updates.map { |attrs| upsert_variable(attrs) }

      render json: {
        success: true,
        variables: upserted.map { |v| serialize_variable(v) }
      }
    end

    private

    def serialize_variable(v)
      {
        id: v.id,
        key: v.key,
        value: v.secret ? "•••" : v.value,
        value_type: v.value_type,
        secret: v.secret
      }
    end

    def upsert_variable(attrs)
      variable = ::PlatformVariable.find_or_initialize_by(
        scope: "global",
        strategy_id: nil,
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
