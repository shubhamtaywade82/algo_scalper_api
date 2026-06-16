# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::RsiBiasGuard do
  before { allow(OptionsBuying::Mode).to receive(:rsi_bias_enabled?).and_return(true) }

  def context_for(direction)
    { index_cfg: { key: 'NIFTY' }, direction: direction }
  end

  it 'passes when the feature is disabled' do
    allow(OptionsBuying::Mode).to receive(:rsi_bias_enabled?).and_return(false)
    expect(described_class.call(context_for(:bullish))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'blocks a bullish (long-CE) entry when RSI bias is bearish' do
    allow(OptionsBuying::StateStore).to receive(:rsi_bias).with('NIFTY').and_return(:bearish)
    expect(described_class.call(context_for(:bullish))[:blocked]).to include('long (CE)')
  end

  it 'blocks a bearish (long-PE) entry when RSI bias is bullish' do
    allow(OptionsBuying::StateStore).to receive(:rsi_bias).with('NIFTY').and_return(:bullish)
    expect(described_class.call(context_for(:bearish))[:blocked]).to include('short (PE)')
  end

  it 'passes when bias aligns with the entry direction' do
    allow(OptionsBuying::StateStore).to receive(:rsi_bias).with('NIFTY').and_return(:bullish)
    expect(described_class.call(context_for(:bullish))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'passes when bias is neutral or absent' do
    allow(OptionsBuying::StateStore).to receive(:rsi_bias).with('NIFTY').and_return(nil)
    expect(described_class.call(context_for(:bearish))).to eq(Entries::EntryGuardPipeline::PASS)
  end

  it 'fails open when the state store raises' do
    allow(OptionsBuying::StateStore).to receive(:rsi_bias).and_raise(StandardError, 'down')
    expect(described_class.call(context_for(:bullish))).to eq(Entries::EntryGuardPipeline::PASS)
  end
end
