# frozen_string_literal: true

namespace :paper do
  desc 'Verify wallet lifecycle: seed -> buy -> tick -> sell'
  task verify_wallet_flow: :environment do
    unless ExecutionMode.paper?
      puts '❌ PAPER_MODE is not enabled. Set PAPER_MODE=true'
      exit 1
    end

    ns = Paper::TradingClock.redis_ns
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))

    # Reset today state
    redis.del("#{ns}:wallet", "#{ns}:orders")
    redis.keys("#{ns}:pos:*").each { |k| redis.del(k) }
    redis.del("#{ns}:pos:index")

    # Use GatewayV2 for the test
    Orders.config = Paper::GatewayV2.new

    seed_cash = BigDecimal(ENV.fetch('PAPER_SEED_CASH', '100000'))

    def fmt(val)
      format('%.2f', (val || 0).to_f)
    end

    puts "\n== Seed wallet =="
    w0 = Orders.config.wallet_snapshot
    puts "  Cash:           ₹#{fmt(w0[:cash])}"
    puts "  Equity:         ₹#{fmt(w0[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w0[:realized_pnl])}"
    puts "  Unrealized PnL: ₹#{fmt(w0[:unrealized_pnl])}"
    puts "  Fees Total:     ₹#{fmt(w0[:fees_total])}"
    raise 'Seed cash mismatch' unless w0[:cash].to_f.round(2) == seed_cash.to_f.round(2)
    raise 'Equity mismatch at seed' unless (w0[:equity] - w0[:cash]).abs < 0.0001

    seg = 'NSE_FNO'
    sid = '50058'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i
    qty = lot
    buy_ltp = BigDecimal(100)

    puts "\n== Place BUY =="
    r1 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: qty, meta: { ltp: buy_ltp.to_f })

    raise 'Buy failed' unless r1 && r1.status == 'filled'

    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=#{qty} price=#{fmt(buy_ltp)} resp_order_no=#{r1.order_no}"

    w1 = Orders.config.wallet_snapshot
    expected_cash_after_buy = seed_cash - (buy_ltp * qty) - BigDecimal(20)
    puts 'Wallet after buy:'
    puts "  Cash:           ₹#{fmt(w1[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w1[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w1[:equity])}"
    puts "  Fees Total:     ₹#{fmt(w1[:fees_total])}"
    raise 'Cash after buy mismatch' unless (w1[:cash].to_f.round(2) - expected_cash_after_buy.to_f.round(2)).abs < 0.01

    expected_used = (buy_ltp * qty) + 20
    raise 'Used amount after buy mismatch' unless (w1[:used_amount].to_f.round(2) - expected_used.to_f.round(2)).abs < 0.01
    raise 'Fees after buy mismatch' unless (w1[:fees_total].to_f.round(2) - 20.0).abs < 0.01

    p1 = Orders.config.position(segment: seg, security_id: sid)
    raise 'Position missing after buy' unless p1 && p1[:qty] == qty && (p1[:avg_price].to_f.round(2) - 100.0).abs < 0.01

    puts "\n== Tick +3 =="
    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 103.0)
    w2 = Orders.config.wallet_snapshot
    expected_upnl = (3 * qty)
    raise 'Unrealized PnL mismatch' unless (w2[:unrealized_pnl].to_f.round(2) - expected_upnl.to_f.round(2)).abs < 0.01

    puts "\n== Place SELL =="
    sell_ltp = BigDecimal(103)
    r2 = Orders.config.place_market(side: 'sell', segment: seg, security_id: sid, qty: qty,
                                    meta: { ltp: sell_ltp.to_f })
    raise 'Sell failed' unless r2 && r2.status == 'filled'

    puts "EXIT  -> seg=#{seg} sid=#{sid} qty=#{qty} price=#{fmt(sell_ltp)} resp_order_no=#{r2.order_no}"

    w3 = Orders.config.wallet_snapshot
    expected_cash_after_sell = expected_cash_after_buy + (sell_ltp * qty) - BigDecimal(20)
    puts 'Wallet after sell:'
    puts "  Cash:           ₹#{fmt(w3[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w3[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w3[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w3[:realized_pnl])}"
    puts "  Unrealized PnL: ₹#{fmt(w3[:unrealized_pnl])}"
    puts "  Fees Total:     ₹#{fmt(w3[:fees_total])}"
    raise 'Cash after sell mismatch' unless (w3[:cash].to_f.round(2) - expected_cash_after_sell.to_f.round(2)).abs < 0.01
    raise 'Fees total mismatch after sell' unless (w3[:fees_total].to_f.round(2) - 40.0).abs < 0.01
    raise 'Used amount after flat mismatch' unless (w3[:used_amount].to_f.round(2) - 40.0).abs < 0.01

    p2 = Orders.config.position(segment: seg, security_id: sid)
    raise 'Position should be flat after sell' unless p2.nil?

    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (wallet_flow):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    #{"₹#{fmt(w_end[:used_amount])}"}"
    puts "  Equity:         ₹#{fmt(w_end[:equity])}"
    puts "  Realized PnL:   #{"₹#{fmt(w_end[:realized_pnl])}"}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"

    # --- Aggregate additional scenarios in a single run ---
    results = []

    begin
      Rake::Task['paper:verify_scale_in_single_exit'].invoke
      results << { name: 'scale_in_single_exit', ok: true }
    rescue StandardError => e
      results << { name: 'scale_in_single_exit', ok: false, err: e.message }
    ensure
      Rake::Task['paper:verify_scale_in_single_exit'].reenable
    end

    begin
      Rake::Task['paper:verify_parallel_positions'].invoke
      results << { name: 'parallel_positions', ok: true }
    rescue StandardError => e
      results << { name: 'parallel_positions', ok: false, err: e.message }
    ensure
      Rake::Task['paper:verify_parallel_positions'].reenable
    end

    begin
      Rake::Task['paper:verify_sequential_positions'].invoke
      results << { name: 'sequential_positions', ok: true }
    rescue StandardError => e
      results << { name: 'sequential_positions', ok: false, err: e.message }
    ensure
      Rake::Task['paper:verify_sequential_positions'].reenable
    end

    begin
      Rake::Task['paper:verify_pnl_states'].invoke
      results << { name: 'pnl_states', ok: true }
    rescue StandardError => e
      results << { name: 'pnl_states', ok: false, err: e.message }
    ensure
      Rake::Task['paper:verify_pnl_states'].reenable
    end

    begin
      Rake::Task['paper:verify_reconciliation'].invoke
      results << { name: 'reconciliation', ok: true }
    rescue StandardError => e
      results << { name: 'reconciliation', ok: false, err: e.message }
    ensure
      Rake::Task['paper:verify_reconciliation'].reenable
    end

    # Final summary
    puts "\n=== SUMMARY ==="
    results.each do |r|
      status = r[:ok] ? 'PASS' : "FAIL (#{r[:err]})"
      puts "  - #{r[:name]}: #{status}"
    end
    all_ok = results.all? { |r| r[:ok] }
    puts all_ok ? "\n✅ All scenarios passed." : "\n❌ Some scenarios failed."
  rescue StandardError => e
    puts "\n❌ Verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end

