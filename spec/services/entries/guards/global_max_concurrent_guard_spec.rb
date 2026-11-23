# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::GlobalMaxConcurrentGuard do
  describe '.call' do
    let(:context) { {} }
    let(:trade_limits) do
      {
        global_max_concurrent_positions: max_concurrent,
        max_concurrent_same_direction: max_same_dir
      }
    end
    let(:max_same_dir) { nil }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(trade_limits: trade_limits)
    end

    context 'when global max concurrent positions is not configured' do
      let(:max_concurrent) { nil }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current positions are below the limit' do
      let(:max_concurrent) { 5 }

      before do
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(3)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when current positions equal the limit' do
      let(:max_concurrent) { 5 }

      before do
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(5)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to eq(blocked: 'global_max_concurrent_positions (5/5)')
      end
    end

    context 'when current positions exceed the limit' do
      let(:max_concurrent) { 3 }

      before do
        allow(PositionTracker).to receive_message_chain(:active, :count).and_return(5)
      end

      it 'blocks entry with count details' do
        result = described_class.call(context)
        expect(result).to eq(blocked: 'global_max_concurrent_positions (5/3)')
      end
    end

    context 'when max_concurrent_same_direction is configured' do
      let(:max_concurrent) { 5 }
      let(:max_same_dir) { 1 }
      let(:context) { { direction: 'bearish' } }

      context 'when existing same-direction positions reach limit' do
        before do
          allow(PositionTracker).to receive_message_chain(:active, :count).and_return(1)
          where_chain = double('ActiveRecord::Relation', count: 1)
          allow(PositionTracker).to receive_message_chain(:active, :where).with(side: 'long_pe').and_return(where_chain)
        end

        it 'blocks entry on same-direction concentration' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'max_concurrent_same_direction (1/1 for long_pe)')
        end
      end

      context 'when existing same-direction positions are below limit' do
        before do
          allow(PositionTracker).to receive_message_chain(:active, :count).and_return(1)
          where_chain = double('ActiveRecord::Relation', count: 0)
          allow(PositionTracker).to receive_message_chain(:active, :where).with(side: 'long_pe').and_return(where_chain)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end
  end
end

