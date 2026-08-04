#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Orders Services Test')

# Setup prerequisites
ServiceTestHelper.print_section('0. Prerequisites Setup')
ServiceTestHelper.setup_test_watchlist_items
ServiceTestHelper.setup_test_position_tracker(paper: true)

# Test 1: OrderRouter
ServiceTestHelper.print_section('1. OrderRouter')
TradingSystem::OrderRouter.new
ServiceTestHelper.print_success('OrderRouter initialized')

# Test 2: Orders::Placer
ServiceTestHelper.print_section('2. Orders::Placer')
Orders::Placer.new
ServiceTestHelper.print_success('Orders::Placer initialized')

# Test 3: Orders::Gateway
ServiceTestHelper.print_section('3. Orders::Gateway')
paper_mode = AlgoConfig.fetch.dig(:paper_trading, :enabled) == true

if paper_mode
  Orders::GatewayPaper.new
  ServiceTestHelper.print_info('Using Paper Gateway')
else
  Orders::GatewayLive.new
  ServiceTestHelper.print_info('Using Live Gateway')
end

ServiceTestHelper.print_success('Orders::Gateway initialized')

# Test 4: Orders::EntryManager
ServiceTestHelper.print_section('4. Orders::EntryManager')
entry_manager = Orders::EntryManager.new
ServiceTestHelper.print_success('EntryManager initialized')

# Test 5: Orders::BracketPlacer
ServiceTestHelper.print_section('5. Orders::BracketPlacer')
bracket_placer = Orders::BracketPlacer.new
ServiceTestHelper.print_success('BracketPlacer initialized')

# Test 6: Test order placement (create PositionTracker in DB instead of real order)
ServiceTestHelper.print_section('6. Order Placement Test (Create PositionTracker in DB)')
ServiceTestHelper.print_info('Creating PositionTracker record in DB (no real order placed)')

watchlist_item = WatchlistItem.where(active: true).includes(:watchable).first
if watchlist_item
  watchable = watchlist_item.watchable

  if watchable
    symbol = watchable.respond_to?(:symbol_name) ? watchable.symbol_name : watchlist_item.label
    seg = watchable.respond_to?(:exchange_segment) ? watchable.exchange_segment : watchlist_item.segment
    sid = watchable.respond_to?(:security_id) ? watchable.security_id : watchlist_item.security_id

    ServiceTestHelper.print_info("Test watchlist item: #{symbol}")

    # Create PositionTracker in DB (simulating order placement)
    tracker = ServiceTestHelper.create_position_tracker(
      watchable: watchable,
      segment: seg,
      security_id: sid.to_s,
      side: 'long',
      quantity: 75,
      paper: true
    )

    if tracker
      ServiceTestHelper.print_success("Created PositionTracker (ID: #{tracker.id}) in DB")
      ServiceTestHelper.print_info("  Symbol: #{symbol}")
      ServiceTestHelper.print_info("  Entry Price: ₹#{tracker.entry_price}")
      ServiceTestHelper.print_info("  Quantity: #{tracker.quantity}")
    else
      ServiceTestHelper.print_warning('Failed to create PositionTracker')
    end
  else
    ServiceTestHelper.print_warning('Watchlist item has no watchable (instrument/derivative)')
  end
else
  ServiceTestHelper.print_warning('No active watchlist items for testing')
end

# Test 7: Test bracket placement (dry run)
ServiceTestHelper.print_section('7. Bracket Placement Test (Dry Run)')
active_tracker = PositionTracker.active.first

if active_tracker
  ServiceTestHelper.print_info("Test tracker: #{active_tracker.id}")

  # Calculate SL/TP
  if active_tracker.entry_price.present?
    entry = active_tracker.entry_price.to_f
    sl_price = entry * 0.70  # 30% below
    tp_price = entry * 1.60  # 60% above

    ServiceTestHelper.print_info("  Entry: ₹#{entry}")
    ServiceTestHelper.print_info("  SL: ₹#{sl_price}")
    ServiceTestHelper.print_info("  TP: ₹#{tp_price}")

    # BracketPlacer.place_bracket would be called here
    ServiceTestHelper.print_info('BracketPlacer.place_bracket would:')
    ServiceTestHelper.print_info('  - Update ActiveCache with SL/TP')
    ServiceTestHelper.print_info('  - Emit bracket_placed event')
  end
else
  ServiceTestHelper.print_warning('No active positions for bracket testing')
end

# Test 8: Order statistics
ServiceTestHelper.print_section('8. Order Statistics')
entry_stats = entry_manager.instance_variable_get(:@stats)
ServiceTestHelper.print_info("EntryManager stats:\n#{ServiceTestHelper.format_hash(entry_stats)}") if entry_stats

bracket_stats = bracket_placer.instance_variable_get(:@stats)
ServiceTestHelper.print_info("BracketPlacer stats:\n#{ServiceTestHelper.format_hash(bracket_stats)}") if bracket_stats

ServiceTestHelper.print_success('Orders services test completed')
ServiceTestHelper.print_warning('Note: Actual order placement requires proper signal results and market conditions')
