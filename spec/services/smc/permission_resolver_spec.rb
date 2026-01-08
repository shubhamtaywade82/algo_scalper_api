# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::PermissionResolver do
  describe '.call' do
    context 'when HTF is neutral' do
      it 'returns blocked' do
        htf = { premium_discount: { premium: false, discount: false }, swing_structure: { trend: :range } }
        mtf = { swing_structure: { trend: :bullish, choch: false } }
        ltf = { liquidity: {}, swing_structure: { choch: false } }
        avrz = { rejection: false }

        result = described_class.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
        expect(result.permission).to eq(:blocked)
        expect(result.bias).to eq(:neutral)
        expect(result.max_lots).to eq(0)
      end
    end

    context 'when timing is missing' do
      it 'returns execution_only' do
        htf = { premium_discount: { discount: true }, swing_structure: { trend: :bullish } }
        mtf = { swing_structure: { trend: :bullish, choch: false } }
        ltf = { liquidity: { sell_side_taken: false }, swing_structure: { choch: false } }
        avrz = { rejection: false }

        result = described_class.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
        expect(result.permission).to eq(:execution_only)
        expect(result.max_lots).to eq(1)
        expect(result.execution_mode).to eq(:scalp_only)
      end
    end

    context 'when timing is present' do
      context 'when strict trigger is missing' do
        it 'returns scale_ready' do
          htf = { premium_discount: { discount: true }, swing_structure: { trend: :bullish } }
          mtf = { swing_structure: { trend: :bullish, choch: false } }
          ltf = { liquidity: { sell_side_taken: false }, swing_structure: { choch: true } }
          avrz = { rejection: true }

          result = described_class.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
          expect(result.permission).to eq(:scale_ready)
          expect(result.max_lots).to eq(3)
          expect(result.entry_signal).to be_nil
        end
      end

      context 'when strict trigger is present' do
        it 'returns full_deploy' do
          htf = { premium_discount: { discount: true }, swing_structure: { trend: :bullish } }
          mtf = { swing_structure: { trend: :bullish, choch: false } }
          ltf = { liquidity: { sell_side_taken: true }, swing_structure: { choch: true } }
          avrz = { rejection: true }

          result = described_class.call(htf: htf, mtf: mtf, ltf: ltf, avrz: avrz)
          expect(result.permission).to eq(:full_deploy)
          expect(result.max_lots).to eq(4)
          expect(result.entry_signal).to eq(:call)
        end
      end
    end
  end
end

