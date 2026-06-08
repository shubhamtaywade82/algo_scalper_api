# scripts/test_alpha_real_data.rb
# frozen_string_literal: true

puts "🚀 Starting real market data scan for Alpha Engine..."

# 1. Initialize the Signal Engine for all indices
engine = SignalEngine.new(indices: %i[nifty banknifty sensex])

# 2. Run the scan
signals = engine.run

puts "\n🎯 Scan complete. Found #{signals.size} actionable signal(s).\n"

# 3. Process each signal found
signals.each do |signal|
  puts "--------------------------------------------------"
  puts "Source:     #{signal[:alpha_source].to_s.titleize}"
  puts "Instrument: #{signal[:index_key].to_s.upcase} #{signal[:strike]} #{signal[:direction].to_s.upcase}"
  puts "Expiry:     #{signal[:expiry]}"
  puts "Entry:      ₹#{signal[:entry_price]}"
  puts "Target:     ₹#{signal[:target]}"
  puts "Stop Loss:  ₹#{signal[:stop_loss]}"
  puts "Confidence: #{(signal[:confidence] * 100).round(1)}%"
  puts "Exp. Value: ₹#{signal[:expected_value]}"
  
  puts "\n⚙️ Attempting paper execution..."
  
  result = AlphaExecutionService.execute(signal)
  
  if result[:status] == :success
    puts "✅ EXECUTED successfully."
    puts "   Order ID: #{result[:order_id]}"
    
    tracker = PositionTracker.find_by(order_no: result[:order_id])
    if tracker
      puts "   Tracker ID: #{tracker.id}, Qty: #{tracker.quantity}"
    end
  else
    puts "❌ EXECUTION FAILED."
    puts "   Reason: #{result[:reason]}"
  end
end

if signals.empty?
  puts "No signals met the confidence threshold (> 0.55) or market criteria right now."
end
