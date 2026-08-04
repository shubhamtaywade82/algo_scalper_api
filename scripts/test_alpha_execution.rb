# frozen_string_literal: true

# scripts/test_alpha_execution.rb

# 1. Setup a valid signal for a contract we know exists
# We'll use a realistic strike for NIFTY (around 23200)
derivative = Derivative.where(underlying_symbol: 'NIFTY').where(expiry_date: Time.zone.today..).first

unless derivative
  puts "❌ Could not find any NIFTY derivative. Please check your DB."
  exit
end

puts "✅ Found test derivative: #{derivative.symbol_name} #{derivative.strike_price} #{derivative.expiry_date} #{derivative.option_type}"

# 2. Mock a Signal
signal = {
  index_key: :nifty,
  direction: derivative.option_type.downcase.to_sym,
  strike: derivative.strike_price.to_f,
  expiry: derivative.expiry_date.to_s,
  confidence: 0.85,
  expected_value: 1500.0,
  alpha_source: :momentum,
  timestamp: Time.current.iso8601,
  lot_size: 75,
  entry_price: 23_205.0, # Index price
  underlying_ltp: 23_205.0,
  stop_loss: 23_150.0,
  target: 23_300.0
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
