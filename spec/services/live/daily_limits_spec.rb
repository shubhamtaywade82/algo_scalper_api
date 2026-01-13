# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::DailyLimits do
  let(:redis) { instance_double(Redis) }
  let(:daily_limits) { described_class.new(redis: redis) }

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        max_daily_loss_pct: 5000.0, # ₹5000 max loss per index
        max_global_daily_loss_pct: 10_000.0, # ₹10000 max loss globally
        max_daily_trades: 10, # 10 trades per index
        max_global_daily_trades: 20 # 20 trades globally
      }
    )
    allow(redis).to receive(:get).and_return('0')
    allow(redis).to receive(:incrbyfloat)
    allow(redis).to receive(:incr)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:scan_each)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:error)
  end

  describe '#can_trade?' do
    context 'when Redis is unavailable' do
      let(:daily_limits) do
        instance = described_class.new
        instance.instance_variable_set(:@redis, nil)
        instance
      end

      it 'returns not allowed with redis_unavailable reason' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq('redis_unavailable')
      end
    end

    context 'when daily loss limit is not exceeded' do
      before do
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1000.0')
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('2000.0')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:NIFTY/).and_return('5')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:global/).and_return('10')
      end

      it 'returns allowed' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be true
        expect(result[:reason]).to be_nil
      end
    end

    context 'when daily loss limit is exceeded (per-index)' do
      before do
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('6000.0') # Exceeds 5000
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('2000.0')
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'returns not allowed with daily_loss_limit_exceeded reason' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq('daily_loss_limit_exceeded')
        expect(result[:daily_loss]).to eq(6000.0)
        expect(result[:max_daily_loss]).to eq(5000.0)
        expect(result[:index_key]).to eq('NIFTY')
      end
    end

    context 'when global daily loss limit is exceeded' do
      before do
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1000.0')
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('12000.0') # Exceeds 10000
      end

      it 'returns not allowed with global_daily_loss_limit_exceeded reason' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq('global_daily_loss_limit_exceeded')
        expect(result[:global_daily_loss]).to eq(12_000.0)
        expect(result[:max_global_loss]).to eq(10_000.0)
      end
    end

    context 'when trade frequency limit is exceeded (per-index)' do
      before do
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1000.0')
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('2000.0')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:NIFTY/).and_return('12') # Exceeds 10
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:global/).and_return('15')
      end

      it 'returns not allowed with trade_frequency_limit_exceeded reason' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq('trade_frequency_limit_exceeded')
        expect(result[:daily_trades]).to eq(12)
        expect(result[:max_daily_trades]).to eq(10)
        expect(result[:index_key]).to eq('NIFTY')
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context 'when global trade frequency limit is exceeded' do
      before do
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1000.0')
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('2000.0')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:NIFTY/).and_return('5')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:global/).and_return('25') # Exceeds 20
      end

      it 'returns not allowed with global_trade_frequency_limit_exceeded reason' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be false
        expect(result[:reason]).to eq('global_trade_frequency_limit_exceeded')
        expect(result[:global_daily_trades]).to eq(25)
        expect(result[:max_global_trades]).to eq(20)
      end
    end

    context 'when config keys use alternative names' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          risk: {
            daily_loss_limit_pct: 5000.0, # Alternative key name
            global_daily_loss_limit_pct: 10_000.0,
            daily_trade_limit: 10, # Alternative key name
            global_daily_trade_limit: 20
          }
        )
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1000.0')
        allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('2000.0')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:NIFTY/).and_return('5')
        allow(redis).to receive(:get).with(/daily_limits:trades:.*:global/).and_return('10')
      end

      it 'uses alternative config key names' do
        result = daily_limits.can_trade?(index_key: 'NIFTY')

        expect(result[:allowed]).to be true
      end
    end
  end

  describe '#record_loss' do
    it 'increments per-index loss counter' do
      loss_key = /daily_limits:loss:.*:NIFTY/
      daily_limits.record_loss(index_key: 'NIFTY', amount: 500.0)

      expect(redis).to have_received(:incrbyfloat).with(loss_key, 500.0)
      expect(redis).to have_received(:expire).with(loss_key, anything)
    end

    it 'increments global loss counter' do
      global_loss_key = /daily_limits:loss:.*:global/
      daily_limits.record_loss(index_key: 'NIFTY', amount: 500.0)

      expect(redis).to have_received(:incrbyfloat).with(global_loss_key, 500.0)
      expect(redis).to have_received(:expire).with(global_loss_key, anything)
    end

    it 'logs the loss recording' do
      allow(redis).to receive(:get).and_return('1000.0')
      daily_limits.record_loss(index_key: 'NIFTY', amount: 500.0)

      expect(Rails.logger).to have_received(:info).with(/Recorded loss for NIFTY/)
    end

    it 'returns false if Redis is unavailable' do
      daily_limits_nil = described_class.new
      daily_limits_nil.instance_variable_set(:@redis, nil)
      result = daily_limits_nil.record_loss(index_key: 'NIFTY', amount: 500.0)

      expect(result).to be false
    end

    it 'returns false if amount is not positive' do
      result = daily_limits.record_loss(index_key: 'NIFTY', amount: 0)

      expect(result).to be false
      expect(redis).not_to have_received(:incrbyfloat)
    end
  end

  describe '#record_trade' do
    it 'increments per-index trade counter' do
      trades_key = /daily_limits:trades:.*:NIFTY/
      daily_limits.record_trade(index_key: 'NIFTY')

      expect(redis).to have_received(:incr).with(trades_key)
      expect(redis).to have_received(:expire).with(trades_key, anything)
    end

    it 'increments global trade counter' do
      global_trades_key = /daily_limits:trades:.*:global/
      daily_limits.record_trade(index_key: 'NIFTY')

      expect(redis).to have_received(:incr).with(global_trades_key)
      expect(redis).to have_received(:expire).with(global_trades_key, anything)
    end

    it 'returns false if Redis is unavailable' do
      daily_limits_nil = described_class.new
      daily_limits_nil.instance_variable_set(:@redis, nil)
      result = daily_limits_nil.record_trade(index_key: 'NIFTY')

      expect(result).to be false
    end
  end

  describe '#reset_daily_counters' do
    it 'deletes all daily limit keys for today' do
      keys = [
        'daily_limits:loss:2024-01-15:NIFTY',
        'daily_limits:trades:2024-01-15:NIFTY',
        'daily_limits:loss:2024-01-15:global'
      ]
      allow(redis).to receive(:scan_each).and_yield(keys[0]).and_yield(keys[1]).and_yield(keys[2])
      allow(redis).to receive(:del)

      result = daily_limits.reset_daily_counters

      expect(result).to be true
      expect(redis).to have_received(:del).exactly(3).times
    end

    it 'logs the reset operation' do
      allow(redis).to receive(:scan_each)
      daily_limits.reset_daily_counters

      expect(Rails.logger).to have_received(:info).with(/Reset daily counters/)
    end

    it 'returns false if Redis is unavailable' do
      daily_limits_nil = described_class.new
      daily_limits_nil.instance_variable_set(:@redis, nil)
      result = daily_limits_nil.reset_daily_counters

      expect(result).to be false
    end
  end

  describe '#get_daily_loss' do
    it 'returns daily loss for index' do
      allow(redis).to receive(:get).with(/daily_limits:loss:.*:NIFTY/).and_return('1500.0')

      result = daily_limits.get_daily_loss('NIFTY')

      expect(result).to eq(1500.0)
    end

    it 'returns 0.0 if key does not exist' do
      allow(redis).to receive(:get).and_return(nil)

      result = daily_limits.get_daily_loss('NIFTY')

      expect(result).to eq(0.0)
    end

    it 'returns 0.0 if Redis is unavailable' do
      daily_limits_nil = described_class.new
      daily_limits_nil.instance_variable_set(:@redis, nil)
      result = daily_limits_nil.get_daily_loss('NIFTY')

      expect(result).to eq(0.0)
    end
  end

  describe '#get_global_daily_loss' do
    it 'returns global daily loss' do
      allow(redis).to receive(:get).with(/daily_limits:loss:.*:global/).and_return('5000.0')

      result = daily_limits.get_global_daily_loss

      expect(result).to eq(5000.0)
    end
  end

  describe '#get_daily_trades' do
    it 'returns daily trade count for index' do
      allow(redis).to receive(:get).with(/daily_limits:trades:.*:NIFTY/).and_return('8')

      result = daily_limits.get_daily_trades('NIFTY')

      expect(result).to eq(8)
    end

    it 'returns 0 if key does not exist' do
      allow(redis).to receive(:get).and_return(nil)

      result = daily_limits.get_daily_trades('NIFTY')

      expect(result).to eq(0)
    end
  end

  describe '#get_global_daily_trades' do
    it 'returns global daily trade count' do
      allow(redis).to receive(:get).with(/daily_limits:trades:.*:global/).and_return('15')

      result = daily_limits.get_global_daily_trades

      expect(result).to eq(15)
    end
  end

  describe 'normalization' do
    it 'normalizes index key to uppercase string' do
      allow(redis).to receive(:get).and_return('0')
      daily_limits.can_trade?(index_key: :nifty)

      expect(redis).to have_received(:get).with(/daily_limits:loss:.*:NIFTY/)
    end

    it 'handles string index keys' do
      allow(redis).to receive(:get).and_return('0')
      daily_limits.can_trade?(index_key: 'banknifty')

      expect(redis).to have_received(:get).with(/daily_limits:loss:.*:BANKNIFTY/)
    end
  end
end
