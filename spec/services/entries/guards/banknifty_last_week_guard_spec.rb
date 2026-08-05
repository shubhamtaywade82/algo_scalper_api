# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::BankniftyLastWeekGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: index_key } } }
    let(:index_key) { 'BANKNIFTY' }

    context 'when index is not BANKNIFTY' do
      let(:index_key) { 'NIFTY' }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when index is BANKNIFTY' do
      let(:index_key) { 'BANKNIFTY' }

      context 'and it is the last week before monthly expiry' do
        before do
          allow(Entries::EntryGuard).to receive(:banknifty_last_week?).and_return(true)
        end

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and it is NOT the last week before monthly expiry' do
        before do
          allow(Entries::EntryGuard).to receive(:banknifty_last_week?).and_return(false)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'BANKNIFTY entry only in last week before monthly expiry')
        end
      end
    end
  end
end
