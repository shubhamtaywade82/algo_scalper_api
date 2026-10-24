# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::BosContractGuard do
  describe '.call' do
    let(:context) { { entry_metadata: entry_metadata } }
    let(:entry_metadata) { { entry_contract: 'bos_machine_v1' } }

    context 'when BOS contract is present in metadata' do
      before do
        allow(Entries::EntryGuard).to receive(:bos_contract_present?).with(entry_metadata).and_return(true)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when BOS contract is missing in metadata' do
      before do
        allow(Entries::EntryGuard).to receive(:bos_contract_present?).with(entry_metadata).and_return(false)
      end

      it 'blocks entry with metadata details' do
        result = described_class.call(context)
        expect(result).to include(blocked: /BOS contract missing/)
        expect(result[:blocked]).to include(entry_metadata.inspect)
      end
    end

    context 'when entry_metadata is nil' do
      let(:entry_metadata) { nil }

      before do
        allow(Entries::EntryGuard).to receive(:bos_contract_present?).with(nil).and_return(false)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to include(blocked: /BOS contract missing/)
      end
    end
  end
end
