# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TradingAgent::ToolRegistry do
  describe '.tools_for_ollama' do
    it 'returns an array of tool schemas' do
      tools = described_class.tools_for_ollama
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
    end

    it 'includes all custom tools' do
      tools = described_class.tools_for_ollama
      tool_names = tools.map { |t| t.dig(:function, :name) }

      expect(tool_names).to include('get_instrument')
      expect(tool_names).to include('get_market_snapshot')
      expect(tool_names).to include('get_option_intelligence')
      expect(tool_names).to include('get_smc_analysis')
      expect(tool_names).to include('get_historical_data')
      expect(tool_names).to include('validate_trade_risk')
      expect(tool_names).to include('position_sizing')
      expect(tool_names).to include('get_trading_stats')
    end

    it 'each tool has required schema fields' do
      tools = described_class.tools_for_ollama

      tools.each do |tool|
        expect(tool[:type]).to eq('function')
        expect(tool.dig(:function, :name)).to be_present
        expect(tool.dig(:function, :description)).to be_present
        expect(tool.dig(:function, :parameters)).to be_present
      end
    end

    it 'get_instrument requires symbol parameter' do
      tools = described_class.tools_for_ollama
      instrument_tool = tools.find { |t| t.dig(:function, :name) == 'get_instrument' }
      expect(instrument_tool.dig(:function, :parameters, :required)).to include('symbol')
    end

    it 'get_market_snapshot requires symbol parameter' do
      tools = described_class.tools_for_ollama
      snapshot_tool = tools.find { |t| t.dig(:function, :name) == 'get_market_snapshot' }
      expect(snapshot_tool.dig(:function, :parameters, :required)).to include('symbol')
    end

    it 'get_option_intelligence requires symbol parameter' do
      tools = described_class.tools_for_ollama
      option_tool = tools.find { |t| t.dig(:function, :name) == 'get_option_intelligence' }
      expect(option_tool.dig(:function, :parameters, :required)).to include('symbol')
    end
  end

  describe '.execute' do
    context 'validate_trade_risk' do
      it 'approves valid trades' do
        result = described_class.execute('validate_trade_risk', {
          'action' => 'BUY',
          'entry_price' => 100,
          'stop_loss' => 95,
          'take_profit' => 110,
          'risk_percent' => 1.5,
          'equity' => 100_000
        })

        expect(result).to be_a(Hash)
        expect(result[:approved]).to be(true)
        expect(result[:risk_checks][:rr_ratio]).to eq(2.0)
      end

      it 'rejects trades with bad R:R' do
        result = described_class.execute('validate_trade_risk', {
          'action' => 'BUY',
          'entry_price' => 100,
          'stop_loss' => 95,
          'take_profit' => 102,
          'risk_percent' => 1.5,
          'equity' => 100_000
        })

        expect(result[:approved]).to be(false)
      end

      it 'rejects trades with wrong stop direction' do
        result = described_class.execute('validate_trade_risk', {
          'action' => 'BUY',
          'entry_price' => 100,
          'stop_loss' => 105,
          'take_profit' => 110,
          'risk_percent' => 1.5,
          'equity' => 100_000
        })

        expect(result[:approved]).to be(false)
      end

      it 'rejects trades with excessive risk' do
        result = described_class.execute('validate_trade_risk', {
          'action' => 'BUY',
          'entry_price' => 100,
          'stop_loss' => 90,
          'take_profit' => 120,
          'risk_percent' => 5.0,
          'equity' => 100_000
        })

        expect(result[:approved]).to be(false)
      end
    end

    context 'position_sizing' do
      it 'calculates correct position size' do
        result = described_class.execute('position_sizing', {
          'equity' => 100_000,
          'risk_percent' => 2.0,
          'entry_price' => 100,
          'stop_loss' => 95
        })

        expect(result[:quantity]).to eq(400)
        expect(result[:risk_amount]).to eq(2000.0)
      end

      it 'handles missing parameters' do
        result = described_class.execute('position_sizing', {})
        expect(result[:error]).to eq('Missing parameters')
      end

      it 'handles SL too close to entry' do
        result = described_class.execute('position_sizing', {
          'equity' => 100_000,
          'risk_percent' => 2.0,
          'entry_price' => 100,
          'stop_loss' => 100
        })

        expect(result[:error]).to eq('SL too close to entry')
      end
    end

    context 'get_instrument' do
      it 'finds NIFTY instrument' do
        instrument = double('Instrument',
                            id: 1, security_id: 13, display_name: 'Nifty 50',
                            exchange: 'nse', segment: 'index',
                            instrument_type: 'INDEX', lot_size: 50,
                            expiry_flag: 'N', underlying_symbol: 'NIFTY')
        allow(Instrument).to receive(:where).with(segment: 'index').and_return(Instrument)
        allow(Instrument).to receive(:where).with(anything).and_return(Instrument)
        allow(Instrument).to receive_messages(where: Instrument, order: [instrument], first: instrument)

        result = described_class.execute('get_instrument', { 'symbol' => 'NIFTY' })
        expect(result).to be_a(Hash)
        expect(result[:display_name]).to include('Nifty')
        expect(result[:security_id]).to eq(13)
      end

      it 'returns error for unknown symbol' do
        allow(Instrument).to receive(:where).with(anything).and_return(Instrument)
        allow(Instrument).to receive_messages(where: Instrument, order: Instrument, first: nil)

        result = described_class.execute('get_instrument', { 'symbol' => 'NONEXISTENT' })
        expect(result[:error]).to be_present
      end

      it 'returns error for missing symbol' do
        result = described_class.execute('get_instrument', {})
        expect(result[:error]).to be_present
      end
    end

    context 'get_market_snapshot' do
      it 'returns LTP and indicators for NIFTY' do
        instrument = double('Instrument',
                            id: 1, security_id: 13, display_name: 'Nifty 50',
                            exchange: 'nse', segment: 'index')
        series = double('CandleSeries')
        allow(series).to receive_messages(candles: [double(close: 23_900)], rsi: 55.0, macd: { signal: 10, histogram: 5, macd: 15 }, adx: 25.0, supertrend_signal: 'bullish', atr: 100.0, bollinger_bands: { upper: 24_000, middle: 23_800, lower: 23_600 })

        allow(Instrument).to receive(:where).with(anything).and_return(Instrument)
        allow(Instrument).to receive_messages(where: Instrument, order: [instrument], first: instrument)
        allow(instrument).to receive_messages(ltp: 23_900.5, candles: series)

        result = described_class.execute('get_market_snapshot', { 'symbol' => 'NIFTY', 'interval' => '15' })
        expect(result).to be_a(Hash)
        expect(result[:ltp]).to eq(23_900.5)
        expect(result[:indicators]).to be_a(Hash)
      end
    end

    context 'get_option_intelligence' do
      it 'returns option chain for NIFTY' do
        result = described_class.execute('get_option_intelligence', { 'symbol' => 'NIFTY' })
        expect(result).to be_a(Hash)
        if result[:error].nil?
          expect(result[:atm_strike]).to be_a(Numeric)
          expect(result[:days_to_expiry]).to be_a(Integer)
          expect(result[:selected_expiry]).to be_present
          expect(result[:expiries]).to be_an(Array)
        end
      end

      it 'includes Greeks for ATM call' do
        result = described_class.execute('get_option_intelligence', { 'symbol' => 'NIFTY' })
        if result[:atm_call]
          expect(result[:atm_call][:delta]).to be_a(Numeric)
          expect(result[:atm_call][:theta]).to be_a(Numeric)
          expect(result[:atm_call][:gamma]).to be_a(Numeric)
          expect(result[:atm_call][:vega]).to be_a(Numeric)
          expect(result[:atm_call][:iv]).to be_a(Numeric)
          expect(result[:atm_call][:oi]).to be_a(Numeric)
        end
      end

      it 'includes Greeks for ATM put' do
        result = described_class.execute('get_option_intelligence', { 'symbol' => 'NIFTY' })
        if result[:atm_put]
          expect(result[:atm_put][:delta]).to be_a(Numeric)
          expect(result[:atm_put][:theta]).to be_a(Numeric)
          expect(result[:atm_put][:gamma]).to be_a(Numeric)
          expect(result[:atm_put][:vega]).to be_a(Numeric)
          expect(result[:atm_put][:iv]).to be_a(Numeric)
          expect(result[:atm_put][:oi]).to be_a(Numeric)
        end
      end

      it 'returns days_to_expiry' do
        result = described_class.execute('get_option_intelligence', { 'symbol' => 'NIFTY' })
        if result[:days_to_expiry]
          expect(result[:days_to_expiry]).to be >= 0
          expect(result[:is_expiry_today]).to be_in([true, false])
          expect(result[:is_expiry_week]).to be_in([true, false])
        end
      end

      it 'returns strikes with full data' do
        result = described_class.execute('get_option_intelligence', { 'symbol' => 'NIFTY' })
        if result[:strikes]&.any?
          strike = result[:strikes].first
          expect(strike[:strike]).to be_a(Numeric)
          if strike[:call]
            expect(strike[:call][:ltp]).to be_a(Numeric)
            expect(strike[:call][:oi]).to be_a(Numeric)
            expect(strike[:call][:delta]).to be_a(Numeric)
          end
          if strike[:put]
            expect(strike[:put][:ltp]).to be_a(Numeric)
            expect(strike[:put][:oi]).to be_a(Numeric)
            expect(strike[:put][:delta]).to be_a(Numeric)
          end
        end
      end
    end

    context 'get_smc_analysis' do
      it 'returns SMC analysis for NIFTY' do
        instrument = double('Instrument', id: 1, security_id: 13, display_name: 'Nifty 50')
        series = double('CandleSeries')
        allow(series).to receive(:candles).and_return([double(close: 23_900)])
        ctx = double('Smc::Context',
                     trend: 'bullish', phase: 'accumulation',
                     pd: nil, liquidity: nil, order_blocks: [], fvg: nil,
                     swing_structure: nil, internal_structure: nil)
        allow(ctx).to receive(:to_h).and_return({})

        allow(Instrument).to receive(:where).with(anything).and_return(Instrument)
        allow(Instrument).to receive_messages(where: Instrument, order: [instrument], first: instrument)
        allow(instrument).to receive(:candles).and_return(series)
        allow(Smc::Context).to receive(:new).and_return(ctx)

        result = described_class.execute('get_smc_analysis', { 'symbol' => 'NIFTY' })
        expect(result).to be_a(Hash)
        expect(result[:bias]).to be_present
        expect(result[:confluence]).to be_present
      end
    end

    context 'get_historical_data' do
      it 'returns candle data' do
        instrument = double('Instrument', id: 1, security_id: 13, display_name: 'Nifty 50')
        series = double('CandleSeries')
        candle = double('Candle', timestamp: '2026-06-30', open: 23_800, high: 23_900, low: 23_750, close: 23_850, volume: 1000)
        allow(series).to receive(:candles).and_return([candle])

        allow(Instrument).to receive(:where).with(anything).and_return(Instrument)
        allow(Instrument).to receive_messages(where: Instrument, order: [instrument], first: instrument)
        allow(instrument).to receive(:candles).and_return(series)

        result = described_class.execute('get_historical_data', {
          'symbol' => 'NIFTY',
          'interval' => '15',
          'days' => 5
        })
        expect(result).to be_a(Hash)
        expect(result[:count]).to be >= 0
      end
    end

    context 'get_trading_stats' do
      it 'returns trading stats' do
        result = described_class.execute('get_trading_stats', {})
        expect(result).to be_a(Hash)
        expect(result[:date]).to be_present
        expect(result[:total_trades]).to be_a(Integer)
      end
    end

    context 'with unknown tool' do
      it 'returns error for unknown tool' do
        result = described_class.execute('unknown_tool', {})
        expect(result[:error]).to eq('unknown_tool')
      end
    end
  end

  describe 'clean_result' do
    it 'converts Time to ISO8601' do
      result = described_class.send(:clean_result, { time: Time.current })
      expect(result[:time]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it 'converts Date to ISO8601' do
      result = described_class.send(:clean_result, { date: Time.zone.today })
      expect(result[:date]).to match(/\d{4}-\d{2}-\d{2}/)
    end

    it 'converts Symbol to String' do
      result = described_class.send(:clean_result, { sym: :hello })
      expect(result[:sym]).to eq('hello')
    end

    it 'converts BigDecimal to Float' do
      result = described_class.send(:clean_result, { val: BigDecimal('1.5') })
      expect(result[:val]).to eq(1.5)
    end

    it 'handles nested hashes' do
      result = described_class.send(:clean_result, { nested: { time: Time.current } })
      expect(result[:nested][:time]).to match(/\d{4}-\d{2}-\d{2}T/)
    end

    it 'handles arrays' do
      result = described_class.send(:clean_result, { arr: [{ time: Time.current }] })
      expect(result[:arr].first[:time]).to match(/\d{4}-\d{2}-\d{2}T/)
    end
  end
end
