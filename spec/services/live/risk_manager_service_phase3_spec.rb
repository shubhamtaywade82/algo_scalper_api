# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, 'Phase 3: Metrics & Circuit Breaker' do
  let(:service) { described_class.new }
  let(:exit_engine) { instance_double(Live::ExitEngine) }
  let(:service_with_exit_engine) { described_class.new(exit_engine: exit_engine) }

  describe 'Metrics & Monitoring' do
    describe '#record_cycle_metrics' do
      it 'records cycle time metrics' do
        service.record_cycle_metrics(
          cycle_time: 0.5,
          positions_count: 10,
          redis_fetches: 5,
          db_queries: 3,
          api_calls: 2
        )

        metrics = service.get_metrics
        expect(metrics[:cycle_count]).to eq(1)
        expect(metrics[:total_cycle_time]).to eq(0.5)
        expect(metrics[:min_cycle_time]).to eq(0.5)
        expect(metrics[:max_cycle_time]).to eq(0.5)
      end

      it 'tracks minimum and maximum cycle times' do
        service.record_cycle_metrics(cycle_time: 0.3, positions_count: 5, redis_fetches: 2, db_queries: 1, api_calls: 1)
        service.record_cycle_metrics(cycle_time: 0.8, positions_count: 15, redis_fetches: 8, db_queries: 5,
                                     api_calls: 3)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:min_cycle_time]).to eq(0.3)
        expect(metrics[:max_cycle_time]).to eq(0.8)
      end

      it 'accumulates positions count' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 15, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:total_positions]).to eq(25)
      end

      it 'accumulates Redis fetch count' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 8, db_queries: 3,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:total_redis_fetches]).to eq(13)
      end

      it 'accumulates DB query count' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 7,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:total_db_queries]).to eq(10)
      end

      it 'accumulates API call count' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 5)

        metrics = service.get_metrics
        expect(metrics[:total_api_calls]).to eq(7)
      end

      it 'tracks exit counts when provided' do
        service.record_cycle_metrics(
          cycle_time: 0.5,
          positions_count: 10,
          redis_fetches: 5,
          db_queries: 3,
          api_calls: 2,
          exit_counts: { stop_loss: 2, take_profit: 1, time_based: 1 }
        )

        metrics = service.get_metrics
        expect(metrics[:exit_stop_loss]).to eq(2)
        expect(metrics[:exit_take_profit]).to eq(1)
        expect(metrics[:exit_time_based]).to eq(1)
      end

      it 'tracks error counts when provided' do
        service.record_cycle_metrics(
          cycle_time: 0.5,
          positions_count: 10,
          redis_fetches: 5,
          db_queries: 3,
          api_calls: 2,
          error_counts: { api_error: 1, redis_error: 2 }
        )

        metrics = service.get_metrics
        expect(metrics[:error_api_error]).to eq(1)
        expect(metrics[:error_redis_error]).to eq(2)
      end
    end

    describe '#get_metrics' do
      it 'returns zero metrics when no cycles recorded' do
        metrics = service.get_metrics

        expect(metrics[:cycle_count]).to eq(0)
        expect(metrics[:avg_cycle_time]).to eq(0)
        expect(metrics[:min_cycle_time]).to be_nil
        expect(metrics[:max_cycle_time]).to be_nil
        expect(metrics[:avg_positions_per_cycle]).to eq(0)
      end

      it 'calculates average cycle time correctly' do
        service.record_cycle_metrics(cycle_time: 0.3, positions_count: 5, redis_fetches: 2, db_queries: 1, api_calls: 1)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.7, positions_count: 15, redis_fetches: 8, db_queries: 5,
                                     api_calls: 3)

        metrics = service.get_metrics
        expect(metrics[:avg_cycle_time]).to be_within(0.01).of(0.5)
      end

      it 'calculates average positions per cycle' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 20, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:avg_positions_per_cycle]).to eq(15)
      end

      it 'calculates average Redis fetches per cycle' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 10, db_queries: 3,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:avg_redis_fetches_per_cycle]).to eq(7.5)
      end

      it 'calculates average DB queries per cycle' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 7,
                                     api_calls: 2)

        metrics = service.get_metrics
        expect(metrics[:avg_db_queries_per_cycle]).to eq(5)
      end

      it 'calculates average API calls per cycle' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 8)

        metrics = service.get_metrics
        expect(metrics[:avg_api_calls_per_cycle]).to eq(5)
      end

      it 'includes exit counts in metrics' do
        service.record_cycle_metrics(
          cycle_time: 0.5,
          positions_count: 10,
          redis_fetches: 5,
          db_queries: 3,
          api_calls: 2,
          exit_counts: { stop_loss: 2, take_profit: 1 }
        )

        metrics = service.get_metrics
        expect(metrics[:exit_stop_loss]).to eq(2)
        expect(metrics[:exit_take_profit]).to eq(1)
      end

      it 'includes error counts in metrics' do
        service.record_cycle_metrics(
          cycle_time: 0.5,
          positions_count: 10,
          redis_fetches: 5,
          db_queries: 3,
          api_calls: 2,
          error_counts: { api_error: 3 }
        )

        metrics = service.get_metrics
        expect(metrics[:error_api_error]).to eq(3)
      end
    end

    describe '#reset_metrics' do
      it 'resets all metrics to zero' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.increment_metric(:exit_stop_loss)
        service.increment_metric(:error_api_error)

        service.reset_metrics

        metrics = service.get_metrics
        expect(metrics[:cycle_count]).to eq(0)
        expect(metrics[:total_cycle_time]).to eq(0)
        # After reset, metrics that were previously set are removed (nil), not 0
        # This is expected behavior - metrics only exist when they have values
        expect(metrics[:exit_stop_loss]).to be_nil
        expect(metrics[:error_api_error]).to be_nil
      end

      it 'allows recording metrics after reset' do
        service.record_cycle_metrics(cycle_time: 0.5, positions_count: 10, redis_fetches: 5, db_queries: 3,
                                     api_calls: 2)
        service.reset_metrics
        service.record_cycle_metrics(cycle_time: 0.3, positions_count: 5, redis_fetches: 2, db_queries: 1, api_calls: 1)

        metrics = service.get_metrics
        expect(metrics[:cycle_count]).to eq(1)
        expect(metrics[:avg_cycle_time]).to eq(0.3)
      end
    end
  end

  describe 'Circuit Breaker' do
    describe '#circuit_breaker_open?' do
      it 'returns false when circuit breaker is closed' do
        expect(service.circuit_breaker_open?).to be false
      end

      it 'returns true when circuit breaker is open' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_last_failure, Time.current)

        expect(service.circuit_breaker_open?).to be true
      end

      it 'returns false when timeout has passed and transitions to half_open' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_last_failure, Time.current - 70) # 70 seconds ago

        expect(service.circuit_breaker_open?).to be false
        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:half_open)
      end

      it 'returns false when circuit breaker is half_open' do
        service.instance_variable_set(:@circuit_breaker_state, :half_open)

        expect(service.circuit_breaker_open?).to be false
      end

      it 'accepts optional cache_key parameter' do
        expect(service.circuit_breaker_open?('some_key')).to be false
      end
    end

    describe '#record_api_failure' do
      it 'increments failure count' do
        service.record_api_failure

        expect(service.instance_variable_get(:@circuit_breaker_failures)).to eq(1)
      end

      it 'records last failure time' do
        before_time = Time.current
        service.record_api_failure
        after_time = Time.current

        last_failure = service.instance_variable_get(:@circuit_breaker_last_failure)
        expect(last_failure).to be_between(before_time, after_time)
      end

      it 'opens circuit breaker after threshold failures' do
        service.instance_variable_set(:@circuit_breaker_threshold, 3)

        2.times { service.record_api_failure }
        expect(service.circuit_breaker_open?).to be false

        service.record_api_failure # 3rd failure
        expect(service.circuit_breaker_open?).to be true
        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:open)
      end

      it 'logs warning when circuit breaker opens' do
        service.instance_variable_set(:@circuit_breaker_threshold, 1)
        allow(Rails.logger).to receive(:warn)

        service.record_api_failure

        expect(Rails.logger).to have_received(:warn).with(/Circuit breaker OPEN/)
      end

      it 'accepts optional cache_key parameter' do
        expect { service.record_api_failure('some_key') }.not_to raise_error
      end
    end

    describe '#record_api_success' do
      it 'closes circuit breaker from half_open state' do
        service.instance_variable_set(:@circuit_breaker_state, :half_open)
        service.instance_variable_set(:@circuit_breaker_failures, 3)

        service.record_api_success

        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:closed)
        expect(service.instance_variable_get(:@circuit_breaker_failures)).to eq(0)
      end

      it 'logs info when circuit breaker closes from half_open' do
        service.instance_variable_set(:@circuit_breaker_state, :half_open)
        allow(Rails.logger).to receive(:info)

        service.record_api_success

        expect(Rails.logger).to have_received(:info).with(/Circuit breaker CLOSED/)
      end

      it 'resets failures when circuit breaker is open' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_failures, 5)

        service.record_api_success

        expect(service.instance_variable_get(:@circuit_breaker_failures)).to eq(0)
      end

      it 'does not change state when circuit breaker is closed' do
        service.instance_variable_set(:@circuit_breaker_state, :closed)
        service.instance_variable_set(:@circuit_breaker_failures, 0)

        service.record_api_success

        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:closed)
        expect(service.instance_variable_get(:@circuit_breaker_failures)).to eq(0)
      end

      it 'accepts optional cache_key parameter' do
        expect { service.record_api_success('some_key') }.not_to raise_error
      end
    end

    describe '#reset_circuit_breaker' do
      it 'resets circuit breaker to closed state' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_failures, 5)
        service.instance_variable_set(:@circuit_breaker_last_failure, Time.current)

        service.reset_circuit_breaker

        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:closed)
        expect(service.instance_variable_get(:@circuit_breaker_failures)).to eq(0)
        expect(service.instance_variable_get(:@circuit_breaker_last_failure)).to be_nil
      end
    end

    describe 'Circuit Breaker Integration' do
      it 'prevents API calls when circuit breaker is open' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_last_failure, Time.current)

        expect(service.circuit_breaker_open?).to be true
      end

      it 'allows API calls after timeout when circuit breaker transitions to half_open' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        service.instance_variable_set(:@circuit_breaker_last_failure, Time.current - 70)

        expect(service.circuit_breaker_open?).to be false
        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:half_open)
      end

      it 'closes circuit breaker after successful API call from half_open' do
        service.instance_variable_set(:@circuit_breaker_state, :half_open)

        service.record_api_success

        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:closed)
      end

      it 'reopens circuit breaker if failure occurs in half_open state' do
        service.instance_variable_set(:@circuit_breaker_state, :half_open)
        service.instance_variable_set(:@circuit_breaker_threshold, 1)

        service.record_api_failure

        expect(service.instance_variable_get(:@circuit_breaker_state)).to eq(:open)
      end
    end
  end

  describe 'Health Status' do
    describe '#health_status' do
      before do
        service.instance_variable_set(:@started_at, Time.current - 100)
      end

      it 'returns health status hash' do
        status = service.health_status

        expect(status).to be_a(Hash)
        expect(status.keys).to include(:running, :thread_alive, :last_cycle_time, :active_positions, :circuit_breaker_state, :recent_errors, :uptime_seconds)
      end

      it 'includes running status' do
        service.instance_variable_set(:@running, true)
        status = service.health_status

        expect(status[:running]).to be true
      end

      it 'includes thread alive status' do
        thread = Thread.new { sleep 0.1 }
        service.instance_variable_set(:@thread, thread)
        status = service.health_status

        expect(status[:thread_alive]).to be true
        thread.kill
      end

      it 'includes last cycle time from metrics' do
        service.instance_variable_set(:@metrics, { last_cycle_time: 0.5 })
        status = service.health_status

        expect(status[:last_cycle_time]).to eq(0.5)
      end

      it 'includes active positions count' do
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(5)
        status = service.health_status

        expect(status[:active_positions]).to eq(5)
      end

      it 'includes circuit breaker state' do
        service.instance_variable_set(:@circuit_breaker_state, :open)
        status = service.health_status

        expect(status[:circuit_breaker_state]).to eq(:open)
      end

      it 'includes recent errors count' do
        service.instance_variable_set(:@metrics, { recent_api_errors: 3 })
        status = service.health_status

        expect(status[:recent_errors]).to eq(3)
      end

      it 'calculates uptime correctly when running' do
        service.instance_variable_set(:@running, true)
        service.instance_variable_set(:@started_at, Time.current - 120)
        status = service.health_status

        expect(status[:uptime_seconds]).to be_within(5).of(120)
      end

      it 'returns zero uptime when not running' do
        service.instance_variable_set(:@running, false)
        status = service.health_status

        expect(status[:uptime_seconds]).to eq(0)
      end
    end
  end
end
