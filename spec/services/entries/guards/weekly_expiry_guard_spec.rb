# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::WeeklyExpiryGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: index_cfg,
        pick: pick,
        is_supertrend: is_supertrend,
        is_paper: is_paper
      }
    end
    let(:index_cfg) { { key: 'NIFTY', segment: 'NFO-OPT' } }
    let(:pick) { { security_id: '12345', segment: 'NFO-OPT', derivative_id: nil } }
    let(:is_supertrend) { false }
    let(:is_paper) { false }
    let(:derivative) { instance_double(Derivative, expiry_flag: 'W-NIFTY') }

    context 'when in supertrend mode' do
      let(:is_supertrend) { true }

      it 'allows entry without checking expiry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when in paper trading mode' do
      let(:is_paper) { true }

      it 'allows entry without checking expiry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when index is not NIFTY or SENSEX' do
      let(:index_cfg) { { key: 'BANKNIFTY', segment: 'NFO-OPT' } }

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when index is NIFTY or SENSEX' do
      let(:index_cfg) { { key: 'NIFTY', segment: 'NFO-OPT' } }

      before do
        allow(Derivative).to receive(:find_by).and_return(derivative)
      end

      context 'and contract is a weekly expiry' do
        let(:derivative) { instance_double(Derivative, expiry_flag: 'W-NIFTY') }

        it 'allows entry' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'and contract is NOT a weekly expiry (monthly)' do
        let(:derivative) { instance_double(Derivative, expiry_flag: 'NIFTY') }

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'weekly_only_expiry_rule')
        end
      end

      context 'and derivative is not found' do
        let(:derivative) { nil }

        before do
          allow(Derivative).to receive(:find_by).and_return(nil)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'weekly_only_expiry_rule')
        end
      end

      context 'and an error occurs during lookup' do
        before do
          allow(Derivative).to receive(:find_by).and_raise(StandardError.new('lookup error'))
        end

        it 'blocks entry (fails closed)' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'weekly_only_expiry_rule')
        end
      end
    end
  end

  describe '#initialize' do
    context 'when entry_metadata contains supertrend contract' do
      let(:context) do
        {
          index_cfg: { key: 'NIFTY' },
          pick: {},
          is_supertrend: nil,
          is_paper: false,
          entry_metadata: { entry_contract: 'supertrend_machine_v1' }
        }
      end

      it 'sets is_supertrend to true' do
        guard = described_class.new(context)
        # We can't directly test instance variables, but we can test the behavior
        # by calling the method that uses is_supertrend
        allow(guard).to receive(:weekly_contract?).and_return(false)
        result = guard.call
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
