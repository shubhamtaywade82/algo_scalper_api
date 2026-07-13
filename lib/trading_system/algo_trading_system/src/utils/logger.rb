# frozen_string_literal: true

require 'logger'
require 'json'
require 'time'

module Utils
  # Structured JSON logger
  class Logger
    class << self
      def instance
        @instance ||= build_logger
      end

      def configure(logger)
        @instance = logger
      end

      def info(message, payload = {})
        instance.info(format_log(message, payload))
      end

      def warn(message, payload = {})
        instance.warn(format_log(message, payload))
      end

      def error(message, payload = {})
        instance.error(format_log(message, payload))
      end

      def debug(message, payload = {})
        instance.debug(format_log(message, payload))
      end

      private

      def build_logger(output = $stdout)
        logger = ::Logger.new(output)
        logger.formatter = proc do |severity, datetime, _progname, msg|
          log_data = { timestamp: datetime.utc.iso8601, level: severity }
          log_data.merge!(msg) if msg.is_a?(Hash)
          "#{log_data.to_json}\n"
        end
        logger
      end

      def format_log(message, payload)
        { message: message }.merge(payload)
      end
    end
  end
end
