# frozen_string_literal: true

namespace :position do
  desc 'Sync positions between DhanHQ and PositionTracker database'
  task sync: :environment do
    puts 'Starting position synchronization...'

    begin
      Live::PositionSyncService.instance.force_sync!
      puts 'Position synchronization completed successfully!'
    rescue StandardError => e
      puts "Position synchronization failed: #{e.class} - #{e.message}"
      exit 1
    end
  end

  desc 'Show position sync status'
  task status: :environment do
    puts 'Position Sync Status:'
    puts '===================='

    begin
      # Count DhanHQ positions
      dhan_positions = DhanHQ::Models::Position.active
      puts "DhanHQ Active Positions: #{dhan_positions.size}"

      # Count tracked positions
      tracked_positions = PositionTracker.active
      puts "Tracked Positions: #{tracked_positions.size}"

      # Show untracked positions
      tracked_security_ids = tracked_positions.pluck(:security_id).map(&:to_s)
      untracked = dhan_positions.reject do |pos|
        security_id = pos.security_id
        tracked_security_ids.include?(security_id.to_s)
      end

      puts "Untracked Positions: #{untracked.size}"

      if untracked.any?
        puts "\nUntracked Position Details:"
        untracked.each do |pos|
          security_id = pos.security_id
          symbol = pos.trading_symbol
          puts "  - #{security_id}: #{symbol}"
        end
      end
    rescue StandardError => e
      puts "Failed to get position status: #{e.class} - #{e.message}"
      exit 1
    end
  end
end
