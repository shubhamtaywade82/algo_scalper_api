# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instruments::LegacyResolver do
  let(:underlying) { create(:instrument, :nifty_index, security_id: '13') }
  let(:option) do
    create(:instrument, :nifty_call_option, underlying_symbol: 'NIFTY', security_id: '49081',
                                            underlying_security_id: '13', underlying_instrument: underlying)
  end

  describe '.resolve_pick' do
    it 'prefers instrument_id when present' do
      expect(described_class.resolve_pick(instrument_id: option.id)).to eq(option)
    end

    it 'resolves derivative_id through the consolidated instrument' do
      expect(described_class.resolve_pick(derivative_id: option.id)).to eq(option)
    end

    it 'falls back to security_id (FNO segment first)' do
      expect(described_class.resolve_pick(security_id: '49081')).to eq(option)
    end

    it 'reads string keys as well as symbol keys' do
      expect(described_class.resolve_pick('instrument_id' => option.id)).to eq(option)
    end

    it 'returns nil for an unresolvable pick' do
      expect(described_class.resolve_pick(security_id: 'UNKNOWN')).to be_nil
      expect(described_class.resolve_pick({})).to be_nil
      expect(described_class.resolve_pick(nil)).to be_nil
    end
  end

  describe '.by_legacy_id across the consolidation boundary' do
    it 'returns the direct instrument hit when it is a derivative contract' do
      expect(described_class.by_legacy_id(option.id)).to eq(option)
      expect(described_class.by_legacy_id(option.id, require_derivative: true)).to eq(option)
    end

    it 'returns nil when require_derivative is set and the id is not a contract' do
      plain = create(:instrument, :equity, security_id: '99992')

      expect(described_class.by_legacy_id(plain.id, require_derivative: true)).to be_nil
    end
  end
end
