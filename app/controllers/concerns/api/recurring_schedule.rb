# frozen_string_literal: true

module Api
  # Reads config/recurring.yml for the current env (the Solid Queue recurring schedule).
  module RecurringSchedule
    extend ActiveSupport::Concern

    private

    def load_schedule_config
      path = Rails.root.join("config/recurring.yml")
      return {} unless File.exist?(path)

      begin
        all_config = YAML.load_file(path)
        all_config[Rails.env] || {}
      rescue StandardError => e
        Rails.logger.error("[Api::RecurringSchedule] Failed to load recurring.yml: #{e.message}")
        {}
      end
    end
  end
end
