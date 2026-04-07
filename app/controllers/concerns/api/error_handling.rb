# frozen_string_literal: true

module Api
  # Shared error-handling concern for all API controllers.
  #
  # Provides:
  #   - A centralised `rescue_from` hook for unhandled StandardError so individual
  #     controllers don't need to repeat the same rescue/log/render boilerplate.
  #   - Convenience helpers `render_success` and `render_error` for a consistent
  #     JSON response envelope across all endpoints.
  #
  # Usage in controllers:
  #   include Api::ErrorHandling
  #
  # Individual actions can still rescue specific exceptions themselves if they need
  # different behaviour (e.g. returning 404 vs 422).  The global hook only fires
  # when no closer rescue handles the exception.
  module ErrorHandling
    extend ActiveSupport::Concern

    included do
      rescue_from StandardError, with: :handle_unhandled_error
    end

    # ─── Response helpers ────────────────────────────────────────────────────

    # Renders a standard success envelope.
    #
    # @param data [Hash] Payload to nest under the response root.
    # @param status [Symbol, Integer] HTTP status (default :ok).
    def render_success(data = {}, status: :ok)
      render json: { success: true, **data }, status: status
    end

    # Renders a standard error envelope.
    #
    # @param message [String] Human-readable error description.
    # @param status [Symbol, Integer] HTTP status (default :internal_server_error).
    def render_error(message, status: :internal_server_error)
      render json: { success: false, error: message }, status: status
    end

    private

    # Global fallback — logs the full backtrace and returns a safe 500 response.
    # Individual rescue blocks in actions take priority over this handler.
    def handle_unhandled_error(error)
      Rails.logger.error(
        "[#{self.class.name}##{action_name}] Unhandled #{error.class}: #{error.message}\n" \
        "#{error.backtrace&.first(10)&.join("\n")}"
      )
      render_error("internal_error", status: :internal_server_error)
    end
  end
end
