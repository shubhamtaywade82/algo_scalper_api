# frozen_string_literal: true

module Api
  class LogsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      log_file = Rails.root.join("log", "#{Rails.env}.log")
      logs = []

      if File.exist?(log_file)
        begin
          # Read last 100 lines safely (up to 50KB from the end to avoid loading huge files)
          file_size = File.size(log_file)
          read_bytes = [file_size, 50_000].min

          lines = File.open(log_file, "r") do |f|
            f.seek(file_size - read_bytes)
            f.read.force_encoding("UTF-8").split("\n")
          end

          # Take the last 100 complete lines
          lines = lines.last(100)

          logs = lines.filter_map do |line|
            # Strip ANSI color codes
            clean_line = line.gsub(/\e\[[0-9;]*[mK]/, "").strip
            next if clean_line.blank?

            # Basic parsing of Rails logs
            level = "info"
            level = "error" if clean_line.downcase.include?("error") || clean_line.include?("FATAL")
            level = "warn" if clean_line.downcase.include?("warn")

            source = "Rails"
            if clean_line.start_with?("[") && clean_line.include?("]")
              idx = clean_line.index("]")
              source = clean_line[1...idx]
              clean_line = clean_line[(idx + 1)..].strip
            end

            timestamp = Time.current.strftime("%H:%M:%S")
            # If line has standard timestamp like "I, [2026-07-06T11:41:16.123456 #1234]  INFO -- :"
            if clean_line.match?(/\A[IWEFD],\s+\[\d{4}-\d{2}-\d{2}T/)
              parts = clean_line.split(" -- : ")
              if parts.size > 1
                msg = parts[1..].join(" -- : ")
                meta = parts[0]
                time_str = meta.match(/\[(.*?)\]/)&.captures&.first
                timestamp = begin
                              DateTime.parse(time_str).strftime("%H:%M:%S")
                rescue StandardError
                              timestamp
                end
                level_char = meta[0]
                level = case level_char
                        when "W" then "warn"
                        when "E" then "error"
                        when "F" then "error"
                        else "info"
                        end
                clean_line = msg
              end
            end

            {
              timestamp: timestamp,
              level: level,
              source: source,
              message: clean_line
            }
          end
        rescue StandardError => e
          logs = [{ timestamp: Time.current.strftime("%H:%M:%S"), level: "error", source: "System", message: "Failed to read logs: #{e.message}" }]
        end
      else
        logs = [{ timestamp: Time.current.strftime("%H:%M:%S"), level: "warn", source: "System", message: "Log file not found at #{log_file}" }]
      end

      render json: { success: true, logs: logs }
    end
  end
end
