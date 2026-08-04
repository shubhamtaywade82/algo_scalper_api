# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::CompressionSetupGuard do
  let(:instrument) { instance_double(Instrument) }
  let(:context) { { index_cfg: { key: 'NIFTY' }, instrument: instrument } }

  before do
    allow(OptionsBuying::Mode).to receive(:compression_enabled?).and_return(true)
  end

  context 'when intraday mode' do
    before do
      allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(false)
    end

    it 'passes without compression check' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when positional carry is active and not compressed' do
    before do
      allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
      allow(OptionsBuying::CarryPolicy).to receive(:carry_allowed?).and_return(true)
      allow(OptionsBuying::ATRCompressionChecker).to receive_messages(compressed?: false, setup_ratio: 0.55)
    end

    it 'blocks entry' do
      result = described_class.call(context)

      expect(result[:blocked]).to include('compression setup required')
    end
  end

  context 'when positional mode is on but carry is not allowed' do
    before do
      allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
      allow(OptionsBuying::CarryPolicy).to receive(:carry_allowed?).and_return(false)
    end

    it 'passes without compression check' do
      expect(OptionsBuying::ATRCompressionChecker).not_to receive(:compressed?)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when compression check fails' do
    before do
      allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
      allow(OptionsBuying::CarryPolicy).to receive(:carry_allowed?).and_return(true)
      allow(OptionsBuying::ATRCompressionChecker).to receive(:compressed?).and_raise(StandardError, 'boom')
    end

    it 'blocks entry' do
      result = described_class.call(context)

      expect(result[:blocked]).to eq('compression guard unavailable')
    end
  end
end
