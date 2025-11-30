# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::RuleResult do
  describe '.exit' do
    it 'creates exit result with reason' do
      result = described_class.exit(reason: 'SL HIT')
      expect(result.action).to eq(:exit)
      expect(result.reason).to eq('SL HIT')
      expect(result.exit?).to be true
    end

    it 'creates exit result with metadata' do
      metadata = { pnl_pct: -4.0, sl_pct: 2.0 }
      result = described_class.exit(reason: 'SL HIT', metadata: metadata)
      expect(result.metadata).to eq(metadata)
    end
  end

  describe '.no_action' do
    it 'creates no_action result' do
      result = described_class.no_action
      expect(result.action).to eq(:no_action)
      expect(result.no_action?).to be true
      expect(result.reason).to be_nil
    end
  end

  describe '.skip' do
    it 'creates skip result' do
      result = described_class.skip
      expect(result.action).to eq(:skip)
      expect(result.skip?).to be true
      expect(result.reason).to be_nil
    end
  end

  describe '#exit?' do
    it 'returns true for exit action' do
      result = described_class.exit(reason: 'SL HIT')
      expect(result.exit?).to be true
    end

    it 'returns false for other actions' do
      expect(described_class.no_action.exit?).to be false
      expect(described_class.skip.exit?).to be false
    end
  end

  describe '#no_action?' do
    it 'returns true for no_action' do
      expect(described_class.no_action.no_action?).to be true
    end

    it 'returns false for other actions' do
      expect(described_class.exit(reason: 'SL').no_action?).to be false
      expect(described_class.skip.no_action?).to be false
    end
  end

  describe '#skip?' do
    it 'returns true for skip action' do
      expect(described_class.skip.skip?).to be true
    end

    it 'returns false for other actions' do
      expect(described_class.exit(reason: 'SL').skip?).to be false
      expect(described_class.no_action.skip?).to be false
    end
  end
end
