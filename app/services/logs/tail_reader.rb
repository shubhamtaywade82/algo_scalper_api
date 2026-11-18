# frozen_string_literal: true

module Logs
  # Reads the tail of a log file and turns it into structured entries for the dashboard.
  class TailReader
    MAX_READ_BYTES = 50_000
    MAX_LINES = 2000

    # ActiveRecord query/trace lines, ActionCable heartbeat broadcasts and hex payload
    # dumps are ~90% of the dev log and bury the app events the page exists to show.
    LOG_NOISE = Regexp.union(
      /\A(↳ |CACHE |TRANSACTION \(|SQL \()/,
      /\A[\w:]+ (Load|Create|Update|Destroy|Exists\?|Count|Sum|Pluck|Insert|Upsert|Bulk Insert|Insert All|Delete All|Update All)\b.*\(\d+\.\d+ms\)/,
      /\A\[ActionCable\] Broadcasting to strategy_status/,
      /\A\h{40,}/
    )
    ANSI_CODES = /\e\[[0-9;]*[mK]/
    LOGGER_LINE = /\A[IWEFD],\s+\[\d{4}-\d{2}-\d{2}T/
    LOGGER_SEPARATOR = ' -- : '
    LOGGER_LEVELS = { 'W' => 'warn', 'E' => 'error', 'F' => 'error' }.freeze

    def initialize(path)
      @path = path
    end

    # @return [Array<Hash>] { id:, timestamp:, level:, source:, message: }, oldest first
    def call
      return [system_entry('warn', "Log file not found at #{@path}")] unless File.exist?(@path)

      parse(read_tail)
    rescue StandardError => e
      [system_entry('error', "Failed to read logs: #{e.message}")]
    end

    private

    def read_tail
      size = File.size(@path)
      File.open(@path, 'r') do |file|
        file.seek(size - [size, MAX_READ_BYTES].min)
        file.read.force_encoding('UTF-8')
      end
    end

    def parse(raw)
      entries = raw.split("\n").last(MAX_LINES).filter_map { |line| parse_line(line) }
      entries.each_with_index.map { |entry, index| { id: index + 1 }.merge(entry) }
    end

    def parse_line(line)
      text = line.gsub(ANSI_CODES, '').strip
      return if text.blank? || text.match?(LOG_NOISE)

      level = level_from(text)
      source, text = split_source(text)
      timestamp, level, text = apply_logger_format(text, now_label, level)

      { timestamp: timestamp, level: level, source: source, message: text }
    end

    def level_from(text)
      lowered = text.downcase
      return 'warn' if lowered.include?('warn')
      return 'error' if lowered.include?('error') || text.include?('FATAL')

      'info'
    end

    # "[Source] message" -> ["Source", "message"]
    def split_source(text)
      return ['Rails', text] unless text.start_with?('[') && text.include?(']')

      closing = text.index(']')
      [text[1...closing], text[(closing + 1)..].strip]
    end

    # Ruby Logger lines ("E, [time #pid] ERROR -- : message") carry their own time and level.
    def apply_logger_format(text, timestamp, level)
      return [timestamp, level, text] unless text.match?(LOGGER_LINE)

      meta, *message = text.split(LOGGER_SEPARATOR)
      return [timestamp, level, text] if message.empty?

      [logger_time(meta) || timestamp, LOGGER_LEVELS.fetch(meta[0], 'info'), message.join(LOGGER_SEPARATOR)]
    end

    def logger_time(meta)
      DateTime.parse(meta.match(/\[(.*?)\]/)&.captures&.first).strftime('%H:%M:%S')
    rescue StandardError
      nil
    end

    def now_label
      Time.current.strftime('%H:%M:%S')
    end

    def system_entry(level, message)
      { id: 1, timestamp: now_label, level: level, source: 'System', message: message }
    end
  end
end
