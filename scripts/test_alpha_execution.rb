# scripts/test_alpha_execution.rb

# 1. Setup a valid signal for a contract we know exists
# We'll use the NIFTY 30000 CE (expiry June 30) found earlier
derivative = Derivative.find_by(underlying_symbol: 'NIFTY', strike_price: 30000, expiry_date: '2026-06-30', option_type: 'CE')

unless derivative
  puts "❌ Could not find test derivative. Please check your DB."
  exit
end

puts "✅ Found test derivative: #{derivative.symbol_name} #{derivative.strike_price} #{derivative.expiry_date} #{derivative.option_type}"

# 2. Mock a Signal
signal = {
  index_key: :nifty,
  direction: :ce,
  strike: 30000,
  expiry: '2026-06-30',
  confidence: 0.85,
  expected_value: 1500.0,
  alpha_source: :momentum,
  timestamp: Time.current.iso8601,
  lot_size: 25,
  entry_price: 24500.0, # Index price
  stop_loss: 24400.0,
  target: 24700.0
}

puts "🚀 Executing Alpha Signal via AlphaExecutionService..."

# 3. Trigger Execution
result = AlphaExecutionService.execute(signal)

puts "--- Execution Result ---"
puts "Status: #{result[:status]}"
if result[:status] == :success
  puts "Order ID: #{result[:order_id]}"
  
  # 4. Verify Side Effects
  tracker = PositionTracker.find_by(order_no: result[:order_id])
  if tracker
    puts "✅ PositionTracker created: ID=#{tracker.id}, Symbol=#{tracker.symbol}, Qty=#{tracker.quantity}"
    puts "   Alpha Source: #{tracker.meta['alpha_source']}"
    puts "   Expected Value: #{tracker.meta['expected_value']}"
  else
    puts "❌ Order placed but PositionTracker was NOT found (check InstrumentHelpers)."
  end
  
  audit = AlphaSignal.find_by(order_id: result[:order_id])
  if audit
    puts "✅ AlphaSignal Audit recorded: Source=#{audit.alpha_source}, Status=#{audit.status}"
  else
    puts "❌ AlphaSignal audit entry was NOT found."
  end
  
else
  puts "❌ Execution Failed: #{result[:reason]}"
end
