# frozen_string_literal: true

# Dedicated logger for AI intent-extraction prompts (IntentResolver).
# Writes to log/ai_intent.log so main development.log is not cluttered.
# log/ is already ignored via .gitignore (/log/*).
Rails.application.config.after_initialize do
  path = Rails.root.join('log/ai_intent.log')
  formatter = proc do |severity, time, _progname, msg|
    "[ai_intent] #{severity[0]}, [#{time.strftime('%Y-%m-%dT%H:%M:%S.%6N')} ##{Process.pid}]  #{severity} -- : #{msg}\n"
  end

  ai_intent_logger = ActiveSupport::Logger.new(path)
  ai_intent_logger.formatter = formatter
  ai_intent_logger.level = Logger::DEBUG

  Rails.application.config.ai_intent_logger = ai_intent_logger
end
