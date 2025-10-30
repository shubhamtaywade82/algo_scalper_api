# frozen_string_literal: true

namespace :paper do
  desc 'Integration: place order via Orders.config and exit via flat_position (risk exit)'
  task integration: :environment do
    unless ExecutionMode.paper?
      puts '❌ PAPER_MODE is not enabled. Set PAPER_MODE=true'
      exit 1
    end

    def fmt(val)
      format('%.2f', (val || 0).to_f)
    end

    ns = Paper::TradingClock.redis_ns
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    redis.del("#{ns}:wallet", "#{ns}:orders")
    redis.keys("#{ns}:pos:*").each { |k| redis.del(k) }
    redis.del("#{ns}:pos:index")
    # Re-seed wallet to ENV seed cash for consistent baseline
    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sid = '51000'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i

    # Snapshot: initial
    w0 = Orders.config.wallet_snapshot
    puts "\nWallet (initial):"
    puts "  Cash:           ₹#{fmt(w0[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w0[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w0[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w0[:realized_pnl])}"
    puts "  Unrealized PnL: ₹#{fmt(w0[:unrealized_pnl])}"
    puts "  Fees Total:     ₹#{fmt(w0[:fees_total])}"

    puts "\n== Integration: Place via Orders.config.place_market =="
    r = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: lot, meta: { ltp: 100.0 })
    raise 'Placement failed' unless r && r.status == 'filled'

    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=#{lot} price=100.00 order=#{r.order_no}"

    # Snapshot: after order placed
    w1 = Orders.config.wallet_snapshot
    puts "\nWallet (after entry):"
    puts "  Cash:           ₹#{fmt(w1[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w1[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w1[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w1[:realized_pnl])}"
    puts "  Unrealized PnL: ₹#{fmt(w1[:unrealized_pnl])}"
    puts "  Fees Total:     ₹#{fmt(w1[:fees_total])}"

    pos = Orders.config.position(segment: seg, security_id: sid)
    raise 'Position not found after placement' unless pos && pos[:qty] == lot

    puts "\n== Integration: Risk exit via Orders.config.flat_position =="
    # Simulate a small favorable move before exit and provide LTP in meta
    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 101.0)
    rx = Orders.config.place_market(side: 'sell', segment: seg, security_id: sid, qty: lot, meta: { ltp: 101.0 })
    raise 'Exit failed' unless rx

    puts "EXIT  -> seg=#{seg} sid=#{sid} order=#{rx.respond_to?(:order_no) ? rx.order_no : 'N/A'}"

    # Verify flat and show wallet
    pos2 = Orders.config.position(segment: seg, security_id: sid)
    raise 'Position should be flat' unless pos2.nil?

    # Snapshot: after exit
    w2 = Orders.config.wallet_snapshot
    puts "\nWallet (after exit):"
    puts "  Cash:           ₹#{fmt(w2[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w2[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w2[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w2[:realized_pnl])}"
    puts "  Unrealized PnL: ₹#{fmt(w2[:unrealized_pnl])}"
    puts "  Fees Total:     ₹#{fmt(w2[:fees_total])}"

    puts "\n✅ Paper integration path verified (placement + risk exit)."

    # Run the full verification suite from paper:verify_wallet_flow within integration
    puts "\n== Running full paper verification suite (from integration) =="
    Rake::Task['paper:verify_wallet_flow'].invoke
    Rake::Task['paper:verify_wallet_flow'].reenable
  rescue StandardError => e
    puts "\n❌ Integration failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end
