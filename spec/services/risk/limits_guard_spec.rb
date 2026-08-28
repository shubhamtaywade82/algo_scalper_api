# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::LimitsGuard do
  let(:redis_double) { instance_double(Redis) }
  let(:active_relation) { instance_double(ActiveRecord::Relation, count: 0) }

  before do
    described_class.instance_variable_set(:@redis, nil)
    allow(Redis).to receive(:new).and_return(redis_double)
    allow(redis_double).to receive(:get).and_return(nil)
    allow(redis_double).to receive(:incr)
    allow(redis_double).to receive(:set)
    allow(redis_double).to receive(:expire)
    allow(PositionTracker).to receive(:active).and_return(active_relation)
    allow(AlgoConfig).to receive(:fetch).and_return({ risk_limits: {} })
  end

  describe '.check_all!' do
    context 'when no limits are breached' do
      it 'returns { blocked: false }' do
        result = described_class.check_all!
        expect(result).to eq({ blocked: false })
      end
    end

    context 'when daily max trades reached' do
      before do
        allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('10')
      end

      it 'returns blocked' do
        result = described_class.check_all!
        expect(result).to eq({ blocked: 'daily_max_trades_reached' })
      end
    end

    context 'when max open positions reached' do
      before do
        allow(active_relation).to receive(:count).and_return(3)
      end

      it 'returns blocked' do
        result = described_class.check_all!
        expect(result).to eq({ blocked: 'max_open_positions_reached' })
      end
    end

    context 'when consecutive losses breached' do
      before do
        allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('5')
        allow(redis_double).to receive(:get).with(described_class.consecutive_losses_key).and_return('3')
      end

      it 'returns blocked' do
        result = described_class.check_all!
        expect(result).to eq({ blocked: 'max_consecutive_losses_breached' })
      end
    end

    context 'with custom limits from AlgoConfig' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return({
          risk_limits: {
            daily_max_trades: 5,
            max_open_positions: 2,
            max_consecutive_losses: 1
          }
        })
      end

      it 'uses custom daily_max_trades limit' do
        allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('5')

        result = described_class.check_all!
        expect(result).to eq({ blocked: 'daily_max_trades_reached' })
      end

      it 'uses custom max_open_positions limit' do
        allow(active_relation).to receive(:count).and_return(2)

        result = described_class.check_all!
        expect(result).to eq({ blocked: 'max_open_positions_reached' })
      end

      it 'uses custom max_consecutive_losses limit' do
        allow(redis_double).to receive(:get).with(described_class.consecutive_losses_key).and_return('1')

        result = described_class.check_all!
        expect(result).to eq({ blocked: 'max_consecutive_losses_breached' })
      end
    end

    describe 'limit evaluation order' do
      it 'checks trades count before positions' do
        allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('10')

        result = described_class.check_all!
        expect(result[:blocked]).to eq('daily_max_trades_reached')
      end

      it 'checks open positions before consecutive losses' do
        allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('2')
        allow(active_relation).to receive(:count).and_return(3)
        allow(redis_double).to receive(:get).with(described_class.consecutive_losses_key).and_return('3')

        # It should block on max_open_positions before reaching consecutive_losses
        result = described_class.check_all!
        expect(result[:blocked]).to eq('max_open_positions_reached')
      end
    end
  end

  describe '.record_trade!' do
    it 'increments the trades count key' do
      described_class.record_trade!

      expect(redis_double).to have_received(:incr).with(described_class.trades_count_key)
      expect(redis_double).to have_received(:expire).with(described_class.trades_count_key, 86_400)
    end
  end

  describe '.record_win!' do
    it 'resets consecutive losses to 0' do
      described_class.record_win!

      expect(redis_double).to have_received(:set).with(described_class.consecutive_losses_key, 0)
      expect(redis_double).to have_received(:expire).with(described_class.consecutive_losses_key, 86_400)
    end
  end

  describe '.record_loss!' do
    it 'increments consecutive losses' do
      described_class.record_loss!

      expect(redis_double).to have_received(:incr).with(described_class.consecutive_losses_key)
      expect(redis_double).to have_received(:expire).with(described_class.consecutive_losses_key, 86_400)
    end
  end

  describe '.current_stats' do
    before do
      allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('7')
      allow(redis_double).to receive(:get).with(described_class.consecutive_losses_key).and_return('2')
      allow(active_relation).to receive(:count).and_return(1)
    end

    it 'returns current stats hash' do
      stats = described_class.current_stats
      expect(stats).to eq({
                            trades_count: 7,
                            consecutive_losses: 2,
                            active_positions: 1
                          })
    end

    context 'when Redis is nil (connection failed)' do
      before do
        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, 'connection refused')
      end

      it 'returns zeros for Redis-backed values' do
        stats = described_class.current_stats
        expect(stats[:trades_count]).to eq(0)
        expect(stats[:consecutive_losses]).to eq(0)
      end

      it 'still returns active_positions from the database' do
        stats = described_class.current_stats
        expect(stats[:active_positions]).to eq(1)
      end
    end

    context 'when stats keys do not exist in Redis' do
      before do
        allow(redis_double).to receive(:get).and_return(nil)
      end

      it 'returns 0 for missing Redis keys' do
        stats = described_class.current_stats
        expect(stats[:trades_count]).to eq(0)
        expect(stats[:consecutive_losses]).to eq(0)
      end
    end
  end

  describe '.check_all! when Redis is unavailable' do
    before do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, 'connection refused')
    end

    it 'returns { blocked: true } for trades/positions check (fail-closed on Redis failure)' do
      result = described_class.check_all!
      expect(result).to eq({ blocked: 'daily_max_trades_reached' })
    end
  end

  describe '#redis connection error handling' do
    before do
      described_class.instance_variable_set(:@redis, nil)
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError, 'connection refused')
      allow(Rails.logger).to receive(:error)
    end

    it 'logs the error at least once and returns blocked (fail-closed)' do
      result = described_class.check_all!

      expect(Rails.logger).to have_received(:error).with(/Redis error/).at_least(:once)
      expect(result).to eq({ blocked: 'daily_max_trades_reached' })
    end
  end

  describe 'key prefixes' do
    it 'scopes keys to current date' do
      expected_prefix = "risk:limits:#{Time.zone.today}"
      expect(described_class.key_prefix).to eq(expected_prefix)
      expect(described_class.trades_count_key).to eq("#{expected_prefix}:trades_count")
      expect(described_class.consecutive_losses_key).to eq("#{expected_prefix}:consecutive_losses")
    end
  end

  describe 'MAX_DAILY_DRAWDOWN constant' do
    it 'uses correct default max consecutive losses threshold' do
      # The check happens at class level, edge cases with thresholds just below limit
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk_limits: { max_consecutive_losses: 3 }
      })

      allow(redis_double).to receive(:get).with(described_class.trades_count_key).and_return('1')
      allow(redis_double).to receive(:get).with(described_class.consecutive_losses_key).and_return('2')

      result = described_class.check_all!
      expect(result).to eq({ blocked: false })
    end
  end
end
