# frozen_string_literal: true

# Clear market holiday cache on boot so holiday data is always fresh
Rails.application.config.after_initialize do
  if defined?(Market::Calendar)
    Market::Calendar.clear_holiday_cache!
    Rails.logger.info("[Market::Calendar] Holiday cache cleared on boot")
  end
end
