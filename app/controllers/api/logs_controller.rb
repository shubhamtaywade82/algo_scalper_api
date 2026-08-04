# frozen_string_literal: true

module Api
  class LogsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    MAX_READ_BYTES = 50_000
    MAX_LINES = 2000
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    def index
      log_file = Rails.root.join("log", "#{Rails.env}.log")
      all_logs = []

      if File.exist?(log_file)
        begin
          file_size = File.size(log_file)
          read_bytes = [file_size, MAX_READ_BYTES].min

          raw = File.open(log_file, "r") do |f|
            f.seek(file_size - read_bytes)
            f.read.force_encoding("UTF-8")
          end

          all_logs = parse_log_lines(raw)
        rescue StandardError => e
          all_logs = [{ id: 1, timestamp: Time.current.strftime("%H:%M:%S"), level: "error", source: "System", message: "Failed to read logs: #{e.message}" }]
        end
      else
        all_logs = [{ id: 1, timestamp: Time.current.strftime("%H:%M:%S"), level: "warn", source: "System", message: "Log file not found at #{log_file}" }]
      end

      # Apply filters
      all_logs = filter_by_level(all_logs, params[:level])
      all_logs = filter_by_source(all_logs, params[:source])

      total = all_logs.size
      page = [params[:page].to_i, 1].max
      per_page = [[params[:per_page].to_i, 1].max, MAX_PER_PAGE].min
      total_pages = [1, (total.to_f / per_page).ceil].max
      page = [page, total_pages].min

      offset = (page - 1) * per_page
      paginated = all_logs.slice(offset, per_page) || []

      render json: {
        logs: paginated,
        meta: {
          total: total,
          page: page,
          per_page: per_page,
          pages: total_pages
        }
      }
    end

    private

    def parse_log_lines(raw)
      lines = raw.split("\n").last(MAX_LINES)
      id = 0

      lines.filter_map do |line|
        clean_line = line.gsub(/\e\[[0-9;]*[mK]/, "").strip
        next if clean_line.blank?

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

        id += 1
        {
          id: id,
          timestamp: timestamp,
          level: level,
          source: source,
          message: clean_line
        }
      end
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
