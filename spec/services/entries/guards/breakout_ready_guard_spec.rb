# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::BreakoutReadyGuard do
  let(:context) { { index_cfg: { key: 'NIFTY' }, direction: :bullish } }

  before do
    allow(OptionsBuying::Mode).to receive_messages(breakout_enabled?: true, positional_active?: false)
    allow(OptionsBuying::CarryPolicy).to receive(:expiry_day?).and_return(false)
  end

  context 'when resistance is not seeded' do
    before do
      allow(OptionsBuying::StateStore).to receive(:resistance).with('NIFTY').and_return(nil)
    end

    it 'passes' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when resistance is set but breakout is not armed' do
    before do
      allow(OptionsBuying::StateStore).to receive(:resistance).with('NIFTY').and_return(24_500.0)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bullish).and_return(false)
    end

    it 'blocks entry' do
      result = described_class.call(context)

      expect(result[:blocked]).to include('breakout not armed')
    end

    it 'passes when fast entry mode is enabled' do
      allow(Signal::FastEntryMode).to receive(:enabled?).and_return(true)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when breakout is armed' do
    before do
      allow(OptionsBuying::StateStore).to receive(:resistance).with('NIFTY').and_return(24_500.0)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bullish).and_return(true)
    end

    it 'passes' do
      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when a bearish (long-PE) entry is gated by support' do
    let(:context) { { index_cfg: { key: 'NIFTY' }, direction: :bearish } }

    it 'blocks when support is set but no bearish breakdown is armed' do
      allow(OptionsBuying::StateStore).to receive(:support).with('NIFTY').and_return(24_000.0)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bearish).and_return(false)

      result = described_class.call(context)

      expect(result[:blocked]).to include('bearish breakout not armed')
    end

    it 'passes when the bearish breakdown is armed' do
      allow(OptionsBuying::StateStore).to receive(:support).with('NIFTY').and_return(24_000.0)
      allow(OptionsBuying::StateStore).to receive(:breakout_ready?).with('NIFTY', direction: :bearish).and_return(true)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end

    it 'fails open (passes) when support is not seeded yet' do
      allow(OptionsBuying::StateStore).to receive(:support).with('NIFTY').and_return(nil)

      expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end

  context 'when state store fails' do
    before do
      allow(OptionsBuying::StateStore).to receive(:resistance).and_raise(Redis::BaseError, 'down')
    end

    it 'blocks entry' do
      result = described_class.call(context)

      expect(result[:blocked]).to eq('breakout guard unavailable')
    end
  end
end
