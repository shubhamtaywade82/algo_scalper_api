# frozen_string_literal: true

require 'csv'
require 'time'
require 'terminal-table'

module Utils
  # Parses research CSVs and generates a human-readable summary of market behavior
  class ResearchSummaryParser
    def self.summarize(file_path)
      unless File.exist?(file_path)
        puts "Error: File #{file_path} not found."
        return
      end

      rows = CSV.read(file_path, headers: true)
      return if rows.empty?

      stats = calculate_stats(rows)
      print_report(File.basename(file_path), stats)
    end

    private

    def self.calculate_stats(rows)
      spot_prices = rows.map { |r| r['spot_close'].to_f }
      ce_prices = rows.map { |r| r['ce_close'].to_f }.reject(&:zero?)
      pe_prices = rows.map { |r| r['pe_close'].to_f }.reject(&:zero?)
      ce_ivs = rows.map { |r| r['ce_iv'].to_f }.reject(&:zero?)
      pe_ivs = rows.map { |r| r['pe_iv'].to_f }.reject(&:zero?)

      # Group by day for intraday analysis
      days = rows.group_by { |r| Time.parse(r['timestamp']).to_date }

      day_stats = days.map do |date, day_rows|
        s_prices = day_rows.map { |r| r['spot_close'].to_f }
        c_prices = day_rows.map { |r| r['ce_close'].to_f }.reject(&:zero?)
        p_prices = day_rows.map { |r| r['pe_close'].to_f }.reject(&:zero?)

        {
          date: date,
          spot_range: (s_prices.max - s_prices.min).round(2),
          ce_move: c_prices.empty? ? 0 : ((c_prices.max / c_prices.min - 1) * 100).round(2),
          pe_move: p_prices.empty? ? 0 : ((p_prices.max / p_prices.min - 1) * 100).round(2)
        }
      end

      {
        start_date: rows.first['timestamp'],
        end_date: rows[-1]['timestamp'],
        total_minutes: rows.size,
        spot_min: spot_prices.min,
        spot_max: spot_prices.max,
        avg_ce_iv: (ce_ivs.sum / ce_ivs.size).round(2),
        avg_pe_iv: (pe_ivs.sum / pe_ivs.size).round(2),
        max_ce_price: ce_prices.max,
        max_pe_price: pe_prices.max,
        day_stats: day_stats
      }
    end

    def self.print_report(filename, s)
      puts "\n" + "=" * 60
      puts "📊 RESEARCH SUMMARY: #{filename}"
      puts "=" * 60
      puts "Period:      #{s[:start_date]} to #{s[:end_date]}"
      puts "Duration:    #{s[:total_minutes]} trading minutes"
      puts "Spot Range:  #{s[:spot_min]} - #{s[:spot_max]} (Δ #{ (s[:spot_max] - s[:spot_min]).round(2) })"
      puts "Average IV:  CE: #{s[:avg_ce_iv]} | PE: #{s[:avg_pe_iv]}"
      puts "-" * 60
      
      table = Terminal::Table.new do |t|
        t.headings = ['Date', 'Spot Δ', 'CE Max Move %', 'PE Max Move %']
        s[:day_stats].each do |d|
          t.add_row [d[:date], d[:spot_range], "#{d[:ce_move]}%", "#{d[:pe_move]}%"]
        end
      end
      
      puts table
      
      puts "\n💡 INSIGHTS:"
      best_ce_day = s[:day_stats].max_by { |d| d[:ce_move] }
      best_pe_day = s[:day_stats].max_by { |d| d[:pe_move] }
      
      puts "🚀 Best Call Momentum: #{best_ce_day[:ce_move]}% move on #{best_ce_day[:date]}"
      puts "📉 Best Put Momentum:  #{best_pe_day[:pe_move]}% move on #{best_pe_day[:date]}"
      puts "=" * 60 + "\n"
    end
  end
end
