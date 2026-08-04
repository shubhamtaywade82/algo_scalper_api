# frozen_string_literal: true

module Analysis
  class Snapshot
    class SubSnapshot
      attr_reader :timestamp, :sequence, :age_ms, :quality, :source, :data

      def initialize(timestamp:, sequence:, age_ms:, quality:, source:, data:)
        @timestamp = timestamp
        @sequence = sequence
        @age_ms = age_ms
        @quality = quality
        @source = source
        @data = (data || {}).freeze
        freeze
      end
    end

    attr_reader :id, :timestamp, :sequence, :sub_snapshots

    def initialize(id:, timestamp:, sequence:, sub_snapshots:)
      @id = id
      @timestamp = timestamp
      @sequence = sequence
      @sub_snapshots = (sub_snapshots || {}).freeze
      freeze
    end

    # Returns a map of sub-snapshot names (Symbol) to their sequences
    def sequences
      sub_snapshots.transform_values(&:sequence)
    end
  end
end