namespace :paper do
  desc 'Verify scale-in (buy lot, buy another lot) and single exit of both lots'
  task verify_scale_in_single_exit: :environment do
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

    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sid = '50400'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i

    puts "\n== Scale-in: BUY 1 lot @100, then BUY 1 lot @110 =="
    r1 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: lot, meta: { ltp: 100.0 })
    r2 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: lot, meta: { ltp: 110.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=#{lot} price=100.00 order=#{r1&.order_no}"
    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=#{lot} price=110.00 order=#{r2&.order_no}"

    pos = Orders.config.position(segment: seg, security_id: sid)
    expected_qty = lot * 2
    expected_avg = 105.0
    raise 'Scale-in qty mismatch' unless pos && pos[:qty] == expected_qty
    raise 'Avg price mismatch' unless (pos[:avg_price].to_f.round(2) - expected_avg).abs < 0.01

    # Exit both lots in a single sell
    puts "\n== Single EXIT of both lots @108 =="
    sell_px = 108.0
    r3 = Orders.config.place_market(side: 'sell', segment: seg, security_id: sid, qty: expected_qty, meta: { ltp: sell_px })
    puts "EXIT  -> seg=#{seg} sid=#{sid} qty=#{expected_qty} price=#{format('%.2f', sell_px)} order=#{r3&.order_no}"

    w = Orders.config.wallet_snapshot
    expected_realized = (sell_px - expected_avg) * expected_qty
    # 3 orders total (2 buys + 1 sell) => ₹60 fees
    expected_fees = 60.0
    puts "  Wallet: Cash=₹#{fmt(w[:cash])} Equity=₹#{fmt(w[:equity])} Realized=₹#{fmt(w[:realized_pnl])} Fees=₹#{fmt(w[:fees_total])}"
    raise 'Realized PnL mismatch' unless (w[:realized_pnl].to_f.round(2) - expected_realized.round(2)).abs < 0.01
    raise 'Fees mismatch' unless (w[:fees_total].to_f.round(2) - expected_fees).abs < 0.01
    raise 'Used amount after flat mismatch' unless (w[:used_amount].to_f.round(2) - expected_fees).abs < 0.01

    puts "\n✅ Scale-in single-exit verified."

    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (scale_in_single_exit):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    ₹#{fmt(w_end[:used_amount])}"
    puts "  Equity:         ₹#{fmt(w_end[:equity])}"
    puts "  Realized PnL:   ₹#{fmt(w_end[:realized_pnl])}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"
  rescue StandardError => e
    puts "\n❌ Scale-in verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
  desc 'Verify two positions opened in parallel and MTM updates'
  task verify_parallel_positions: :environment do
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

    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sid1 = '50058'
    sid2 = '50059'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i

    puts "\n== Open two BUY positions =="
    rpa = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid1, qty: lot, meta: { ltp: 100.0 })
    rpb = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid2, qty: lot, meta: { ltp: 200.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sid1} qty=#{lot} price=100.00 order=#{rpa&.order_no}"
    puts "ENTRY -> seg=#{seg} sid=#{sid2} qty=#{lot} price=200.00 order=#{rpb&.order_no}"
    w = Orders.config.wallet_snapshot
    puts "  Cash:        ₹#{fmt(w[:cash])}"
    puts "  Fees total:  ₹#{fmt(w[:fees_total])} (expect 40.00)"
    p1 = Orders.config.position(segment: seg, security_id: sid1)
    p2 = Orders.config.position(segment: seg, security_id: sid2)
    raise 'Missing pos1' unless p1 && p1[:qty] == lot
    raise 'Missing pos2' unless p2 && p2[:qty] == lot

    puts "\n== Tick updates (sid1 +5, sid2 -10) =="
    Orders.config.on_tick(segment: seg, security_id: sid1, ltp: 105.0)
    Orders.config.on_tick(segment: seg, security_id: sid2, ltp: 190.0)
    p1u = Orders.config.position(segment: seg, security_id: sid1)[:upnl].to_f
    p2u = Orders.config.position(segment: seg, security_id: sid2)[:upnl].to_f
    puts "  P1 UPNL: ₹#{fmt(p1u)} (expect #{fmt(5.0 * lot)})"
    puts "  P2 UPNL: ₹#{fmt(p2u)} (expect #{fmt(-10.0 * lot)})"
    raise 'P1 upnl mismatch' unless (p1u.round(2) - (5.0 * lot)).abs < 0.01
    raise 'P2 upnl mismatch' unless (p2u.round(2) - (-10.0 * lot)).abs < 0.01

    puts "\n== Close both =="
    rsa = Orders.config.place_market(side: 'sell', segment: seg, security_id: sid1, qty: lot, meta: { ltp: 105.0 })
    rsb = Orders.config.place_market(side: 'sell', segment: seg, security_id: sid2, qty: lot, meta: { ltp: 190.0 })
    puts "EXIT  -> seg=#{seg} sid=#{sid1} qty=#{lot} price=105.00 order=#{rsa&.order_no}"
    puts "EXIT  -> seg=#{seg} sid=#{sid2} qty=#{lot} price=190.00 order=#{rsb&.order_no}"
    w2 = Orders.config.wallet_snapshot
    puts "  Used Amount: ₹#{fmt(w2[:used_amount])} (expect cumulative fees)"
    puts "  Fees total:  ₹#{fmt(w2[:fees_total])} (expect 80.00)"
    raise 'Fees total mismatch' unless (w2[:fees_total].to_f.round(2) - 80.00).abs < 0.01

    puts "\n✅ Parallel positions verified."
    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (parallel_positions):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    #{"₹#{fmt(w_end[:used_amount])}"}"
    puts "  Equity:         ₹#{fmt(w_end[:equity])}"
    puts "  Realized PnL:   #{"₹#{fmt(w_end[:realized_pnl])}"}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"
  rescue StandardError => e
    puts "\n❌ Parallel verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end

  desc 'Verify sequential positions (profit then loss) and realized PnL netting'
  task verify_sequential_positions: :environment do
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

    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sidA = '50100'
    sidB = '50101'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i

    puts "\n== Trade A: +5 profit =="
    rA1 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sidA, qty: lot, meta: { ltp: 100.0 })
    rA2 = Orders.config.place_market(side: 'sell', segment: seg, security_id: sidA, qty: lot, meta: { ltp: 105.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sidA} qty=#{lot} price=100.00 order=#{rA1&.order_no}"
    puts "EXIT  -> seg=#{seg} sid=#{sidA} qty=#{lot} price=105.00 order=#{rA2&.order_no}"

    puts "\n== Trade B: -5 loss =="
    rB1 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sidB, qty: lot, meta: { ltp: 50.0 })
    rB2 = Orders.config.place_market(side: 'sell', segment: seg, security_id: sidB, qty: lot, meta: { ltp: 45.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sidB} qty=#{lot} price=50.00 order=#{rB1&.order_no}"
    puts "EXIT  -> seg=#{seg} sid=#{sidB} qty=#{lot} price=45.00 order=#{rB2&.order_no}"
    w = Orders.config.wallet_snapshot
    puts "  Wallet: Cash=₹#{fmt(w[:cash])} Equity=₹#{fmt(w[:equity])} Fees=₹#{fmt(w[:fees_total])} Realized=₹#{fmt(w[:realized_pnl])}"

    w = Orders.config.wallet_snapshot
    puts "  Realized PnL: ₹#{fmt(w[:realized_pnl])} (expect near 0.00 ignoring fees)"
    raise 'Realized mismatch' unless w[:realized_pnl].to_f.round(2).abs < (0.02 * lot) # near zero ignoring fees

    puts "  Fees total:  ₹#{fmt(w[:fees_total])} (expect 80.00)"
    raise 'Fees total mismatch' unless (w[:fees_total].to_f.round(2) - 80.00).abs < 0.01

    puts "\n✅ Sequential positions verified."
    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (sequential_positions):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    #{"₹#{fmt(w_end[:used_amount])}"}"
    puts "  Equity:         #{"₹#{fmt(w_end[:equity])}"}"
    puts "  Realized PnL:   #{"₹#{fmt(w_end[:realized_pnl])}"}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"
  rescue StandardError => e
    puts "\n❌ Sequential verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end

  desc 'Verify PnL states: profit, loss, breakeven on a single position'
  task verify_pnl_states: :environment do
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

    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sid = '50200'
    lot = (ENV['NIFTY_LOT_SIZE'] || '75').to_i

    qty = lot * 2
    rp = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: qty, meta: { ltp: 100.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=#{qty} price=100.00 order=#{rp&.order_no}"
    w = Orders.config.wallet_snapshot
    puts "  Wallet after entry: Cash=₹#{fmt(w[:cash])} Used=₹#{fmt(w[:used_amount])} Fees=₹#{fmt(w[:fees_total])}"
    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 110.0)
    up1 = Orders.config.position(segment: seg, security_id: sid)[:upnl].to_f
    puts "  Profit UPNL: ₹#{fmt(up1)} (expect #{fmt(10.0 * qty)})"
    raise 'Profit upnl mismatch' unless (up1.round(2) - (10.0 * qty)).abs < 0.01

    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 90.0)
    up2 = Orders.config.position(segment: seg, security_id: sid)[:upnl].to_f
    puts "  Loss UPNL:   ₹#{fmt(up2)} (expect #{fmt(-10.0 * qty)})"
    raise 'Loss upnl mismatch' unless (up2.round(2) - (-10.0 * qty)).abs < 0.01

    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 100.0)
    up3 = Orders.config.position(segment: seg, security_id: sid)[:upnl].to_f
    puts "  BE UPNL:     ₹#{fmt(up3)} (expect 0.00)"
    raise 'BE upnl mismatch' unless up3.round(2).abs < 0.01

    puts "\n✅ PnL states verified."
    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (pnl_states):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    #{"₹#{fmt(w_end[:used_amount])}"}"
    puts "  Equity:         ₹#{fmt(w_end[:equity])}"
    puts "  Realized PnL:   #{"₹#{fmt(w_end[:realized_pnl])}"}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"
  rescue StandardError => e
    puts "\n❌ PnL states verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end

  desc 'Verify reconciliation by re-instantiating gateway and checking state consistency'
  task verify_reconciliation: :environment do
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

    Orders.config = Paper::GatewayV2.new

    seg = 'NSE_FNO'
    sid = '50300'
    r1 = Orders.config.place_market(side: 'buy', segment: seg, security_id: sid, qty: 1, meta: { ltp: 150.0 })
    puts "ENTRY -> seg=#{seg} sid=#{sid} qty=1 price=150.00 order=#{r1&.order_no}"
    Orders.config.on_tick(segment: seg, security_id: sid, ltp: 155.0)
    snap_before = Orders.config.wallet_snapshot
    puts "  Wallet before restart: Cash=₹#{fmt(snap_before[:cash])} Equity=₹#{fmt(snap_before[:equity])} UPNL=₹#{fmt(snap_before[:unrealized_pnl])}"

    # Simulate restart by re-instantiating gateway (reads same Redis)
    Orders.config = Paper::GatewayV2.new
    snap_after = Orders.config.wallet_snapshot
    puts "  Wallet after restart:  Cash=₹#{fmt(snap_after[:cash])} Equity=₹#{fmt(snap_after[:equity])} UPNL=₹#{fmt(snap_after[:unrealized_pnl])}"

    puts "  Equity before: ₹#{fmt(snap_before[:equity])}"
    puts "  Equity after:  ₹#{fmt(snap_after[:equity])}"
    unless (snap_before[:equity].to_f.round(2) - snap_after[:equity].to_f.round(2)).abs < 0.01
      raise 'Equity mismatch after restart'
    end

    pos = Orders.config.position(segment: seg, security_id: sid)
    raise 'Position not found after restart' unless pos && pos[:qty] == 1

    puts "\n✅ Reconciliation verified."
    # Final wallet screenshot for this scenario
    w_end = Orders.config.wallet_snapshot
    puts "\nWallet after scenario (reconciliation):"
    puts "  Cash:           ₹#{fmt(w_end[:cash])}"
    puts "  Used Amount:    #{"₹#{fmt(w_end[:used_amount])}"}"
    puts "  Equity:         ₹#{fmt(w_end[:equity])}"
    puts "  Realized PnL:   #{"₹#{fmt(w_end[:realized_pnl])}"}"
    puts "  Unrealized PnL: #{"₹#{fmt(w_end[:unrealized_pnl])}"}"
    puts "  Fees Total:     #{"₹#{fmt(w_end[:fees_total])}"}"
  rescue StandardError => e
    puts "\n❌ Reconciliation verification failed: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
    exit 1
  end
end
