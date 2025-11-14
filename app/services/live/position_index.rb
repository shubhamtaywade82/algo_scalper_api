# frozen_string_literal: true
require 'singleton'
require 'concurrent/map'
require 'concurrent/array'
require 'monitor'

module Live
  # In-memory index: security_id(string) => Concurrent::Array of tracker metadata
  # Metadata is a Hash with minimal fields used by PnL (id, entry_price, quantity)
  class PositionIndex
    include Singleton

    def initialize
      @index = Concurrent::Map.new # security_id => Concurrent::Array of metadata
      @lock = Monitor.new
    end

    # metadata: { id:, entry_price:, quantity:, segment: }
    def add(metadata)
      sid = metadata[:security_id].to_s
      arr = (@index[sid] ||= Concurrent::Array.new)
      # de-dup by id (rare) and push metadata
      arr.reject! { |m| m[:id] == metadata[:id] }
      arr << metadata
      true
    end

    def remove(tracker_id, security_id)
      sid = security_id.to_s
      return unless @index.key?(sid)

      arr = @index[sid]
      arr.delete_if { |m| m[:id] == tracker_id.to_i }
      @index.delete(sid) if arr.empty?
      true
    end

    def update(metadata)
      # safe replace by id
      remove(metadata[:id], metadata[:security_id])
      add(metadata)
    end

    def trackers_for(security_id)
      arr = @index[security_id.to_s]
      return [] unless arr
      # Return a snapshot (dup) to avoid mutation issues
      arr.dup
    end

    def clear
      @index.clear
    end

    # For boot: populate from DB once
    def bulk_load_active!
      @lock.synchronize do
        @index.clear
        PositionTracker.active.select(:id, :security_id, :entry_price, :quantity, :segment).find_each do |t|
          add(
            id: t.id,
            security_id: t.security_id,
            entry_price: t.entry_price.to_s,
            quantity: t.quantity.to_i,
            segment: t.segment
          )
        end
      end
    end
  end
end
