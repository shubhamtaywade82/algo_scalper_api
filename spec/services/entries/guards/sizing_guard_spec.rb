# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::SizingGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY' },
        pick: { symbol: 'NIFTY24MAR24000CE' },
        direction: :bullish,
        ltp: 150.0,
        entry_metadata: { permission: :scale_ready },
        permission: nil,
        scale_multiplier: 1.0
      }
    end

    let(:profile) do
      {
        allow_execution_only: true,
        max_lots_by_permission: { scale_ready: 3, execution_only: 2 }
      }
    end

    before do
      allow(Trading::InstrumentExecutionProfile).to receive(:for).with('NIFTY').and_return(profile)
      allow(Trading::LotCalculator).to receive(:lot_size_for).with('NIFTY').and_return(65)
      allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(2)
      allow(Capital::Allocator).to receive(:qty_for).and_return(130)
    end

    context 'with valid ltp and permissions' do
      it 'sets quantity and lot_size in context' do
        described_class.call(context)

        expect(context[:quantity]).to eq(130)
        expect(context[:lot_size]).to eq(65)
      end

      it 'returns PASS' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'respects the minimum of allocator qty and cap qty' do
        allow(Capital::Allocator).to receive(:qty_for).and_return(500)
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(1)

        described_class.call(context)

        # cap_lots * lot_size = 1 * 65 = 65, allocator qty = 500, so min = 65
        expect(context[:quantity]).to eq(65)
      end

      it 'ensures quantity is lot-aligned' do
        allow(Capital::Allocator).to receive(:qty_for).and_return(200)
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(4)

        described_class.call(context)

        # qty_by_cap = 4 * 65 = 260, allocator = 200, min = 200
        # 200 / 65 * 65 = 3 * 65 = 195 (lot-aligned)
        expect(context[:quantity]).to eq(195)
      end
    end

    context 'when permission comes from context directly' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: 150.0,
          entry_metadata: nil,
          permission: :execution_only,
          scale_multiplier: 1.0
        }
      end

      it 'uses context permission over entry_metadata' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when execution_only permission and profile disallows it' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: 150.0,
          entry_metadata: nil,
          permission: :execution_only,
          scale_multiplier: 1.0
        }
      end
      let(:profile) do
        {
          allow_execution_only: false,
          max_lots_by_permission: { scale_ready: 3, execution_only: 2 }
        }
      end

      before do
        allow(Trading::InstrumentExecutionProfile).to receive(:for).with('NIFTY').and_return(profile)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: 'execution_only_blocked_by_profile')
      end
    end

    context 'when entry_metadata contains permission' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: 150.0,
          entry_metadata: { permission: :execution_only },
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      before do
        allow(Trading::InstrumentExecutionProfile).to receive(:for).with('NIFTY').and_return(profile)
      end

      it 'uses permission from entry_metadata as fallback' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when no permission is specified anywhere' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: 150.0,
          entry_metadata: {},
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      it 'defaults to scale_ready' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when ltp is nil' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: nil,
          entry_metadata: { permission: :scale_ready },
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /invalid_entry_ltp/)
      end
    end

    context 'when ltp is zero' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: 0,
          entry_metadata: { permission: :scale_ready },
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /invalid_entry_ltp/)
      end
    end

    context 'when ltp is negative' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: -10.0,
          entry_metadata: { permission: :scale_ready },
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /invalid_entry_ltp/)
      end
    end

    context 'when ltp is infinite' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: { symbol: 'NIFTY24MAR24000CE' },
          direction: :bullish,
          ltp: Float::INFINITY,
          entry_metadata: { permission: :scale_ready },
          permission: nil,
          scale_multiplier: 1.0
        }
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /invalid_entry_ltp/)
      end
    end

    context 'when capital allocator returns nil' do
      before do
        allow(Capital::Allocator).to receive(:qty_for).and_return(nil)
      end

      it 'converts nil to 0 and blocks' do
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(0)

        result = described_class.call(context)
        expect(result).to include(blocked: 'capital_sizing_cap_zero')
      end
    end

    context 'when max_lots returns 0' do
      before do
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(0)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: 'capital_sizing_cap_zero')
      end
    end

    context 'when quantity is below lot minimum' do
      before do
        allow(Capital::Allocator).to receive(:qty_for).and_return(50)
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(1)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: 'quantity_below_lot_minimum')
      end
    end

    context 'when SafeNumeric.to_non_negative_integer caps the permission_cap' do
      let(:profile) do
        {
          allow_execution_only: true,
          max_lots_by_permission: { scale_ready: nil }
        }
      end

      before do
        allow(Trading::InstrumentExecutionProfile).to receive(:for).with('NIFTY').and_return(profile)
      end

      it 'handles nil permission cap gracefully' do
        allow(Trading::CapitalAllocator).to receive(:max_lots).and_return(0)

        result = described_class.call(context)
        expect(result).to include(blocked: 'capital_sizing_cap_zero')
      end
    end
  end
end
