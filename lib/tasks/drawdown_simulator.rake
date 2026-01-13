# frozen_string_literal: true

namespace :drawdown do
  desc 'Simulate drawdown calculations for testing'
  task simulate: :environment do
    puts "\n=== Drawdown Schedule Simulator ===\n\n"

    include Positions::DrawdownSchedule

    puts '1. Upward Drawdown Schedule (NIFTY):'
    puts '   Profit% => Allowed Drawdown%'
    [3, 5, 7, 10, 15, 20, 25, 30].each do |p|
      dd = allowed_upward_drawdown_pct(p, index_key: 'NIFTY')
      puts "   #{p.to_s.rjust(3)}% => #{dd.round(2).to_s.rjust(6)}%"
    end

    puts "\n2. Upward Drawdown Schedule (BANKNIFTY):"
    puts '   Profit% => Allowed Drawdown%'
    [3, 5, 7, 10, 15, 20, 25, 30].each do |p|
      dd = allowed_upward_drawdown_pct(p, index_key: 'BANKNIFTY')
      puts "   #{p.to_s.rjust(3)}% => #{dd.round(2).to_s.rjust(6)}%"
    end

    puts "\n3. Reverse Dynamic SL Schedule:"
    puts '   PnL% => Allowed Loss% (no time penalty)'
    [-1, -3, -5, -10, -15, -20, -25, -30].each do |p|
      sl = reverse_dynamic_sl_pct(p, seconds_below_entry: 0, atr_ratio: 1.0)
      puts "   #{p.to_s.rjust(4)}% => #{sl.round(2).to_s.rjust(6)}%"
    end

    puts "\n4. Reverse Dynamic SL with Time Tightening (2 min below entry):"
    puts '   PnL% => Allowed Loss%'
    [-1, -5, -10, -15, -20].each do |p|
      sl = reverse_dynamic_sl_pct(p, seconds_below_entry: 120, atr_ratio: 1.0)
      puts "   #{p.to_s.rjust(4)}% => #{sl.round(2).to_s.rjust(6)}%"
    end

    puts "\n5. Reverse Dynamic SL with ATR Penalty (ATR ratio 0.6):"
    puts '   PnL% => Allowed Loss%'
    [-1, -5, -10, -15, -20].each do |p|
      sl = reverse_dynamic_sl_pct(p, seconds_below_entry: 0, atr_ratio: 0.6)
      puts "   #{p.to_s.rjust(4)}% => #{sl.round(2).to_s.rjust(6)}%"
    end

    puts "\n6. SL Price Calculation Examples:"
    entry_prices = [50.0, 100.0, 200.0]
    loss_pcts = [5.0, 10.0, 15.0]

    entry_prices.each do |entry|
      loss_pcts.each do |loss|
        sl_price = sl_price_from_entry(entry, loss)
        puts "   Entry: ₹#{entry.round(2)}, Loss: #{loss}% => SL: ₹#{sl_price.round(2)}"
      end
    end

    puts "\n=== Simulation Complete ===\n"
  end
end
