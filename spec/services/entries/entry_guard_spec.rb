# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO', cooldown_sec: 0 } }
  let(:pick) { { symbol: 'NIFTY24MAR22000CE', security_id: '12345', segment: 'NSE_FNO', ltp: BigDecimal('150.0') } }
  let(:direction) { 'LONG' }
  let(:signal) { double(record_entry_outcome: true) } # rubocop:disable RSpec/VerifiedDoubles
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: 'NSE', segment: 'index', security_id: '13') }
  let(:ltp) { BigDecimal('150.0') }

  describe '.try_enter' do
    before do
      instrument
      # Generic pipeline pass
      allow(described_class.entry_guard_pipeline).to receive(:run).and_return(Entries::EntryGuardPipeline::PASS)

      # Mock order execution
      allow(Entries::OrderExecutionService).to receive(:call).and_return(instance_double(PositionTracker))
    end

    context 'when pipeline fails' do
      let(:blocked_reason) { 'pipeline_reason' }

      before do
        allow(described_class.entry_guard_pipeline).to receive(:run).and_return({ blocked: blocked_reason })
      end

      it 'blocks entry and records outcome' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be false
        expect(signal).to have_received(:record_entry_outcome).with('blocked', blocked_reason)
      end
    end

    context 'when order execution fails' do
      before do
        allow(Entries::OrderExecutionService).to receive(:call).and_return({ error: 'order_failed' })
      end

      context 'when quantity calculation fails' do
        it 'returns false when quantity is zero' do
          allow(Capital::Allocator).to receive(:qty_for).and_return(0)

          expect do
            result = described_class.try_enter(
              index_cfg: index_cfg,
              pick: pick,
              direction: :bullish
            )

            expect(result).to be false
          end.not_to change(PositionTracker, :count)
        end
      end
    end

    context 'when successful' do
      it 'enters and records success' do
        expect(described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: direction, signal: signal)).to be true
        expect(signal).to have_received(:record_entry_outcome).with('entered')
      end
    end

    context 'when position_side is short (selling)' do
      it 'derives short_pe for a bullish bias and passes position_side through' do
        described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: :bullish, position_side: 'short')

        expect(Entries::OrderExecutionService).to have_received(:call)
          .with(hash_including(side: 'short_pe', position_side: 'short'))
      end

      it 'derives short_ce for a bearish bias' do
        described_class.try_enter(index_cfg: index_cfg, pick: pick, direction: :bearish, position_side: 'short')

        expect(Entries::OrderExecutionService).to have_received(:call)
          .with(hash_including(side: 'short_ce', position_side: 'short'))
      end
    end
  end

  describe '.record_signal_to_order_latency!' do
    it 'stores a positive signal_to_order_ms in tracker.execution' do
      tracker = create(:position_tracker)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 0.05 # simulate 50ms elapsed

      described_class.send(:record_signal_to_order_latency!, tracker, started_at)

      expect(tracker.reload.execution['signal_to_order_ms']).to be >= 50
    end

    it 'preserves other keys already present in execution' do
      tracker = create(:position_tracker, execution: { 'type' => 'stop_loss' })

      described_class.send(:record_signal_to_order_latency!, tracker, Process.clock_gettime(Process::CLOCK_MONOTONIC))

      expect(tracker.reload.execution).to include('type' => 'stop_loss', 'signal_to_order_ms' => a_value >= 0)
    end

    it 'does not raise for an object without an execution column' do
      expect { described_class.send(:record_signal_to_order_latency!, Object.new, Process.clock_gettime(Process::CLOCK_MONOTONIC)) }
        .not_to raise_error
    end
  end

  describe Entries::Guards::ExposureGuard do
    describe '.exposure_ok?' do
      let(:db_instrument) { create(:instrument) }

      it 'returns true when under limit' do
        expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 3)).to be true
      end

      it 'returns false when at limit' do
        create_list(:position_tracker, 2, instrument: db_instrument, status: 'active', side: 'long_ce', segment: 'NSE_FNO', security_id: '999')
        expect(described_class.exposure_ok?(instrument: db_instrument, side: 'long_ce', max_same_side: 2)).to be false
      end
    end
  end

  describe '.build_client_order_id' do
    let(:index_cfg) { { key: 'NIFTY' } }
    let(:pick) { { security_id: '55111' } }

    it 'is deterministic for the same index/security/time-bucket' do
      id1 = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick)
      id2 = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick)

      expect(id1).to eq(id2)
    end

    it 'is deterministic for the same signal identity regardless of time' do
      signal = instance_double(TradingSignal, id: 42, respond_to?: true)
      allow(signal).to receive(:respond_to?).with(:id).and_return(true)

      id1 = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick, signal: signal)
      id2 = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick, signal: signal)

      expect(id1).to eq(id2)
    end

    it 'differs for different signal identities' do
      signal_a = instance_double(TradingSignal, id: 1)
      signal_b = instance_double(TradingSignal, id: 2)

      id_a = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick, signal: signal_a)
      id_b = described_class.build_client_order_id(index_cfg: index_cfg, pick: pick, signal: signal_b)

      expect(id_a).not_to eq(id_b)
    end

    it 'stays within DhanHQ correlation_id 25-character limit' do
      id = described_class.build_client_order_id(index_cfg: { key: 'BANKNIFTY' }, pick: { security_id: '1234567' })

      expect(id.length).to be <= 25
    end
  end

  # Orders::Entries::OrderExecutionService and Guards::BosStructureGuard call these with an
  # explicit receiver (`Entries::EntryGuard.method_name`). If any of them slip back below
  # `private`, that call raises NoMethodError at runtime for every order — and the specs above
  # never catch it because they stub OrderExecutionService.call entirely.
  describe 'methods required to be public for external callers' do
    %i[build_client_order_id extract_order_no create_tracker! create_paper_tracker! timeframe_to_interval].each do |method_name|
      it "exposes .#{method_name} as a public class method" do
        expect(described_class).to respond_to(method_name)
      end
    end
  end
end
