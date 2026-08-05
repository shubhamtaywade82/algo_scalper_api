# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::GlobalMaxConcurrentGuard do
  describe '.call' do
    let(:context) { {} }
    let(:algo_config) { instance_double(AlgoConfig::Configuration) }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(algo_config)
      allow(algo_config).to receive(:dig).with(:trade_limits, :global_max_concurrent_positions).and_return(max_concurrent)
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
  end
end
