# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::DrawdownGuard do
  describe '.call' do
    let(:context) { {} }

    context 'when drawdown guard is not triggered' do
      before do
        allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(false)
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when drawdown guard is triggered' do
      before do
        allow(Portfolio::DrawdownGuard).to receive(:triggered?).and_return(true)
      end

      it 'blocks entry' do
        result = described_class.call(context)
        expect(result).to eq(blocked: 'drawdown_guard_active')
      end
    end
  end
end
